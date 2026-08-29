import SwiftUI
import UIKit
import UserNotifications
import RevenueCat

struct SettingsView: View {
    /// When true, land with a tiny shake + haptic on the Pro card (from “Free · left this week”).
    var nudgeProCard: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var showPaywall = false
    @State private var proNudgeOffset: CGFloat = 0
    @State private var proNudgeTilt: Double = 0
    @State private var showCustomerCenter = false
    #if DEBUG
    @State private var showDeveloper = false
    @State private var versionTapCount = 0
    private let versionTapThreshold = 5
    #endif
    @State private var showShare = false
    @State private var practiceReminders = PracticeReminderService.shared.isEnabled
    @State private var reminderTime = PracticeReminderService.shared.reminderTime
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var restoreMessage: String?
    @State private var subscriptions = SubscriptionService.shared
    @State private var membershipOffCopy = SettingsPlanCopy.random()

    private let instagramURL = URL(string: "https://instagram.com/oracy")!
    private let xURL = URL(string: "https://x.com/oracy")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    planHero
                    if shouldShowProCard {
                        proUpsellCard
                    } else if subscriptions.isMembershipPlanEnabled, subscriptions.isProActive {
                        manageSubscriptionButton
                    }

                    settingsSection(title: "Account") {
                        NavigationLink {
                            MyAccountView()
                        } label: {
                            settingsRow(title: "My Account", systemImage: "person.crop.circle")
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(title: "Notifications") {
                        VStack(spacing: 0) {
                            Toggle(isOn: $practiceReminders) {
                                settingsRowLabel(title: "Practice reminders", systemImage: "bell.fill")
                            }
                            .tint(Theme.accent)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                            .onChange(of: practiceReminders) { _, enabled in
                                Task { await setPracticeRemindersEnabled(enabled) }
                            }

                            if practiceReminders {
                                Divider().opacity(0.28)
                                    .padding(.horizontal, 18)

                                DatePicker(
                                    "Reminder time",
                                    selection: $reminderTime,
                                    displayedComponents: .hourAndMinute
                                )
                                .datePickerStyle(.compact)
                                .tint(Theme.accent)
                                .font(Theme.grotesk(16, weight: .medium))
                                .padding(.horizontal, 18)
                                .padding(.vertical, 12)
                                .onChange(of: reminderTime) { _, newValue in
                                    PracticeReminderService.shared.reminderTime = newValue
                                }

                                if notificationStatus == .denied {
                                    Text("Notifications are off in iOS Settings. Enable them to get reminders.")
                                        .font(Theme.grotesk(13, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                        .padding(.horizontal, 18)
                                        .padding(.bottom, 14)
                                }
                            }
                        }
                        .background(Theme.cardBackground.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }

                    settingsSection(title: "Social") {
                        Button {
                            Haptics.soft()
                            showShare = true
                        } label: {
                            settingsRow(title: "Share Oracy", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.plain)

                        if RemoteConfigService.shared.isReferralRewardsEnabled
                            || RemoteConfigService.shared.isInviteOnlyEnabled {
                            NavigationLink {
                                EnterReferralCodeView()
                            } label: {
                                settingsRow(title: "Enter referral code", systemImage: "gift")
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    settingsSection(title: "Follow us") {
                        Link(destination: instagramURL) {
                            settingsRow(title: "Instagram", systemImage: "camera", showsChevron: true)
                        }
                        .buttonStyle(.plain)

                        Link(destination: xURL) {
                            settingsRow(title: "X", systemImage: "at", showsChevron: true)
                        }
                        .buttonStyle(.plain)
                    }

                    settingsSection(title: "Other") {
                        NavigationLink {
                            AboutOracyView()
                        } label: {
                            settingsRow(title: "About Oracy", systemImage: "info.circle")
                        }
                        .buttonStyle(.plain)

                        Button {
                            Task { await restorePurchases() }
                        } label: {
                            settingsRow(title: "Restore purchases", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            PrivacyView(embedded: true)
                        } label: {
                            settingsRow(title: "Privacy & Data", systemImage: "hand.raised")
                        }
                        .buttonStyle(.plain)
                    }

                    versionFooter
                        .padding(.top, 8)
                        .padding(.bottom, 24)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            .themeBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
            }
            #if DEBUG
            .navigationDestination(isPresented: $showDeveloper) {
                DeveloperSettingsView()
            }
            #endif
            .fullScreenCover(isPresented: $showPaywall) {
                OracyProPaywallView()
            }
            .sheet(isPresented: $showCustomerCenter) {
                OracyCustomerCenterView()
            }
            .sheet(isPresented: $showShare) {
                SettingsShareSheet(items: shareItems)
            }
            .alert("Restore", isPresented: .init(
                get: { restoreMessage != nil },
                set: { if !$0 { restoreMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(restoreMessage ?? "")
            }
            .task {
                membershipOffCopy = SettingsPlanCopy.random()
                practiceReminders = PracticeReminderService.shared.isEnabled
                reminderTime = PracticeReminderService.shared.reminderTime
                notificationStatus = await PracticeReminderService.shared.authorizationStatus()
                await subscriptions.refresh()
                await subscriptions.loadOfferings()
                await nudgeProCardIfNeeded()
            }
        }
        .appErrorOverlay()
    }

    private func nudgeProCardIfNeeded() async {
        guard nudgeProCard, shouldShowProCard else { return }
        try? await Task.sleep(for: .milliseconds(320))
        guard !Task.isCancelled else { return }
        Haptics.light()
        let frames: [(x: CGFloat, tilt: Double)] = [
            (5, 1.4), (-4, -1.1), (3, 0.8), (-2, -0.5), (0, 0)
        ]
        for frame in frames {
            withAnimation(.spring(response: 0.16, dampingFraction: 0.62)) {
                proNudgeOffset = frame.x
                proNudgeTilt = frame.tilt
            }
            try? await Task.sleep(for: .milliseconds(58))
            guard !Task.isCancelled else { return }
        }
    }

    // MARK: Plan hero

    private var planHero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(planTitle)
                .font(Theme.grotesk(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            if let subtitle = planSubtitle {
                Text(subtitle)
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 2)
    }

    private var planTitle: String {
        if !subscriptions.isMembershipPlanEnabled {
            return membershipOffCopy.title
        }
        switch subscriptions.membership {
        case .pro:
            return "You’re on Oracy Pro"
        case .trial:
            return "You’re on a Pro trial"
        case .free:
            return "You’re on the Free plan"
        }
    }

    private var planSubtitle: String? {
        if !subscriptions.isMembershipPlanEnabled {
            return membershipOffCopy.subtitle
        }
        switch subscriptions.membership {
        case .pro:
            return "Unlimited practice and full AI feedback."
        case .trial(let endsAt):
            if let endsAt {
                let formatted = endsAt.formatted(date: .abbreviated, time: .omitted)
                return "Talk better with no limits · trial ends \(formatted)."
            }
            return "Talk better with no limits during your trial."
        case .free:
            let left = subscriptions.weeklyFreeRemaining
            let limit = subscriptions.weeklySessionLimit
            return "Talk better with up to \(limit) sessions a week · \(left) left."
        }
    }

    private var shouldShowProCard: Bool {
        subscriptions.isMembershipPlanEnabled && !subscriptions.isProActive
    }

    private var manageSubscriptionButton: some View {
        Button {
            Haptics.soft()
            showCustomerCenter = true
        } label: {
            HStack {
                Text("Manage subscription")
                    .font(Theme.grotesk(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(Theme.cardBackground.opacity(0.72))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Pro upsell card

    private var proUpsellCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                proCardArt
                    .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Oracy Pro")
                        .font(Theme.fraunces(20, weight: .bold))
                        .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))

                    VStack(alignment: .leading, spacing: 5) {
                        proBullet("Unlimited one-minute analyses")
                        proBullet("Full AI feedback every session")
                        proBullet("Pro mark on your profile")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button {
                Haptics.soft()
                showPaywall = true
            } label: {
                HStack(spacing: 8) {
                    Text(proCTATitle)
                        .font(Theme.grotesk(16, weight: .semibold))
                        .foregroundStyle(Color.white)
                    ProTag(surface: .onAccent)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background {
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.34),
                                    Color.white.opacity(0.12),
                                    Color(red: 0.92, green: 0.62, blue: 0.48).opacity(0.45)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .overlay {
                    Capsule()
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.55),
                                    Color.white.opacity(0.12)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
                .background {
                    Capsule()
                        .fill(.ultraThinMaterial)
                        .opacity(0.35)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(proCTATitle)
        }
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.72, green: 0.42, blue: 0.34),
                            Color(red: 0.48, green: 0.28, blue: 0.24),
                            Color(red: 0.22, green: 0.16, blue: 0.14)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        }
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 18, y: 10)
        .offset(x: proNudgeOffset)
        .rotationEffect(.degrees(proNudgeTilt))
    }

    private var proCTATitle: String {
        if subscriptions.isEligibleForTrial {
            return "Try free · then \(proPriceLabel)"
        }
        return "Try for \(proPriceLabel)"
    }

    private var proPriceLabel: String {
        if let package = subscriptions.monthlyPackage ?? subscriptions.annualPackage {
            return package.storeProduct.localizedPriceString
        }
        return "₹299"
    }

    private var proCardArt: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.28),
                            Color.white.opacity(0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            AppLogoMark(size: 48)
                .scaleEffect(0.9)
        }
    }

    private func proBullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.white.opacity(0.85))
                .padding(.top, 3)
            Text(text)
                .font(Theme.grotesk(13, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Sections

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.grotesk(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.grotesk(13))
                        .foregroundStyle(Theme.textSecondary.opacity(0.85))
                }
            }
            .padding(.horizontal, 4)

            VStack(spacing: 8) {
                content()
            }
        }
    }

    private func settingsRow(
        title: String,
        systemImage: String,
        showsChevron: Bool = true
    ) -> some View {
        HStack(spacing: 14) {
            settingsRowLabel(title: title, systemImage: systemImage)
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary.opacity(0.55))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground.opacity(0.72))
        .clipShape(Capsule())
        .contentShape(Capsule())
    }

    private func settingsRowLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 22)

            Text(title)
                .font(Theme.grotesk(16, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
        }
    }

    private var versionFooter: some View {
        #if DEBUG
        Button {
            versionTapCount += 1
            Haptics.light()
            if versionTapCount >= versionTapThreshold {
                versionTapCount = 0
                Haptics.success()
                showDeveloper = true
            }
        } label: {
            versionFooterLabel
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Oracy version 1.0.0")
        .accessibilityHint("Tap five times for developer settings")
        #else
        versionFooterLabel
            .accessibilityLabel("Oracy version 1.0.0")
        #endif
    }

    private var versionFooterLabel: some View {
        VStack(spacing: 4) {
            Text("Oracy")
                .font(Theme.fraunces(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Version 1.0.0")
                .font(Theme.grotesk(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var shareItems: [Any] {
        [
            "I’m practicing speaking with Oracy — one minute at a time.",
            URL(string: "https://oracy.app") as Any
        ].compactMap { $0 }
    }

    private func setPracticeRemindersEnabled(_ enabled: Bool) async {
        if enabled {
            let status = await PracticeReminderService.shared.authorizationStatus()
            if status == .notDetermined {
                let granted = await PracticeReminderService.shared.requestAuthorization()
                notificationStatus = await PracticeReminderService.shared.authorizationStatus()
                if !granted {
                    practiceReminders = false
                    PracticeReminderService.shared.isEnabled = false
                    return
                }
            } else if status == .denied {
                notificationStatus = .denied
                // Keep toggle on so the denied hint shows; user can open iOS Settings.
            } else {
                notificationStatus = status
            }
        } else {
            notificationStatus = await PracticeReminderService.shared.authorizationStatus()
        }

        PracticeReminderService.shared.isEnabled = enabled
        await PracticeReminderService.shared.refreshSchedule()
    }

    private func restorePurchases() async {
        let ok = await subscriptions.restore()
        if ok, subscriptions.isProActive {
            restoreMessage = "Oracy Pro is active again."
        } else if ok {
            restoreMessage = "No active Pro subscription found for this Apple ID."
        } else {
            restoreMessage = subscriptions.lastErrorMessage ?? "Couldn’t restore right now. Please try again."
        }
    }
}

// MARK: - Rotating copy (membership off)

private struct SettingsPlanCopy {
    var title: String
    var subtitle: String

    static func random() -> SettingsPlanCopy {
        let options: [(String, String)] = [
            ("Speak with intention", "One minute a day. Clearer, calmer, more you."),
            ("Show up for a minute", "Small practice that compounds."),
            ("Find your voice", "Out loud, on purpose."),
            ("Keep the streak honest", "One prompt. One take. Real feedback."),
            ("Talk it through", "Sixty seconds to get sharper."),
            ("Practice out loud", "The shortest path to sounding like yourself."),
            ("Make it land", "Clarity over perfection."),
            ("One clear minute", "No scripts. Just you, speaking.")
        ]
        let pick = options.randomElement() ?? options[0]
        return SettingsPlanCopy(title: pick.0, subtitle: pick.1)
    }
}

// MARK: - Share sheet

private struct SettingsShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Developer (DEBUG only — multi-tap version footer)

#if DEBUG
struct DeveloperSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptions = SubscriptionService.shared

    @AppStorage("debug.forceCelebrate") private var forceCelebrate = false
    @State private var debugStreak = 0
    @State private var debugWeekDays = 0
    @State private var debugYearDays = 0
    @State private var debugBusySessions = 2
    @State private var previewStatus = ""
    @State private var selectedBackend = AppConfig.backendMode
    @State private var isSwitchingBackend = false
    @State private var backendSwitchMessage: String?
    #if DEBUG
    @State private var debugForcePro = UserDefaults.standard.bool(forKey: "debug.forcePro")
    @State private var debugForceTrial = UserDefaults.standard.bool(forKey: "debug.forceTrial")
    @State private var debugForceMembershipPlan = UserDefaults.standard.bool(forKey: "debug.forceMembershipPlan")
    @State private var debugForceInviteOnly = UserDefaults.standard.bool(forKey: "debug.forceInviteOnly")
    @State private var debugForceRevenueCatPaywall = UserDefaults.standard.bool(forKey: "debug.forceRevenueCatPaywall")
    @State private var debugForceReferralRewards = UserDefaults.standard.object(forKey: "debug.forceReferralRewards") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "debug.forceReferralRewards")
    @State private var debugForcePhoneAuth = UserDefaults.standard.object(forKey: "debug.forcePhoneAuth") == nil
        ? true
        : UserDefaults.standard.bool(forKey: "debug.forcePhoneAuth")
    @State private var debugForceGoogleAuth = UserDefaults.standard.object(forKey: "debug.forceGoogleAuth") == nil
        ? false
        : UserDefaults.standard.bool(forKey: "debug.forceGoogleAuth")
    @State private var debugReferralFriends = MockStore.shared.referralInviteCount()
    #endif

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Backend")
                        .font(Theme.grotesk(15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)

                    Picker("Backend", selection: $selectedBackend) {
                        ForEach(BackendMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isSwitchingBackend)
                    .onChange(of: selectedBackend) { _, mode in
                        guard mode != AppConfig.backendMode else { return }
                        Task { await switchBackend(to: mode) }
                    }

                    if isSwitchingBackend {
                        ProgressView()
                            .tint(Theme.accent)
                    } else if selectedBackend == .supabase, !AppConfig.isSupabaseConfigured {
                        Text("Add SUPABASE_URL and SUPABASE_ANON_KEY in Secrets.plist.")
                            .font(Theme.grotesk(12))
                            .foregroundStyle(Theme.accent)
                    } else {
                        Text(selectedBackend == .mock
                              ? "Local data — no network required."
                              : "Live Supabase + edge functions.")
                            .font(Theme.grotesk(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Environment")
            }

            #if DEBUG
            Section("Debug flags") {
                NavigationLink {
                    SystemStatusView()
                } label: {
                    HStack {
                        Text("System Status")
                        Spacer()
                        Text("Debug")
                            .font(Theme.grotesk(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Toggle("Force Oracy Pro", isOn: $debugForcePro)
                    .onChange(of: debugForcePro) { _, on in
                        if on { debugForceTrial = false }
                        subscriptions.setDebugForcePro(on)
                    }

                Toggle("Force Pro trial", isOn: $debugForceTrial)
                    .onChange(of: debugForceTrial) { _, on in
                        if on { debugForcePro = false }
                        subscriptions.setDebugForceTrial(on)
                    }

                Toggle("Force membership plan flag", isOn: $debugForceMembershipPlan)
                    .onChange(of: debugForceMembershipPlan) { _, on in
                        RemoteConfigService.shared.setDebugForceMembershipPlan(on ? true : nil)
                        Task { await subscriptions.refresh() }
                    }

                Toggle("Force invite-only flag", isOn: $debugForceInviteOnly)
                    .onChange(of: debugForceInviteOnly) { _, on in
                        RemoteConfigService.shared.setDebugForceInviteOnly(on ? true : nil)
                    }

                Toggle("Force RevenueCat dashboard paywall", isOn: $debugForceRevenueCatPaywall)
                    .onChange(of: debugForceRevenueCatPaywall) { _, on in
                        RemoteConfigService.shared.setDebugForceRevenueCatPaywall(on ? true : nil)
                    }

                Toggle("Force referral rewards flag", isOn: $debugForceReferralRewards)
                    .onChange(of: debugForceReferralRewards) { _, on in
                        RemoteConfigService.shared.setDebugForceReferralRewards(on)
                    }

                Toggle("Force phone auth flag", isOn: $debugForcePhoneAuth)
                    .onChange(of: debugForcePhoneAuth) { _, on in
                        RemoteConfigService.shared.setDebugForcePhoneAuth(on)
                    }

                Toggle("Force Google auth flag", isOn: $debugForceGoogleAuth)
                    .onChange(of: debugForceGoogleAuth) { _, on in
                        RemoteConfigService.shared.setDebugForceGoogleAuth(on)
                    }

                Button("Clear invite unlock", role: .destructive) {
                    InviteService.shared.clearUnlockForDebug()
                    Haptics.warning()
                }

                if AppConfig.useMockBackend {
                    Stepper("Mock friends joined: \(debugReferralFriends)", value: $debugReferralFriends, in: 0...100)
                        .onChange(of: debugReferralFriends) { _, value in
                            MockStore.shared.setDebugReferralInviteCount(value)
                            Task { await InviteService.shared.refreshRewardState() }
                        }
                }
            }
            #endif

            Section("Onboarding") {
                Button("Replay onboarding", role: .destructive) {
                    Task {
                        await replayOnboarding()
                        dismiss()
                    }
                }

                if AppConfig.useMockBackend {
                    Button("Reset mock data", role: .destructive) {
                        Task {
                            await AuthService.shared.resetMockDataReturningToOnboarding()
                            dismiss()
                        }
                    }
                }
            }

            if AppConfig.useMockBackend {
                profilePreviewSection
            }
        }
        .scrollContentBackground(.hidden)
        .themeBackground()
        .navigationTitle("Developer")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Backend switched", isPresented: .init(
            get: { backendSwitchMessage != nil },
            set: { if !$0 { backendSwitchMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(backendSwitchMessage ?? "")
        }
        .onAppear {
            selectedBackend = AppConfig.backendMode
            syncDebugFieldsFromStore()
        }
    }

    private func switchBackend(to mode: BackendMode) async {
        if mode == .supabase, !AppConfig.isSupabaseConfigured {
            selectedBackend = AppConfig.backendMode
            backendSwitchMessage = "Configure Secrets.plist with Supabase credentials first."
            return
        }

        isSwitchingBackend = true
        defer { isSwitchingBackend = false }

        await AuthService.shared.switchBackend(to: mode)
        selectedBackend = AppConfig.backendMode
        backendSwitchMessage = mode == .mock
            ? "Now using mock data locally."
            : "Now using live Supabase."
    }

    private func replayOnboarding() async {
        if AppConfig.useMockBackend {
            await AuthService.shared.resetMockDataReturningToOnboarding()
            return
        }
        try? await AuthService.shared.updateProfile(
            ProfileUpdate(onboardingCompleted: false)
        )
    }

    // MARK: Profile preview

    private var profilePreviewSection: some View {
        Section {
            Toggle("Force glowing border", isOn: $forceCelebrate)
                .onChange(of: forceCelebrate) { _, on in
                    previewStatus = on ? "Border forced on — open Profile" : "Force celebrate off"
                }

            Stepper("Streak: \(debugStreak)", value: $debugStreak, in: 0...60)
            Stepper("Week days: \(debugWeekDays)", value: $debugWeekDays, in: 0...7)
            Stepper("Year active days: \(debugYearDays)", value: $debugYearDays, in: 0...90)
            Stepper("Busy day sessions: \(debugBusySessions)", value: $debugBusySessions, in: 1...5)

            Button("Apply to Profile") {
                Task { await applyPreview() }
            }

            HStack(spacing: 8) {
                presetButton("Quiet") {
                    debugStreak = 0
                    debugWeekDays = 1
                    debugYearDays = 3
                    debugBusySessions = 1
                    forceCelebrate = false
                }
                presetButton("Warm") {
                    debugStreak = 2
                    debugWeekDays = 3
                    debugYearDays = 10
                    debugBusySessions = 2
                    forceCelebrate = false
                }
                presetButton("Great") {
                    debugStreak = 5
                    debugWeekDays = 5
                    debugYearDays = 24
                    debugBusySessions = 3
                    forceCelebrate = false
                }
                presetButton("On fire") {
                    debugStreak = 21
                    debugWeekDays = 7
                    debugYearDays = 48
                    debugBusySessions = 4
                    forceCelebrate = false
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            if !previewStatus.isEmpty {
                Text(previewStatus)
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("Celebration unlocks at streak ≥ 3, week days ≥ 4, or year days ≥ 12 — or Force glowing border.")
                .font(Theme.grotesk(12))
                .foregroundStyle(Theme.textSecondary)
        } header: {
            Text("Profile preview")
        } footer: {
            Text("Tweaks mock streak + seeded practice (this week plus the year ahead) so you can test the glowing avatar, highlight stories, and the activity grid.")
        }
    }

    private func presetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            Task { await applyPreview() }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func syncDebugFieldsFromStore() {
        debugStreak = AuthService.shared.profile?.streakCount ?? MockStore.shared.profile?.streakCount ?? 0
        let model = PracticeActivityModel(
            sessions: SessionService.shared.sessions,
            joinedAt: AuthService.shared.profile?.createdAt
        )
        let week = PracticeWeekModel(sessions: SessionService.shared.sessions)
        debugWeekDays = week.daysPracticed
        debugYearDays = model.activeDays
        previewStatus = celebrationLabel(
            streak: debugStreak,
            week: debugWeekDays,
            year: debugYearDays
        )
    }

    private func applyPreview() async {
        MockStore.shared.setDebugStreak(debugStreak)
        MockStore.shared.applyDebugPractice(
            weekActiveDays: debugWeekDays,
            yearActiveDays: debugYearDays,
            streakDays: debugStreak,
            busyDaySessions: debugBusySessions
        )
        await AuthService.shared.fetchProfile()
        await SessionService.shared.fetchSessions()
        previewStatus = celebrationLabel(
            streak: debugStreak,
            week: debugWeekDays,
            year: debugYearDays
        ) + " · Applied. Open Profile to check."
        Haptics.success()
    }

    private func celebrationLabel(streak: Int, week: Int, year: Int) -> String {
        let on = ProfileCelebration.isDoingGreat(
            streak: streak,
            daysPracticedThisWeek: week,
            activeDays: year
        )
        return on ? "Doing great: ON" : "Doing great: off"
    }
}
#endif

struct PrivacyView: View {
    var embedded: Bool = false
    @Environment(\.dismiss) private var dismiss
    @State private var showDeleteRecordingsConfirm = false
    @State private var showDeleteAccountConfirm = false
    @State private var isDeletingRecordings = false
    @State private var isDeletingAccount = false

    private var isBusy: Bool { isDeletingRecordings || isDeletingAccount }

    var body: some View {
        Group {
            if embedded {
                content
                    .navigationTitle("Privacy & Data")
                    .navigationBarTitleDisplayMode(.inline)
            } else {
                NavigationStack {
                    content
                        .navigationTitle("Privacy & Data")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .alert("Delete all recordings?", isPresented: $showDeleteRecordingsConfirm) {
            Button("Delete", role: .destructive) {
                Task { await deleteRecordings() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your audio, transcripts, and session history.")
        }
        .alert("Delete account?", isPresented: $showDeleteAccountConfirm) {
            Button("Delete account", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, profile, streak, recordings, and linked Apple or Google sign-in. You can’t undo this.")
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                privacySection(
                    title: "What we record",
                    body: "When you practice speaking, Oracy records your voice for up to 60 seconds per session."
                )
                privacySection(
                    title: "Why audio is uploaded",
                    body: "Your audio is securely uploaded to analyze your speech and provide personalized feedback on fluency, grammar, vocabulary, and more."
                )
                privacySection(
                    title: "How long we keep it",
                    body: "Audio recordings and transcripts are retained for up to 90 days. You can delete all your data at any time from Privacy & Data."
                )
                privacySection(
                    title: "AI training",
                    body: "Your recordings are not used to train AI models. They are only processed to generate your personal feedback."
                )
                privacySection(
                    title: "Your control",
                    body: "Delete recordings anytime, or permanently delete your entire account and all associated data."
                )

                VStack(spacing: 12) {
                    criticalGlassButton(
                        title: "Delete my recordings",
                        systemImage: "waveform.badge.minus",
                        tint: warningAmber,
                        isLoading: isDeletingRecordings
                    ) {
                        showDeleteRecordingsConfirm = true
                    }

                    criticalGlassButton(
                        title: "Delete account",
                        systemImage: "trash.fill",
                        tint: criticalRose,
                        isLoading: isDeletingAccount
                    ) {
                        showDeleteAccountConfirm = true
                    }
                }
                .padding(.top, 12)
            }
            .padding(24)
        }
        .themeBackground()
    }

    private func criticalGlassButton(
        title: String,
        systemImage: String,
        tint: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isBusy else { return }
            Haptics.soft()
            action()
        } label: {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .tint(Color(red: 0.99, green: 0.97, blue: 0.95))
                } else {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                    Text(title)
                        .font(Theme.grotesk(16, weight: .semibold))
                }
            }
            .foregroundStyle(Color(red: 0.99, green: 0.97, blue: 0.95))
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.glassProminent)
        .tint(tint)
        .disabled(isBusy)
        .opacity(isBusy && !isLoading ? 0.55 : 1)
        .accessibilityLabel(title)
    }

    private var criticalRose: Color {
        Color(red: 0.72, green: 0.28, blue: 0.30)
    }

    private var warningAmber: Color {
        Color(red: 0.78, green: 0.48, blue: 0.22)
    }

    private func privacySection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Theme.headline(title)
            Theme.body(body)
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private func deleteRecordings() async {
        isDeletingRecordings = true
        defer { isDeletingRecordings = false }
        do {
            try await SessionService.shared.deleteAllRecordings()
            Haptics.success()
        } catch {
            AppErrorCenter.shared.present(
                title: FriendlyErrorCopy.deleteTitle,
                message: FriendlyErrorCopy.deleteMessage,
                retry: { Task { await deleteRecordings() } }
            )
        }
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await AuthService.shared.deleteAccount()
            Haptics.soft()
            dismiss()
        } catch {
            AppErrorCenter.shared.present(
                title: "Couldn’t delete account",
                message: "Please try again in a moment. If this keeps happening, check your connection.",
                retry: { Task { await deleteAccount() } }
            )
        }
    }
}
