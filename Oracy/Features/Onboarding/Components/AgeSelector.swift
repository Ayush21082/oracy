import SwiftUI

/// Playful but refined age control — − 25 + in a horizontal row.
struct AgeSelector: View {
    @Binding var age: Int
    var range: ClosedRange<Int> = 13...80

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 28) {
            Spacer()
            circleButton(systemName: "minus") {
                guard age > range.lowerBound else { return }
                age -= 1
            }
            .disabled(age <= range.lowerBound)
            .opacity(age <= range.lowerBound ? 0.4 : 1)

            Text("\(age)")
                .font(Theme.fraunces(56, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .contentTransition(.numericText())
                .animation(reduceMotion ? .easeOut(duration: 0.15) : .themeBounceSnappy, value: age)
                .frame(minWidth: 88)
                .multilineTextAlignment(.center)
                .accessibilityLabel("Age \(age)")

            circleButton(systemName: "plus") {
                guard age < range.upperBound else { return }
                age += 1
            }
            .disabled(age >= range.upperBound)
            .opacity(age >= range.upperBound ? 0.4 : 1)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func circleButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 56, height: 56)
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.75)
                }
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.32), lineWidth: 0.8)
                }
        }
        .buttonStyle(BounceButtonStyle(pressedScale: 0.9, haptic: .none))
        .accessibilityLabel(systemName == "plus" ? "Increase age" : "Decrease age")
    }
}
