import SwiftUI

enum AppRoute {
    case loading
    case invite
    case onboarding
    case main
}

struct AppRouter: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auth = AuthService.shared
    @State private var route: AppRoute = .loading
    /// Branded splash sits above the first destination, then eases out.
    @State private var showLaunchOverlay = true
    @State private var launchExiting = false
    @State private var launchStartedAt = Date()
    @State private var isBootstrapping = false
    @State private var isDismissingLaunch = false

    var body: some View {
        ZStack {
            #if targetEnvironment(macCatalyst)
            // Full-window parchment — content is centered; backgrounds inside Home/Onboarding
            // only cover the readable column, which left bare sides on wide Mac windows.
            if route != .loading {
                ThemeBackground(ambientMotion: route == .onboarding || route == .invite)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            #endif

            if route != .loading {
                destination
                    .oracyMacReadableColumn()
                    .transition(.opacity)
            }

            if showLaunchOverlay {
                LoadingView(isExiting: launchExiting)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(
            reduceMotion ? .easeOut(duration: 0.22) : .easeInOut(duration: 0.5),
            value: showLaunchOverlay
        )
        .animation(
            reduceMotion ? .easeOut(duration: 0.22) : .easeInOut(duration: 0.45),
            value: route
        )
        .appErrorOverlay()
        .environment(\.launchOverlayActive, showLaunchOverlay)
        .task {
            await bootstrap()
        }
        .onChange(of: auth.profile?.onboardingCompleted) { _, completed in
            guard auth.isAuthenticated, !InviteService.shared.needsInviteGate else { return }
            setRoute(completed == true ? .main : .onboarding)
        }
        .onChange(of: auth.needsOnboarding) { _, needs in
            guard auth.isAuthenticated, !InviteService.shared.needsInviteGate else { return }
            if needs {
                setRoute(.onboarding)
            }
        }
        .onChange(of: auth.profile?.streakCount) { _, _ in
            Task { await PracticeReminderService.shared.refreshSchedule() }
        }
        .onChange(of: auth.profile?.lastPracticeDate) { _, _ in
            Task { await PracticeReminderService.shared.refreshSchedule() }
        }
        .onChange(of: auth.userId) { _, newId in
            Task { await InviteService.shared.syncAfterAuthChange() }
            // Session wiped mid-flight (stale JWT) — re-bootstrap into anon / onboarding.
            guard newId == nil, route == .main || route == .onboarding else { return }
            Task { await bootstrap() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await PracticeReminderService.shared.refreshSchedule() }
            } else if phase == .background {
                AnalyticsService.shared.track(.appBackgrounded)
                AnalyticsService.shared.flushSoon()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .backendModeDidChange)) { _ in
            Task { await bootstrap() }
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch route {
        case .loading:
            EmptyView()
        case .invite:
            InviteGateView {
                resolveRouteAfterInvite()
            }
        case .onboarding:
            OnboardingView(onComplete: {
                setRoute(.main)
            })
        case .main:
            MainTabView()
        }
    }

    private func bootstrap() async {
        guard !isBootstrapping else { return }
        isBootstrapping = true
        defer { isBootstrapping = false }

        // Fast path: local JWT only — do not block splash on network verify.
        let hadLocalSession = await auth.restoreLocalSessionForLaunch()
        if hadLocalSession {
            resolveRouteFromLocalSession()
        }

        // Full network verify + remote config (may take seconds; splash already dismissing).
        await auth.initialize()
        await RemoteConfigService.shared.refresh()

        if !auth.isAuthenticated {
            try? await auth.signInAnonymously()
        }

        await InviteService.shared.syncAfterAuthChange()

        AnalyticsService.shared.startSession()
        resolveRouteAfterInvite()

        // Reminders off the critical path for launch feel.
        Task {
            await PracticeReminderService.shared.refreshSchedule()
        }
    }

    /// Early route using local JWT + onboarding cache (no network). Cache miss → main.
    private func resolveRouteFromLocalSession() {
        let next: AppRoute
        if InviteService.shared.hasUnlockedInvite == false,
           RemoteConfigService.shared.isInviteOnlyEnabled {
            next = .invite
        } else if auth.preferredLaunchRouteIsOnboarding {
            next = .onboarding
        } else {
            next = .main
        }
        setRoute(next)
    }

    private func resolveRouteAfterInvite() {
        let next: AppRoute
        if InviteService.shared.needsInviteGate {
            next = .invite
        } else if auth.needsOnboarding {
            next = .onboarding
        } else if auth.isAuthenticated {
            next = .main
        } else {
            next = .loading
        }
        setRoute(next)
    }

    private func setRoute(_ next: AppRoute) {
        let name: String
        switch next {
        case .loading: name = "loading"
        case .invite: name = "invite"
        case .onboarding: name = "onboarding"
        case .main: name = "main"
        }
        AnalyticsService.shared.track(.routeResolved, ["route": name])

        guard next != .loading else {
            route = .loading
            showLaunchOverlay = true
            launchExiting = false
            isDismissingLaunch = false
            launchStartedAt = Date()
            return
        }

        route = next
        guard showLaunchOverlay, !isDismissingLaunch else { return }
        Task { await dismissLaunchOverlay() }
    }

    @MainActor
    private func dismissLaunchOverlay() async {
        guard showLaunchOverlay, !isDismissingLaunch else { return }
        isDismissingLaunch = true

        // Hold long enough for the logo bounce to settle, then ease out.
        let minimumVisible: TimeInterval = reduceMotion ? 0.35 : 1.15
        let elapsed = Date().timeIntervalSince(launchStartedAt)
        if elapsed < minimumVisible {
            try? await Task.sleep(for: .seconds(minimumVisible - elapsed))
        }

        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .easeInOut(duration: 0.55)) {
            launchExiting = true
        }

        try? await Task.sleep(for: .seconds(reduceMotion ? 0.15 : 0.42))

        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.35)) {
            showLaunchOverlay = false
        }
    }
}

#if targetEnvironment(macCatalyst)
private extension View {
    /// Centers a phone/iPad-width column so parchment UI doesn’t stretch on wide Mac windows.
    func oracyMacReadableColumn() -> some View {
        frame(maxWidth: 920)
            .frame(maxWidth: .infinity)
    }
}
#else
private extension View {
    func oracyMacReadableColumn() -> some View { self }
}
#endif

struct LoadingView: View {
    var isExiting: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var lineIndex = 0

    private let lines = [
        "One minute. One thought.",
        "Speak once. Mean it.",
        "Find the words.",
        "Warm up your voice."
    ]

    private var contentVisible: Bool { appeared }

    var body: some View {
        ZStack {
            ThemeBackground(ambientMotion: true)

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 28) {
                    Image("app-logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 21.5, style: .continuous))
                        .shadow(
                            color: Theme.shadow,
                            radius: contentVisible ? 18 : 4,
                            y: contentVisible ? 10 : 2
                        )
                        .scaleEffect(isExiting ? 1.08 : (appeared ? 1 : 0.86))
                        .opacity(contentVisible ? 1 : 0)
                        .accessibilityHidden(true)

                    VStack(spacing: 10) {
                        Text("Oracy")
                            .font(Theme.fraunces(42, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .opacity(contentVisible ? 1 : 0)
                            .offset(y: contentVisible ? 0 : 10)

                        Text(lines[lineIndex])
                            .font(Theme.grotesk(17, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .id(lineIndex)
                            .transition(
                                reduceMotion
                                    ? .opacity
                                    : .asymmetric(
                                        insertion: .opacity.combined(with: .offset(y: 8)),
                                        removal: .opacity.combined(with: .offset(y: -6))
                                    )
                            )
                            .opacity(contentVisible ? 1 : 0)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Oracy. \(lines[lineIndex])")
                }

                Spacer()

                if AppConfig.useMockBackend {
                    Theme.caption("Starting in mock mode")
                        .padding(.bottom, 36)
                        .opacity(contentVisible ? 0.9 : 0)
                } else if !AppConfig.isSupabaseConfigured {
                    Theme.caption("Configure Secrets.plist to connect to Supabase\nor set BACKEND_MODE to mock")
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 36)
                        .opacity(contentVisible ? 0.9 : 0)
                }
            }
            .padding(.horizontal, 32)
            .scaleEffect(isExiting ? 0.97 : 1)
        }
        .opacity(isExiting ? 0 : 1)
        .allowsHitTesting(!isExiting)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .themeBounce) {
                appeared = true
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.6))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.45)) {
                    lineIndex = (lineIndex + 1) % lines.count
                }
            }
        }
    }
}
