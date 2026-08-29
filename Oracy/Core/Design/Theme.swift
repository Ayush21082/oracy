import SwiftUI
import UIKit

enum Theme {
    // Soft parchment base (gradient+grain live in ThemeBackground). Accent is dusty terracotta — not tangy orange.
    static let background = Color(light: Soft.cream, dark: Soft.ink)
    static let textPrimary = Color(light: Soft.ink, dark: Soft.cream)
    static let textSecondary = Color(light: Soft.stone, dark: Soft.mist)
    static let accent = Color(light: Soft.terracotta, dark: Soft.terracottaBright)
    static let accentMuted = Color(light: Soft.terracotta.opacity(0.14), dark: Soft.terracottaBright.opacity(0.22))
    static let cardBackground = Color(light: Soft.cardLight, dark: Soft.cardDark)
    static let success = Color(light: Soft.sage, dark: Soft.sageBright)
    static let warning = Color(light: Soft.amber, dark: Soft.amberBright)
    static let shadow = Color(light: Color.black.opacity(0.06), dark: Color.black.opacity(0.45))

    static let cornerRadius: CGFloat = 16
    static let spacing: CGFloat = 8
    static let minTapTarget: CGFloat = 54

    /// Display / editorial typeface.
    static func fraunces(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Fraunces", size: size).weight(weight)
    }

    /// UI / body typeface.
    static func grotesk(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .custom("Schibsted Grotesk", size: size).weight(weight)
    }

    static func largeTitle(_ text: String) -> some View {
        Text(text)
            .font(fraunces(34, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
    }

    static func title(_ text: String) -> some View {
        Text(text)
            .font(fraunces(24, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
    }

    static func headline(_ text: String) -> some View {
        Text(text)
            .font(grotesk(17, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
    }

    static func body(_ text: String) -> some View {
        Text(text)
            .font(grotesk(16))
            .foregroundStyle(Theme.textPrimary)
    }

    static func caption(_ text: String) -> some View {
        Text(text)
            .font(grotesk(13))
            .foregroundStyle(Theme.textSecondary)
    }

    private enum Soft {
        // Cooler linen parchment — avoids the flat “tangy orange” cream wash
        static let cream = Color(red: 0.96, green: 0.94, blue: 0.91)
        static let ink = Color(red: 0.11, green: 0.10, blue: 0.09)
        static let stone = Color(red: 0.47, green: 0.44, blue: 0.42)
        static let mist = Color(red: 0.68, green: 0.64, blue: 0.60)
        // Dusty terracotta (muted) rather than bright tangerine
        static let terracotta = Color(red: 0.66, green: 0.42, blue: 0.34)
        static let terracottaBright = Color(red: 0.82, green: 0.56, blue: 0.46)
        static let cardLight = Color(red: 0.99, green: 0.98, blue: 0.96)
        static let cardDark = Color(red: 0.18, green: 0.16, blue: 0.15)
        static let sage = Color(red: 0.40, green: 0.60, blue: 0.45)
        static let sageBright = Color(red: 0.52, green: 0.72, blue: 0.56)
        static let amber = Color(red: 0.85, green: 0.65, blue: 0.30)
        static let amberBright = Color(red: 0.92, green: 0.74, blue: 0.40)
    }
}

private extension Color {
    init(light: Color, dark: Color) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var minHeight: CGFloat = Theme.minTapTarget
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.grotesk(fontSize, weight: .semibold))
            .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))
            .frame(maxWidth: .infinity)
            .frame(minHeight: minHeight)
            .background(Theme.accent)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.9 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.medium() }
            }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.grotesk(17, weight: .medium))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .background(Theme.accentMuted)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.88 : 1)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.55), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Haptics.light() }
            }
    }
}

/// Icon / compact controls — snappy bounce without full-width chrome.
struct BounceButtonStyle: ButtonStyle {
    enum HapticKind {
        case none, light, medium, soft
    }

    var pressedScale: CGFloat = 0.86
    var haptic: HapticKind = .light

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                switch haptic {
                case .none: break
                case .light: Haptics.light()
                case .medium: Haptics.medium()
                case .soft: Haptics.soft()
                }
            }
    }
}

/// Toolbar / avatar buttons — no gray highlight or press dim.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

extension Animation {
    /// Soft overshoot for content appearing (prompts, scores, chips).
    static var themeBounce: Animation {
        .spring(response: 0.42, dampingFraction: 0.62)
    }

    static var themeBounceSnappy: Animation {
        .spring(response: 0.32, dampingFraction: 0.55)
    }
}

struct CardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .padding(20)
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
            .shadow(
                color: Theme.shadow,
                radius: colorScheme == .dark ? 12 : 8,
                y: colorScheme == .dark ? 4 : 2
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardModifier())
    }
}
