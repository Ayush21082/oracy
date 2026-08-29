import SwiftUI

/// Primary glass CTA for onboarding — Liquid Glass + accent tint.
struct OnboardingPrimaryButton: View {
    let title: String
    var isEnabled: Bool = true
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            guard isEnabled, !isLoading else { return }
            Haptics.medium()
            action()
        } label: {
            Group {
                if isLoading {
                    ProgressView()
                        .tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                } else {
                    Text(title)
                        .font(Theme.grotesk(17, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.glassProminent)
        .tint(Theme.accent)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(.themeBounceSnappy, value: isEnabled)
    }
}

/// Secondary translucent glass button.
struct OnboardingSecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.light()
            action()
        } label: {
            Text(title)
                .font(Theme.grotesk(17, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Theme.minTapTarget)
        }
        .buttonStyle(.glass)
    }
}

/// Large selectable glass card (priorities, levels).
struct OnboardingGlassCard: View {
    let title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack {
                Text(title)
                    .font(Theme.grotesk(17, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .opacity(isSelected ? 0.95 : 0.55)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(
                        isSelected
                            ? Theme.accent.opacity(0.55)
                            : Color.white.opacity(0.28),
                        lineWidth: isSelected ? 1.5 : 0.8
                    )
            }
            .scaleEffect(isSelected ? 1.02 : 1)
            .animation(.themeBounceSnappy, value: isSelected)
        }
        .buttonStyle(BounceButtonStyle(pressedScale: 0.97, haptic: .none))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Compact glass chip for multi-select grids.
struct OnboardingGlassChip: View {
    let title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            Text(title)
                .font(Theme.grotesk(15, weight: .medium))
                .foregroundStyle(isSelected ? Color(red: 0.98, green: 0.97, blue: 0.96) : Theme.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background {
                    if isSelected {
                        Capsule(style: .continuous)
                            .fill(Theme.accent.opacity(0.92))
                    } else {
                        Capsule(style: .continuous)
                            .fill(.ultraThinMaterial)
                            .opacity(0.7)
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.clear : Color.white.opacity(0.3),
                            lineWidth: 0.8
                        )
                }
                .scaleEffect(isSelected ? 1.04 : 1)
                .animation(.themeBounceSnappy, value: isSelected)
        }
        .buttonStyle(BounceButtonStyle(pressedScale: 0.92, haptic: .none))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Wrapping flow layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(
                at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        return (CGSize(width: maxWidth, height: y + rowHeight), positions)
    }
}
