import SwiftUI

struct OnboardingLevelStep: View {
    @Binding var level: ExperienceLevel

    @State private var showOptions = false

    private var levels: [ExperienceLevel] {
        ExperienceLevel.allCases.filter { $0 != .expert }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ConversationalText(
                lines: [
                    "How comfortable are you speaking aloud?",
                    "Be honest — there's no wrong answer."
                ],
                mode: .sequenced(delay: 0.45),
                font: Theme.fraunces(28, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showOptions = true }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 28)

            VStack(spacing: 10) {
                ForEach(levels) { item in
                    OnboardingGlassCard(
                        title: item.displayName,
                        isSelected: level == item
                    ) {
                        level = item
                    }
                }
            }
            .padding(.horizontal, 24)
            .onboardingReveal(showOptions)

            Spacer(minLength: 24)
        }
    }
}
