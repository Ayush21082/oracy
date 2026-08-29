import SwiftUI

enum FeedbackLayoutStyle {
    case cards
    case plain
}

/// Shared feedback body used by post-session Feedback and History detail.
struct SessionFeedbackSections: View {
    let feedback: SessionFeedback
    var scoreRevealed: Bool = true
    var style: FeedbackLayoutStyle = .cards

    var body: some View {
        VStack(alignment: .leading, spacing: style == .plain ? 36 : 28) {
            scoreSection
            strengthsSection
            improvementSection
            expressionSection
            grammarSection
            vocabularySection
            fillerSection
            paceSection
            structureSection
            confidenceSection
        }
    }

    // MARK: Sections

    private var scoreSection: some View {
        section(title: "Overall score") {
            VStack(alignment: style == .plain ? .leading : .center, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(feedback.overallScore)")
                        .font(Theme.fraunces(style == .plain ? 56 : 64, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .scaleEffect(scoreRevealed ? 1 : 0.7)
                        .opacity(scoreRevealed ? 1 : 0)
                    Text(feedback.scoreLabel)
                        .font(Theme.grotesk(18, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .opacity(scoreRevealed ? 1 : 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Overall score \(feedback.overallScore), \(feedback.scoreLabel)")
                .frame(maxWidth: .infinity, alignment: style == .plain ? .leading : .center)

                VStack(spacing: 14) {
                    ScoreBar(label: "Fluency", score: feedback.fluency, animate: scoreRevealed)
                    ScoreBar(label: "Grammar", score: feedback.grammar, animate: scoreRevealed)
                    ScoreBar(label: "Vocabulary", score: feedback.vocabulary, animate: scoreRevealed)
                    ScoreBar(label: "Clarity", score: feedback.clarity, animate: scoreRevealed)
                    ScoreBar(label: "Confidence", score: feedback.confidence, animate: scoreRevealed)
                }
            }
        }
    }

    private var strengthsSection: some View {
        Group {
            if !feedback.strengths.isEmpty {
                section(title: "What you did well") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(feedback.strengths, id: \.self) { strength in
                            HStack(alignment: .top, spacing: 10) {
                                Text("✓")
                                    .font(Theme.grotesk(15, weight: .semibold))
                                    .foregroundStyle(Theme.success)
                                Text(strength)
                                    .font(Theme.grotesk(16))
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
        }
    }

    private var improvementSection: some View {
        section(title: "One thing to improve") {
            Text(feedback.nextImprovement)
                .font(Theme.grotesk(16))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var expressionSection: some View {
        section(title: "Suggested expression") {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Instead of")
                        .font(Theme.grotesk(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("“\(feedback.suggestedExpression.instead)”")
                        .font(Theme.fraunces(18))
                        .italic()
                        .foregroundStyle(Theme.textPrimary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("Try")
                        .font(Theme.grotesk(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text("“\(feedback.suggestedExpression.alternative)”")
                        .font(Theme.fraunces(18, weight: .medium))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
    }

    private var grammarSection: some View {
        Group {
            let corrections = Array(feedback.grammarCorrections.prefix(3))
            if !corrections.isEmpty {
                switch style {
                case .cards:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Improve this")
                            .font(Theme.grotesk(17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(corrections) { correction in
                            GrammarCard(correction: correction, style: .cards)
                        }
                    }
                case .plain:
                    section(title: "Improve this") {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(corrections.enumerated()), id: \.element.id) { index, correction in
                                GrammarCard(correction: correction, style: .plain)
                                if index < corrections.count - 1 {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var vocabularySection: some View {
        Group {
            let suggestions = Array(feedback.vocabularySuggestions.prefix(3))
            if !suggestions.isEmpty {
                switch style {
                case .cards:
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Upgrade your vocabulary")
                            .font(Theme.grotesk(17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(suggestions) { suggestion in
                            VocabularyCard(suggestion: suggestion, style: .cards)
                        }
                    }
                case .plain:
                    section(title: "Upgrade your vocabulary") {
                        VStack(alignment: .leading, spacing: 24) {
                            ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, suggestion in
                                VocabularyCard(suggestion: suggestion, style: .plain)
                                if index < suggestions.count - 1 {
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var fillerSection: some View {
        section(title: "Filler words") {
            Text("You used \(feedback.fillerWords) filler word\(feedback.fillerWords == 1 ? "" : "s"). Try getting below \(max(1, feedback.fillerWords - 1)) tomorrow.")
                .font(Theme.grotesk(16))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var paceSection: some View {
        section(title: "Speaking pace") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(feedback.wordsPerMinute) words/minute")
                    .font(Theme.fraunces(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(feedback.paceNote)
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var structureSection: some View {
        section(title: "Structure") {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(feedback.structureScore) / 10")
                    .font(Theme.fraunces(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(feedback.structureNote)
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var confidenceSection: some View {
        section(title: "Confidence") {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(feedback.confidence)")
                    .font(Theme.fraunces(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Your speech was consistent with \(feedback.confidence >= 70 ? "relatively confident" : "developing") delivery.")
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("This is an AI estimate based on speech patterns, not a psychological assessment.")
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Layout helpers

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        switch style {
        case .cards:
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(Theme.grotesk(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                content()
            }
            .cardStyle()
        case .plain:
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(Theme.fraunces(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
