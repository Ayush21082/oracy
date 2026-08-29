import SwiftUI

/// Types a question title, then fades in the subtitle — conversational prompt.
struct ConversationPrompt: View {
    let title: String
    var subtitle: String? = nil
    var centered: Bool = false
    var onComplete: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.launchOverlayActive) private var launchOverlayActive
    @State private var phase = 0 // 0 typing title, 1 subtitle, 2 done
    @State private var typed = ""
    @State private var showCursor = true
    @State private var showSubtitle = false
    @State private var finished = false

    private var alignment: TextAlignment { centered ? .center : .leading }
    private var stackAlignment: HorizontalAlignment { centered ? .center : .leading }

    var body: some View {
        VStack(alignment: stackAlignment, spacing: 10) {
            HStack(spacing: 0) {
                Text(phase == 0 ? typed : title)
                    .font(Theme.fraunces(26, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(alignment)

                if phase == 0 && !reduceMotion {
                    Text("|")
                        .font(Theme.fraunces(26, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary.opacity(showCursor ? 0.65 : 0))
                }

                if !centered { Spacer(minLength: 0) }
            }

            if let subtitle, showSubtitle || phase >= 1 {
                Text(subtitle)
                    .font(Theme.grotesk(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(alignment)
                    .fixedSize(horizontal: false, vertical: true)
                    .opacity(showSubtitle ? 1 : 0)
                    .offset(y: showSubtitle ? 0 : 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .task(id: "\(title)|\(subtitle ?? "")|\(launchOverlayActive)") {
            // Splash covers destination — wait so "Hey" typewriter isn't spent unseen.
            guard !launchOverlayActive else { return }
            await run()
        }
    }

    @MainActor
    private func run() async {
        finished = false
        phase = 0
        typed = ""
        showSubtitle = false

        if reduceMotion {
            typed = title
            phase = 1
            showSubtitle = subtitle != nil
            finish()
            return
        }

        let blink = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000)
                showCursor.toggle()
            }
        }
        defer { blink.cancel() }

        Haptics.prepare()
        for ch in title {
            typed.append(ch)
            Haptics.typewriterTick()
            try? await Task.sleep(nanoseconds: 28_000_000)
        }
        phase = 1

        if subtitle != nil {
            try? await Task.sleep(nanoseconds: 220_000_000)
            withAnimation(.easeOut(duration: 0.35)) {
                showSubtitle = true
            }
            Haptics.soft()
            try? await Task.sleep(nanoseconds: 280_000_000)
        }

        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        phase = 2
        onComplete?()
    }
}

/// Types short acknowledgment lines after an answer.
struct ConversationAck: View {
    let lines: [String]
    var centered: Bool = false
    var onComplete: (() -> Void)? = nil

    var body: some View {
        ConversationalText(
            lines: lines,
            mode: .typewriter(charactersPerSecond: 36),
            font: Theme.fraunces(22, weight: .semibold),
            secondaryFont: Theme.grotesk(16),
            alignment: centered ? .center : .leading,
            onComplete: onComplete
        )
    }
}

/// Static answer + ack under a frozen prompt (prompt stays mounted on the entry).
struct ConversationEntryAnswers: View {
    let answerLines: [String]
    let acknowledgment: [String]
    var centered: Bool = false
    /// Quieter when the turn is complete (history style).
    var dimmed: Bool = false

    private var answerOpacity: Double { dimmed ? 0.78 : 1 }
    private var ackOpacity: Double { dimmed ? 0.82 : 1 }

    var body: some View {
        VStack(alignment: centered ? .center : .leading, spacing: 12) {
            ForEach(Array(answerLines.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Theme.grotesk(16, weight: .medium))
                    .foregroundStyle(Theme.textPrimary.opacity(answerOpacity))
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }

            ForEach(Array(acknowledgment.enumerated()), id: \.offset) { index, line in
                Text(line)
                    .font(index == 0 ? Theme.fraunces(22, weight: .semibold) : Theme.grotesk(16))
                    .foregroundStyle(Theme.textSecondary.opacity(ackOpacity))
                    .multilineTextAlignment(centered ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }
}
