import SwiftUI

struct OnboardingAgeStep: View {
    @Binding var age: Int

    @State private var showControls = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ConversationalText(
                lines: [
                    "How old are you?",
                    "Just so we can keep things relevant."
                ],
                mode: .sequenced(delay: 0.45),
                font: Theme.fraunces(30, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showControls = true }
            }
            .padding(.horizontal, 32)

            Spacer().frame(height: 40)

            AgeSelector(age: $age)
                .onboardingReveal(showControls)

            Spacer()
        }
    }
}
