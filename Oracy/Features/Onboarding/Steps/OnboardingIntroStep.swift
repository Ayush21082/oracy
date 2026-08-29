import SwiftUI

struct OnboardingIntroStep: View {
    var onContinue: () -> Void

    @State private var showButton = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ConversationalText(
                lines: [
                    "Hey, hello 👋",
                    "What is this app about?",
                    "I'll help you get set up for one-minute speaking practice."
                ],
                mode: .typewriter(charactersPerSecond: 34),
                font: Theme.fraunces(30, weight: .bold),
                secondaryFont: Theme.fraunces(28, weight: .semibold)
            ) {
                withAnimation(.themeBounce) { showButton = true }
            }
            .padding(.horizontal, 32)

            Spacer()

            OnboardingPrimaryButton(title: "Let's get started") {
                onContinue()
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .onboardingReveal(showButton)
        }
    }
}
