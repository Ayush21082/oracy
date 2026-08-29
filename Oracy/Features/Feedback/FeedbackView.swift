import SwiftUI

struct FeedbackView: View {
    let session: SpeakingSession
    let feedback: SessionFeedback
    let transcript: String
    let streakCount: Int
    let onDone: () -> Void
    /// When true, host owns entrance haptics / score reveal timing.
    var deferEntrance: Bool = false
    /// Flipped by AnalysisRevealHost when the curtain has finished clearing.
    var contentRevealed: Bool = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showCompletion = false
    @State private var scoreRevealed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 40) {
                    header

                    if !transcript.isEmpty {
                        plainSection(title: "Transcript") {
                            Text(transcript)
                                .font(Theme.grotesk(16))
                                .foregroundStyle(Theme.textPrimary)
                                .lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    SessionFeedbackSections(
                        feedback: feedback,
                        scoreRevealed: scoreRevealed,
                        style: .plain
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }
            .safeAreaPadding(.top, 8)
            .mask {
                VerticalEdgeFadeMask(fadeHeight: 56, fadeTop: true)
            }
            .themeBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !deferEntrance || contentRevealed {
                    doneBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .fullScreenCover(isPresented: $showCompletion) {
                CompletionView(
                    streakCount: streakCount,
                    durationSeconds: session.durationSeconds ?? 60,
                    wordCount: session.wordCount ?? feedback.wordsPerMinute,
                    fillerCount: feedback.fillerWords,
                    overallScore: feedback.overallScore,
                    onDone: onDone
                )
            }
            .onAppear {
                AnalyticsService.shared.track(.feedbackViewed, [
                    "session_id": session.id.uuidString.lowercased(),
                    "score": String(feedback.overallScore)
                ])
                guard !deferEntrance else { return }
                Haptics.success()
                withAnimation(reduceMotion ? .none : .themeBounce) {
                    scoreRevealed = true
                }
            }
            .onChange(of: contentRevealed) { _, revealed in
                guard deferEntrance, revealed, !scoreRevealed else { return }
                withAnimation(reduceMotion ? .none : .themeBounce) {
                    scoreRevealed = true
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nice work.")
                .font(Theme.fraunces(34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            if let prompt = session.challenge?.prompt, !prompt.isEmpty {
                Text(prompt)
                    .font(Theme.grotesk(15))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var doneBar: some View {
        Button {
            Haptics.medium()
            showCompletion = true
        } label: {
            Text("Done")
                .font(Theme.grotesk(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private func plainSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(Theme.fraunces(22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ScoreBar: View {
    let label: String
    let score: Int
    var animate: Bool = true

    @State private var fillProgress: CGFloat = 0

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.grotesk(15))
                .frame(width: 90, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.accentMuted)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.accent)
                        .frame(width: geo.size.width * fillProgress)
                }
            }
            .frame(height: 8)
            Text("\(score)")
                .font(Theme.grotesk(15, weight: .medium))
                .frame(width: 30, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) score \(score) out of 100")
        .onChange(of: animate) { _, shouldAnimate in
            guard shouldAnimate else { return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                fillProgress = CGFloat(score) / 100
            }
        }
        .onAppear {
            if animate {
                withAnimation(.spring(response: 0.7, dampingFraction: 0.75)) {
                    fillProgress = CGFloat(score) / 100
                }
            }
        }
    }
}

struct GrammarCard: View {
    let correction: GrammarCorrection
    var style: FeedbackLayoutStyle = .cards

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("You said")
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(correction.original)
                    .font(Theme.grotesk(16))
                    .strikethrough()
                    .foregroundStyle(Theme.textSecondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Better")
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(correction.corrected)
                    .font(Theme.grotesk(16, weight: .medium))
                    .foregroundStyle(Theme.success)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Why")
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(correction.explanation)
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .modifier(OptionalCardStyle(enabled: style == .cards))
    }
}

struct VocabularyCard: View {
    let suggestion: VocabularySuggestion
    var style: FeedbackLayoutStyle = .cards

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text("You said")
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                Text(suggestion.original)
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("Try: \(suggestion.suggestions.joined(separator: ", "))")
                .font(Theme.grotesk(16, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .modifier(OptionalCardStyle(enabled: style == .cards))
    }
}

private struct OptionalCardStyle: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        if enabled {
            content.cardStyle()
        } else {
            content
        }
    }
}
