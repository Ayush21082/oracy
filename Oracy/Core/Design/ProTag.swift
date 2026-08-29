import SwiftUI

/// Small monospace PRO mark — gradient type + border, no fill.
/// Use wherever Plus is required (membership remote config on, user not entitled).
struct ProTag: View {
    enum Surface {
        /// On terracotta / dark CTAs (Start Speaking, Plus cards).
        case onAccent
        /// On parchment / light cards.
        case onSurface
    }

    var surface: Surface = .onAccent

    private var gradient: LinearGradient {
        switch surface {
        case .onAccent:
            return LinearGradient(
                colors: [
                    Color(red: 1.00, green: 0.94, blue: 0.78),
                    Color(red: 0.98, green: 0.82, blue: 0.52),
                    Color(red: 0.92, green: 0.68, blue: 0.42),
                    Color(red: 1.00, green: 0.90, blue: 0.70)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .onSurface:
            return LinearGradient(
                colors: [
                    Color(red: 0.78, green: 0.52, blue: 0.32),
                    Color(red: 0.92, green: 0.72, blue: 0.42),
                    Color(red: 0.62, green: 0.38, blue: 0.28),
                    Color(red: 0.86, green: 0.60, blue: 0.38)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        Text("PRO")
            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
            .tracking(1.1)
            .foregroundStyle(gradient)
            .padding(.horizontal, 5)
            .padding(.vertical, 2.5)
            .overlay {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(gradient, lineWidth: 1)
            }
            .accessibilityLabel("Pro")
    }
}

extension View {
    /// Appends a trailing PRO tag when membership is enabled and Plus is required.
    @ViewBuilder
    func proTagIfNeeded(
        _ needed: Bool,
        surface: ProTag.Surface = .onAccent,
        spacing: CGFloat = 8
    ) -> some View {
        if needed {
            HStack(spacing: spacing) {
                self
                ProTag(surface: surface)
            }
        } else {
            self
        }
    }
}
