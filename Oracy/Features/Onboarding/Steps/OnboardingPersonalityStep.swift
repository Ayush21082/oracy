import SwiftUI

struct OnboardingPersonalityStep: View {
    @Binding var personality: Set<OnboardingPersonalityTag>
    var onReadyChanged: ((Bool) -> Void)? = nil

    @State private var showOptions = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ConversationalText(
                lines: [
                    "Perfect. That's enough for me to get a sense of what matters to you.",
                    "What best describes you?"
                ],
                mode: .sequenced(delay: 0.55),
                font: Theme.fraunces(28, weight: .bold),
                secondaryFont: Theme.fraunces(28, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showOptions = true }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 28)

            FlowLayout(spacing: 10) {
                ForEach(OnboardingPersonalityTag.allCases) { tag in
                    OnboardingGlassChip(
                        title: tag.displayName,
                        isSelected: personality.contains(tag)
                    ) {
                        toggle(tag)
                    }
                }
            }
            .padding(.horizontal, 24)
            .onboardingReveal(showOptions)

            Spacer(minLength: 24)
        }
        .onChange(of: personality) { _, value in
            onReadyChanged?(!value.isEmpty)
        }
        .onAppear {
            onReadyChanged?(!personality.isEmpty)
        }
    }

    private func toggle(_ tag: OnboardingPersonalityTag) {
        if personality.contains(tag) {
            personality.remove(tag)
        } else {
            personality.insert(tag)
        }
    }
}
