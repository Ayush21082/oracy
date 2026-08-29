import SwiftUI
import UIKit

struct HomeView: View {
    /// Incremented by the tab shell when the phone is shaken on Home.
    var shakeShuffleToken: Int = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var auth = AuthService.shared
    @State private var challengeService = ChallengeService.shared
    @State private var sessionService = SessionService.shared
    @State private var weeklyCount = 0
    @State private var scoreBoardData = ScoreBoardData(todayScore: nil, yesterdayScore: nil)
    @State private var showRecording = false
    @State private var showPaywall = false
    @State private var showProfile = false
    @State private var showSettings = false
    @State private var showAuth = false
    @State private var isShuffling = false
    @State private var displayedPrompt: String = ""
    @State private var promptVisible = true
    @State private var loadError: String?
    @State private var subscriptions = SubscriptionService.shared

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let metrics = HomeLayoutMetrics(height: geo.size.height, width: geo.size.width)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .center, spacing: metrics.sectionSpacing) {
                        scoreBoard(metrics: metrics)
                        challengeCard(metrics: metrics)
                        shuffleButton
                        button
                    }
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)
                    .frame(maxWidth: .infinity, minHeight: geo.size.height)
                }
                .emojiPullToRefresh {
                    await loadData()
                }
            }
            .themeBackground()
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                // Streak stays on the shared Liquid Glass surface.
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 2) {
                        Text("🔥")
                        CountingNumber(
                            value: auth.profile?.streakCount ?? 0,
                            duration: 0.7,
                            font: Theme.grotesk(17, weight: .bold),
                            foreground: Theme.textPrimary
                        )
                    }
                    .padding(.horizontal)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Streak \(auth.profile?.streakCount ?? 0)")
                }

                // Fixed spacer splits groups — profile sits outside the glass cluster.
                ToolbarSpacer(.fixed)

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showProfile = true
                    } label: {
                        ProfileAvatarView(
                            isSubscriber: subscriptions.isProActive,
                            uiImage: auth.userId.flatMap(ProfileLocalCache.loadAvatarImage),
                            imageURL: auth.profile?.avatarUrl.flatMap(URL.init(string:))
                        )
                    }
                    .accessibilityLabel(subscriptions.isProActive ? "Profile, Oracy Pro" : "Profile")
                    .accessibilityHint("Opens your profile")
                    .buttonStyle(QuietButtonStyle())
                }
                .sharedBackgroundVisibility(.hidden)
            }
            .task {
                await loadData()
            }
            .trackScreen("home")
            .fullScreenCover(isPresented: $showRecording, onDismiss: {
                Task { await loadData() }
            }) {
                if let challenge = challengeService.todaysChallenge {
                    RecordingView(challenge: challenge)
                }
            }
            .fullScreenCover(isPresented: $showPaywall) {
                OracyProPaywallView {
                    showRecording = true
                }
                .onAppear {
                    AnalyticsService.shared.track(.paywallShown, ["source": "home"])
                }
                .onDisappear {
                    AnalyticsService.shared.track(.paywallDismissed, ["source": "home"])
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
                    .onAppear {
                        AnalyticsService.shared.track(.settingsOpened)
                    }
            }
            .fullScreenCover(isPresented: $showProfile) {
                ProfileView {
                    showProfile = false
                }
                .onAppear {
                    AnalyticsService.shared.track(.profileOpened)
                }
            }
            .sheet(isPresented: $showAuth) {
                AuthSheet(
                    showsSkip: false,
                    title: "Sign in to speak",
                    message: "Link Apple or Google to start your one-minute practice."
                ) {
                    Task { await continueSpeakingAfterAuth() }
                }
                .onAppear {
                    AnalyticsService.shared.track(.authLinkStarted, ["source": "home_speak"])
                }
            }
            .onChange(of: challengeService.todaysChallenge?.prompt) { _, newPrompt in
                guard !isShuffling, let newPrompt else { return }
                displayedPrompt = newPrompt
            }
            .onChange(of: shakeShuffleToken) { oldValue, newValue in
                guard newValue != oldValue else { return }
                guard !showRecording, !showProfile, !showSettings, !showAuth, !showPaywall else { return }
                guard challengeService.todaysChallenge != nil, !isShuffling else { return }
                Haptics.rigid()
                Task { await shuffleTopics() }
            }
        }
    }

    private func challengeCard(metrics: HomeLayoutMetrics) -> some View {
        VStack(alignment: .center, spacing: metrics.challengeSpacing) {
            if challengeService.isLoading && displayedPrompt.isEmpty {
                PromptLoadingPlaceholder(
                    fontSize: metrics.promptFontSize,
                    blockHeight: metrics.promptBlockHeight
                )
            } else if !displayedPrompt.isEmpty || challengeService.todaysChallenge != nil {
                Text("'\(displayedPrompt.isEmpty ? (challengeService.todaysChallenge?.prompt ?? "") : displayedPrompt)'")
                    .multilineTextAlignment(.center)
                    .font(Theme.fraunces(metrics.promptFontSize, weight: .regular))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(5)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, minHeight: metrics.promptBlockHeight, alignment: .center)
                    .opacity(promptVisible ? 1 : 0)
                    .offset(y: promptVisible ? 0 : (reduceMotion ? 0 : 10))
                    .scaleEffect(promptVisible ? 1 : (reduceMotion ? 1 : 0.96))
                    .accessibilityLabel(isShuffling ? "Shuffling topics" : displayedPrompt)

                VStack(spacing: 6) {
                    Text("Speak about this topic for one minute.")
                        .font(Theme.grotesk(15)).fontWeight(.medium)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)

                    Text("Your voice analysis will begin immediately.")
                        .font(Theme.grotesk(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

            } else if loadError != nil {
                FriendlyErrorInline(
                    title: FriendlyErrorCopy.loadTitle,
                    message: FriendlyErrorCopy.loadMessage,
                    onRetry: {
                        Task { await loadData() }
                    }
                )
            }
        }
    }

    private var shuffleButton: some View {
        Button {
            Task { await shuffleTopics() }
        } label: {
            HStack(spacing: 8) {
                RotatingDiceIcon(isSpinning: isShuffling)
                Text("Shuffle Topics")
            }
            .padding(.horizontal)
        }
        .buttonStyle(SecondaryButtonStyle())
        .accessibilityLabel("Shuffle topics")
        .accessibilityHint("Or shake your phone to shuffle")
        .disabled(challengeService.todaysChallenge == nil || isShuffling)
    }

    private var button: some View {
        Button {
            Task { await startSpeakingTapped() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                Text("Start Speaking")
                if showsStartSpeakingProTag {
                    ProTag(surface: .onAccent)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .accessibilityLabel(showsStartSpeakingProTag ? "Start speaking, Pro" : "Start speaking")
        .disabled(challengeService.todaysChallenge == nil || isShuffling)
    }

    /// PRO only when Start Speaking will open the paywall (free weekly quota used).
    private var showsStartSpeakingProTag: Bool {
        subscriptions.isMembershipPlanEnabled && !subscriptions.canStartSpeaking
    }

    private func startSpeakingTapped() async {
        guard auth.isLoggedIn else {
            Haptics.soft()
            showAuth = true
            return
        }
        await continueSpeakingAfterAuth()
    }

    private func continueSpeakingAfterAuth() async {
        await subscriptions.refreshWeeklyUsage()
        if subscriptions.canStartSpeaking {
            showRecording = true
        } else {
            showPaywall = true
        }
    }

    private func scoreBoard(metrics: HomeLayoutMetrics) -> some View {
        VStack(spacing: metrics.scoreSpacing) {
            Text("TODAY'S SCORE")
                .font(Theme.grotesk(12)).fontWeight(.semibold)
                .foregroundStyle(Theme.textSecondary)

            ZStack {
                ScoreProgressArc(progress: Double(scoreBoardData.todayScore ?? 0) / 100.0)
                    .frame(width: metrics.scoreArcSize, height: metrics.scoreArcSize)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    CountingNumber(
                        value: scoreBoardData.todayScore ?? 0,
                        duration: 1.0,
                        font: Theme.fraunces(metrics.scoreFontSize, weight: .semibold),
                        foreground: Theme.textPrimary
                    )

                    if let delta = scoreBoardData.delta, delta != 0 {
                        Image(systemName: delta > 0 ? "arrow.up" : "arrow.down")
                            .font(Theme.grotesk(16, weight: .semibold))
                            .foregroundStyle(delta > 0 ? Theme.success : Theme.accent)
                    }
                }
            }
            .frame(width: metrics.scoreArcSize, height: metrics.scoreArcSize)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(scoreAccessibilityLabel)

            Text(scoreSubtitle)
                .font(Theme.grotesk(15))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var scoreSubtitle: String {
        if let delta = scoreBoardData.delta {
            if delta > 0 {
                return "+\(delta) from yesterday"
            } else if delta < 0 {
                return "\(delta) from yesterday"
            } else {
                return "Same as yesterday"
            }
        }
        if scoreBoardData.hasPracticedToday {
            return "Nice work today"
        }
        if let yesterday = scoreBoardData.yesterdayScore {
            return "Yesterday: \(yesterday)"
        }
        return "Complete today's challenge"
    }

    private var scoreAccessibilityLabel: String {
        let score = scoreBoardData.todayScore ?? 0
        if let delta = scoreBoardData.delta {
            return "Today's score \(score), \(delta >= 0 ? "up" : "down") \(abs(delta)) from yesterday"
        }
        if scoreBoardData.hasPracticedToday {
            return "Today's score \(score)"
        }
        return "Today's score 0, not practiced yet"
    }

    private func shuffleTopics() async {
        guard !isShuffling else { return }
        isShuffling = true
        UIAccessibility.post(notification: .announcement, argument: "Shuffling topics")

        // Soft exit
        withAnimation(reduceMotion ? .none : .easeIn(duration: 0.18)) {
            promptVisible = false
        }
        try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 200))

        do {
            let challenge = try await challengeService.shuffleTodaysChallenge()
            displayedPrompt = challenge.prompt
            UIAccessibility.post(
                notification: .announcement,
                argument: "New topic: \(challenge.prompt)"
            )
            Haptics.soft()
            AnalyticsService.shared.track(.challengeShuffled, [
                "challenge_id": challenge.id.uuidString.lowercased()
            ])
        } catch {
            displayedPrompt = challengeService.todaysChallenge?.prompt ?? displayedPrompt
            Haptics.warning()
            AppErrorCenter.shared.present(
                title: FriendlyErrorCopy.defaultTitle,
                message: FriendlyErrorCopy.defaultMessage
            )
        }

        // Bounce enter
        withAnimation(reduceMotion ? .none : .themeBounce) {
            promptVisible = true
        }

        isShuffling = false
    }

    private func loadData() async {
        loadError = nil
        do {
            try await challengeService.loadTodaysChallenge()
            weeklyCount = await challengeService.weeklyCompletionCount()
            scoreBoardData = await sessionService.scoreBoard()
            await auth.fetchProfile()
            await subscriptions.refresh()
            if let prompt = challengeService.todaysChallenge?.prompt {
                displayedPrompt = prompt
            }
        } catch {
            loadError = FriendlyErrorCopy.loadMessage
        }
    }
}

/// Adaptive spacing/sizing so Home fits SE through Pro Max without clipping.
private struct HomeLayoutMetrics {
    let height: CGFloat
    let width: CGFloat

    private var isCompactHeight: Bool { height < 700 }
    private var isVeryCompactHeight: Bool { height < 620 }

    var horizontalPadding: CGFloat { width < 360 ? 16 : 24 }
    var verticalPadding: CGFloat { isVeryCompactHeight ? 12 : (isCompactHeight ? 16 : 24) }
    var sectionSpacing: CGFloat { isVeryCompactHeight ? 14 : (isCompactHeight ? 18 : 24) }
    var challengeSpacing: CGFloat { isCompactHeight ? 16 : 28 }
    var scoreSpacing: CGFloat { isCompactHeight ? 10 : 16 }

    var scoreArcSize: CGFloat { isVeryCompactHeight ? 96 : (isCompactHeight ? 110 : 128) }
    var scoreFontSize: CGFloat { isVeryCompactHeight ? 36 : (isCompactHeight ? 42 : 48) }
    var promptFontSize: CGFloat { isVeryCompactHeight ? 28 : (isCompactHeight ? 32 : 38) }

    var promptBlockHeight: CGFloat {
        let line: CGFloat = isVeryCompactHeight ? 34 : (isCompactHeight ? 40 : 38)
        let lines: CGFloat = isVeryCompactHeight ? 4 : 5
        return line * lines
    }
}

/// Soft prompt-shaped placeholder while today's challenge loads.
private struct PromptLoadingPlaceholder: View {
    var fontSize: CGFloat
    var blockHeight: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineIndex = 0
    @State private var breathe = false

    private let lines = [
        "Finding today's topic…",
        "One minute. One thought.",
        "Choosing something worth saying…",
        "Warming up the page…"
    ]

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            Text("'\(lines[lineIndex])'")
                .multilineTextAlignment(.center)
                .font(Theme.fraunces(fontSize, weight: .regular))
                .foregroundStyle(Theme.textPrimary.opacity(0.55))
                .lineLimit(3)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, minHeight: blockHeight, alignment: .center)
                .opacity(breathe ? 1 : 0.55)
                .scaleEffect(breathe ? 1 : 0.985)
                .id(lineIndex)
                .transition(
                    reduceMotion
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .offset(y: 8)),
                            removal: .opacity.combined(with: .offset(y: -6))
                        )
                )

            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .fill(Theme.accent.opacity(dotOpacity(for: i)))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityHidden(true)

            Text("Your topic will land here.")
                .font(Theme.grotesk(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading today's speaking topic")
        .onAppear {
            guard !reduceMotion else {
                breathe = true
                return
            }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
        .task {
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.7))
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.4)) {
                    lineIndex = (lineIndex + 1) % lines.count
                }
            }
        }
    }

    private func dotOpacity(for index: Int) -> Double {
        let active = lineIndex % 3
        if reduceMotion { return index == 0 ? 0.7 : 0.25 }
        return index == active ? 0.85 : 0.25
    }
}

#if DEBUG
#Preview("Home — interactive") {
    HomePreviewHost()
}

private struct HomePreviewHost: View {
    @State private var ready = false

    var body: some View {
        Group {
            if ready {
                HomeView()
            } else {
                ZStack {
                    ThemeBackground()
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
        }
        .task {
            await HomePreviewData.bootstrap()
            ready = true
        }
    }
}

@MainActor
private enum HomePreviewData {
    static func bootstrap() async {
        MockStore.shared.resetAll()
        let userId = MockStore.shared.ensureUser()
        MockStore.shared.updateProfile(
            ProfileUpdate(
                displayName: "Ayush",
                goals: ["fluency", "vocabulary"],
                experienceLevel: "intermediate",
                timezone: TimeZone.current.identifier,
                onboardingCompleted: true
            )
        )

        let challenge = MockStore.shared.assignTodaysChallenge()

        seedSession(userId: userId, challenge: challenge, dayOffset: 1, score: 72)
        for dayOffset in 2...4 {
            seedSession(userId: userId, challenge: challenge, dayOffset: dayOffset, score: 70 + dayOffset)
        }
        seedSession(userId: userId, challenge: challenge, dayOffset: 0, score: 78)

        AuthService.shared.userId = userId
        if var profile = MockStore.shared.profile {
            profile.streakCount = 7
            profile.displayName = "Ayush"
            MockStore.shared.profile = profile
            AuthService.shared.profile = profile
        }

        ChallengeService.shared.todaysChallenge = nil
        try? await ChallengeService.shared.loadTodaysChallenge()
    }

    private static func seedSession(
        userId: UUID,
        challenge: Challenge,
        dayOffset: Int,
        score: Int
    ) {
        let session = MockStore.shared.createSession(challengeId: challenge.id)
        var response = MockFeedbackFactory.make(
            challengePrompt: challenge.prompt,
            durationSeconds: 58
        )
        let feedback = SessionFeedback(
            overallScore: score,
            fluency: response.feedback.fluency,
            grammar: response.feedback.grammar,
            vocabulary: response.feedback.vocabulary,
            clarity: response.feedback.clarity,
            confidence: response.feedback.confidence,
            wordsPerMinute: response.feedback.wordsPerMinute,
            fillerWords: response.feedback.fillerWords,
            strengths: response.feedback.strengths,
            nextImprovement: response.feedback.nextImprovement,
            grammarCorrections: response.feedback.grammarCorrections,
            vocabularySuggestions: response.feedback.vocabularySuggestions,
            structureScore: response.feedback.structureScore,
            structureNote: response.feedback.structureNote,
            paceNote: response.feedback.paceNote,
            suggestedExpression: response.feedback.suggestedExpression
        )
        response = AnalyzeResponse(
            sessionId: session.id.uuidString,
            transcript: response.transcript,
            feedback: feedback,
            streakCount: 1
        )
        _ = MockStore.shared.completeSession(
            id: session.id,
            audioPath: "mock/preview/\(session.id).m4a",
            durationSeconds: 58,
            response: response
        )

        var sessions = MockStore.shared.sessions
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = SpeakingSession(
                id: session.id,
                userId: userId,
                challengeId: challenge.id,
                audioPath: sessions[idx].audioPath,
                transcript: sessions[idx].transcript,
                durationSeconds: sessions[idx].durationSeconds,
                wordCount: sessions[idx].wordCount,
                wordsPerMinute: sessions[idx].wordsPerMinute,
                fillerCount: sessions[idx].fillerCount,
                feedbackJson: sessions[idx].feedbackJson,
                overallScore: score,
                attemptNumber: 1,
                status: "completed",
                createdAt: Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()),
                challenge: challenge
            )
            MockStore.shared.sessions = sessions
        }
    }
}
#endif
