import SwiftUI

/// Soft arc labels that follow a circular avatar — JOINED year on top, optional PRO MEMBERSHIP below.
struct AvatarJoinedYearArc: View {
    let year: String
    /// Visual diameter of the photo (not including celebration glow).
    var avatarSize: CGFloat
    var isCelebrating: Bool = false
    /// When true, draws a matching arc under the avatar.
    var showsProMembership: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    private var joinedText: String { "JOINED \(year)" }
    private var proText: String { "PRO MEMBERSHIP" }

    private var radius: CGFloat {
        Self.rimRadius(avatarSize: avatarSize, isCelebrating: isCelebrating)
    }

    private var fontSize: CGFloat {
        Self.fontSize(for: avatarSize)
    }

    var body: some View {
        ZStack {
            curvedLabel(joinedText, onBottom: false)

            if showsProMembership {
                curvedLabel(proText, onBottom: true)
            }
        }
        .frame(
            width: Self.layoutDiameter(avatarSize: avatarSize, isCelebrating: isCelebrating),
            height: Self.layoutDiameter(avatarSize: avatarSize, isCelebrating: isCelebrating)
        )
        .accessibilityHidden(true)
    }

    // MARK: Shared geometry (kept in sync with layout height on Profile)

    static func fontSize(for avatarSize: CGFloat) -> CGFloat {
        min(12, max(9, avatarSize * 0.095))
    }

    static func rimRadius(avatarSize: CGFloat, isCelebrating: Bool) -> CGFloat {
        let photoRadius = avatarSize * 0.5
        let glow: CGFloat = isCelebrating ? 16 : 6
        let gap = max(11, avatarSize * 0.1)
        return photoRadius + glow + gap
    }

    /// Full square that fits the arc glyphs without clipping at any stretch size.
    static func layoutDiameter(avatarSize: CGFloat, isCelebrating: Bool) -> CGFloat {
        let r = rimRadius(avatarSize: avatarSize, isCelebrating: isCelebrating)
        let font = fontSize(for: avatarSize)
        // Diameter of path + glyph extent above/below the rim.
        return r * 2 + font + 4
    }

    // MARK: Arc letters

    /// Total angular width of the label (degrees).
    private func sweep(for text: String) -> Double {
        let count = max(text.count, 1)
        return min(128, 9.2 * Double(count))
    }

    @ViewBuilder
    private func curvedLabel(_ text: String, onBottom: Bool) -> some View {
        let sweep = sweep(for: text)
        ForEach(Array(text.enumerated()), id: \.offset) { index, character in
            let count = max(text.count - 1, 1)
            let t = Double(index) / Double(count)
            // Top: −sweep/2 → +sweep/2. Bottom: reverse so it still reads left → right.
            let angle = onBottom
                ? (sweep * 0.5 - sweep * t)
                : (-sweep * 0.5 + sweep * t)

            Text(String(character))
                .font(Theme.grotesk(fontSize, weight: .bold))
                .foregroundStyle(letterGradient)
                .offset(y: onBottom ? radius : -radius)
                .rotationEffect(.degrees(angle))
        }
    }

    private var letterGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Theme.accent.opacity(0.78),
                    Color(red: 0.92, green: 0.72, blue: 0.48).opacity(0.88),
                    Theme.accent.opacity(0.72)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.48, green: 0.30, blue: 0.24).opacity(0.88),
                Color(red: 0.58, green: 0.40, blue: 0.28).opacity(0.82),
                Color(red: 0.50, green: 0.34, blue: 0.26).opacity(0.85)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}
