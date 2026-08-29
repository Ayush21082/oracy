import SwiftUI

struct OnboardingCreatingStep: View {
    var onFinished: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack {
            Spacer()
            OnboardingProgressCopy(
                phrases: [
                    "One moment…",
                    "Shaping your practice…",
                    "Almost ready…"
                ],
                interval: 1.5,
                onFinished: onFinished
            )
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 10)
            Spacer()
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.55)) {
                appeared = true
            }
        }
    }
}
