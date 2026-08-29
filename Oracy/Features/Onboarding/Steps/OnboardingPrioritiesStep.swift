import SwiftUI

struct OnboardingPrioritiesStep: View {
    @Binding var priorities: Set<OnboardingPriority>
    var onReadyChanged: ((Bool) -> Void)? = nil

    @State private var showOptions = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            ConversationalText(
                lines: [
                    "What matters most to you?",
                    "Pick everything that feels true."
                ],
                mode: .sequenced(delay: 0.45),
                font: Theme.fraunces(30, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showOptions = true }
            }
            .padding(.horizontal, 32)

            Spacer(minLength: 28)

            VStack(spacing: 10) {
                ForEach(OnboardingPriority.allCases) { priority in
                    OnboardingGlassCard(
                        title: priority.displayName,
                        isSelected: priorities.contains(priority)
                    ) {
                        toggle(priority)
                    }
                }
            }
            .padding(.horizontal, 24)
            .onboardingReveal(showOptions)

            Spacer(minLength: 24)
        }
        .onChange(of: priorities) { _, value in
            onReadyChanged?(!value.isEmpty)
        }
        .onAppear {
            onReadyChanged?(!priorities.isEmpty)
        }
    }

    private func toggle(_ priority: OnboardingPriority) {
        if priorities.contains(priority) {
            priorities.remove(priority)
        } else {
            priorities.insert(priority)
        }
    }
}
