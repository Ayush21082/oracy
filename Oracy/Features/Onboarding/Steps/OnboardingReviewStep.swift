import SwiftUI

struct OnboardingReviewStep: View {
    var onStartSetup: () -> Void

    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ConversationalText(
                lines: [
                    "Alright.\nI think I've got enough to get you started.",
                    "Let's build your setup."
                ],
                mode: .sequenced(delay: 0.6),
                font: Theme.fraunces(30, weight: .bold),
                secondaryFont: Theme.fraunces(26, weight: .semibold)
            ) {
                withAnimation(.themeBounce) { showButton = true }
            }
            .padding(.horizontal, 32)

            Spacer()

            OnboardingPrimaryButton(title: "Start setup") {
                onStartSetup()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .onboardingReveal(showButton)
        }
    }
}
