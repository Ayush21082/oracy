import SwiftUI

/// Detail-screen analysis experience: vocabulary wait → curtain falls → Feedback fades in.
struct AnalysisRevealHost: View {
    let challenge: Challenge
    let audioURL: URL
    let durationSeconds: Double
    let onDone: () -> Void
    var onError: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var session: SpeakingSession?
    @State private var response: AnalyzeResponse?
    @State private var fallProgress: CGFloat = 0
    @State private var contentSettled = false
    @State private var analysisStartedAt = Date()
    @State private var didStartHaptic = false
    @State private var loadingPhrase = AnalysisLoadingCopy.randomPhrase()
    @State private var phraseVisible = true
    @State private var phraseTask: Task<Void, Never>?

    private var hasResult: Bool { session != nil && response != nil }

    /// Content opacity rises with the falling curtain.
    private var detailOpacity: Double {
        if contentSettled { return 1 }
        if !hasResult { return 0 }
        if reduceMotion { return Double(fallProgress) }
        // Ease-in so detail blooms as the curtain clears the upper half
        let t = Double(fallProgress)
        return min(1, t * t * 1.15)
    }

    private var showLoadingCopy: Bool {
        fallProgress < 0.28
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            // Detail lives on this screen from the moment results arrive
            if let session, let response {
                FeedbackView(
                    session: session,
                    feedback: response.feedback,
                    transcript: response.transcript,
                    streakCount: response.streakCount,
                    onDone: onDone,
                    deferEntrance: true,
                    contentRevealed: contentSettled
                )
                .opacity(detailOpacity)
                .allowsHitTesting(contentSettled)
            }

            if fallProgress < 1 {
                AnalysisGradientCurtain(
                    fallProgress: fallProgress,
                    reduceMotion: reduceMotion
                )
                .opacity(1 - Double(fallProgress) * 0.15)
            }

            if showLoadingCopy {
                loadingLabel
                    .opacity(phraseVisible ? (1 - Double(fallProgress) * 3.2) : 0)
                    .allowsHitTesting(false)
            }
        }
        .task {
            startPhraseRotation()
            await runAnalysisFlow()
        }
        .onDisappear {
            phraseTask?.cancel()
        }
        .accessibilityElement(children: hasResult && contentSettled ? .contain : .combine)
        .accessibilityLabel(hasResult && contentSettled ? "Feedback" : loadingPhrase)
    }

    private var loadingLabel: some View {
        Text(loadingPhrase)
            .font(Theme.fraunces(28, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 36)
            .transition(.opacity.combined(with: .scale(scale: 0.98)))
            .id(loadingPhrase)
    }

    private func startPhraseRotation() {
        phraseTask?.cancel()
        phraseTask = Task { @MainActor in
            while !Task.isCancelled, fallProgress < 0.05 {
                try? await Task.sleep(for: .milliseconds(2200))
                guard !Task.isCancelled, fallProgress < 0.05 else { break }
                withAnimation(.easeInOut(duration: 0.35)) {
                    phraseVisible = false
                }
                try? await Task.sleep(for: .milliseconds(280))
                guard !Task.isCancelled else { break }
                loadingPhrase = AnalysisLoadingCopy.randomPhrase(excluding: loadingPhrase)
                withAnimation(.easeInOut(duration: 0.4)) {
                    phraseVisible = true
                }
            }
        }
    }

    @MainActor
    private func runAnalysisFlow() async {
        if !didStartHaptic {
            didStartHaptic = true
            Haptics.soft()
        }
        analysisStartedAt = Date()

        guard let userId = AuthService.shared.userId else {
            failAndDismiss()
            return
        }

        do {
            let created = try await SessionService.shared.createSession(challengeId: challenge.id)

            let audioPath = try await SessionService.shared.uploadAudio(
                sessionId: created.id,
                userId: userId,
                audioURL: audioURL
            )

            let profile = AuthService.shared.profile
            let analyzed = try await SessionService.shared.analyzeSession(
                sessionId: created.id,
                audioPath: audioPath,
                challengePrompt: challenge.prompt,
                userLevel: profile?.experienceLevel ?? "intermediate",
                userGoals: profile?.goals ?? [],
                durationSeconds: durationSeconds
            )

            var enriched = created
            enriched.durationSeconds = durationSeconds
            enriched.wordCount = analyzed.feedback.wordsPerMinute
            enriched.overallScore = analyzed.feedback.overallScore
            enriched.feedbackJson = analyzed.feedback
            enriched.transcript = analyzed.transcript
            enriched.challenge = challenge

            // Mount detail under the curtain, then let the curtain fall away.
            session = enriched
            response = analyzed

            await fallCurtainAndReveal()
        } catch {
            Haptics.error()
            failAndDismiss()
        }
    }

    @MainActor
    private func fallCurtainAndReveal() async {
        phraseTask?.cancel()
        Haptics.light()

        withAnimation(.easeOut(duration: 0.3)) {
            phraseVisible = false
        }

        let elapsed = Date().timeIntervalSince(analysisStartedAt)
        let duration: TimeInterval
        if reduceMotion {
            duration = 0.35
        } else if elapsed < 1.2 {
            duration = 0.95
        } else if elapsed < 2.5 {
            duration = 1.2
        } else {
            duration = 1.45
        }

        // Smooth deceleration — curtain falls, detail opacity rises in lockstep
        withAnimation(.timingCurve(0.22, 0.8, 0.18, 1.0, duration: duration)) {
            fallProgress = 1
        }

        try? await Task.sleep(for: .milliseconds(Int(duration * 1000)))

        Haptics.success()
        withAnimation(reduceMotion ? .none : .themeBounce) {
            contentSettled = true
        }
    }

    private func failAndDismiss() {
        phraseTask?.cancel()
        onError()
    }
}
