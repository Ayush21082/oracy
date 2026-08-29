import SwiftUI

/// Auto-advancing status lines — calm crossfade, no bounce or scale punch.
struct OnboardingProgressCopy: View {
    let phrases: [String]
    var interval: TimeInterval = 1.55
    var onFinished: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var didFinish = false
    @State private var lineOpacity: Double = 1
    @State private var pulse = false

    private var phraseTransition: Animation {
        reduceMotion
            ? .easeOut(duration: 0.2)
            : .easeInOut(duration: 0.55)
    }

    var body: some View {
        VStack(spacing: 28) {
            // Quiet breathing mark — presence without a spinner
            Circle()
                .fill(Theme.accent.opacity(0.55))
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1.15 : 0.92)
                .opacity(pulse ? 0.95 : 0.45)
                .animation(
                    reduceMotion
                        ? .easeOut(duration: 0.2)
                        : .easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                    value: pulse
                )

            Text(phrases[safe: index] ?? phrases.last ?? "")
                .font(Theme.fraunces(28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .opacity(lineOpacity)
                .accessibilityLabel(phrases[safe: index] ?? "")
        }
        .task {
            if !reduceMotion {
                pulse = true
            }
            await run()
        }
    }

    @MainActor
    private func run() async {
        guard phrases.count > 1 else {
            try? await Task.sleep(nanoseconds: UInt64((reduceMotion ? 0.4 : interval) * 1_000_000_000))
            finish()
            return
        }

        let hold = reduceMotion ? 0.35 : interval
        for i in 0..<phrases.count {
            if i > 0 {
                withAnimation(phraseTransition) {
                    lineOpacity = 0
                }
                try? await Task.sleep(nanoseconds: UInt64((reduceMotion ? 0.12 : 0.32) * 1_000_000_000))
                index = i
                withAnimation(phraseTransition) {
                    lineOpacity = 1
                }
            } else {
                index = 0
                lineOpacity = 1
            }
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
        }
        finish()
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        onFinished?()
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
