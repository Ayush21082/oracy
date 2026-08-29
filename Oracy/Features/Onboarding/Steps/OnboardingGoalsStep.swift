import SwiftUI

struct OnboardingGoalsStep: View {
    @Binding var goals: Set<UserGoal>
    var onReadyChanged: ((Bool) -> Void)? = nil

    @State private var showOptions = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ConversationalText(
                lines: [
                    "What do you want to improve when you speak?",
                    "This helps me personalize your practice."
                ],
                mode: .sequenced(delay: 0.45),
                font: Theme.fraunces(28, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showOptions = true }
            }
            .padding(.horizontal, 28)

            Spacer(minLength: 28)

            FlowLayout(spacing: 10) {
                ForEach(UserGoal.allCases) { goal in
                    OnboardingGlassChip(
                        title: goal.displayName,
                        isSelected: goals.contains(goal)
                    ) {
                        toggle(goal)
                    }
                }
            }
            .padding(.horizontal, 24)
            .onboardingReveal(showOptions)

            Spacer(minLength: 24)
        }
        .onChange(of: goals) { _, value in
            onReadyChanged?(!value.isEmpty)
        }
        .onAppear {
            onReadyChanged?(!goals.isEmpty)
        }
    }

    private func toggle(_ goal: UserGoal) {
        if goals.contains(goal) {
            goals.remove(goal)
        } else {
            goals.insert(goal)
        }
    }
}
