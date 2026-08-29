import SwiftUI

struct OnboardingFinaleStep: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var lineIndex = 0
    @State private var didFinish = false

    private let lines = ["Almost there…", "You're all set."]

    var body: some View {
        VStack(spacing: 36) {
            Spacer()

            EmojiFinaleView()

            Text(lines[lineIndex])
                .font(Theme.fraunces(28, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .id(lineIndex)
                .transition(.opacity.combined(with: .scale(scale: 0.98)))
                .animation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce, value: lineIndex)

            Spacer()
        }
        .task {
            await run()
        }
    }

    @MainActor
    private func run() async {
        let first = reduceMotion ? 0.5 : 1.4
        let second = reduceMotion ? 0.45 : 1.2

        try? await Task.sleep(nanoseconds: UInt64(first * 1_000_000_000))
        withAnimation {
            lineIndex = 1
        }
        try? await Task.sleep(nanoseconds: UInt64(second * 1_000_000_000))
        guard !didFinish else { return }
        didFinish = true
        onFinished()
    }
}
