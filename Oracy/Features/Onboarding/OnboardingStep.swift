import SwiftUI

/// Kept for overlay phases; form now lives in a single scroll view.
enum OnboardingStep: Int, CaseIterable, Identifiable {
    case intro
    case auth
    case priorities
    case age
    case personality
    case goals
    case level
    case review
    case creating
    case microphone
    case notifications
    case finale

    var id: Int { rawValue }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }
}

extension AnyTransition {
    static var onboardingStep: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.98)).combined(with: .offset(y: 8)),
            removal: .opacity.combined(with: .scale(scale: 1.02))
        )
    }
}
