import SwiftUI
import UIKit

/// Shared circular avatar from the `bird` asset (or a custom photo).
/// When `isCelebrating`, the border glows softly and rotates.
/// When `isSubscriber`, a calmer Pro ring stays visible (can stack with celebration bloom).
struct ProfileAvatarView: View {
    var size: CGFloat = 40
    var borderWidth: CGFloat = 1.75
    var isCelebrating: Bool = false
    var isSubscriber: Bool = false
    /// Local override (e.g. newly picked photo before upload).
    var uiImage: UIImage? = nil
    /// Remote profile photo URL from `profiles.avatar_url`.
    var imageURL: URL? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var spinDegrees: Double = 0
    @State private var glowPulse = false

    private var isDark: Bool { colorScheme == .dark }

    private var ringColors: [Color] {
        [
            Theme.accent,
            Color(red: 0.98, green: 0.82, blue: 0.55),
            Color(red: 0.92, green: 0.58, blue: 0.42),
            Color(red: 0.78, green: 0.62, blue: 0.52),
            Theme.success.opacity(0.9),
            Theme.accent
        ]
    }

    private var plusRingColors: [Color] {
        [
            Theme.accent,
            Color(red: 0.92, green: 0.74, blue: 0.42),
            Color(red: 0.82, green: 0.56, blue: 0.46),
            Theme.accent
        ]
    }

    var body: some View {
        ZStack {
            if isCelebrating {
                Circle()
                    .fill(Theme.accent.opacity(bloomOpacity))
                    .frame(width: size + bloomExtra, height: size + bloomExtra)
                    .blur(radius: bloomBlur)
                    .opacity(0.9)

                Circle()
                    .strokeBorder(
                        AngularGradient(colors: ringColors, center: .center),
                        lineWidth: borderWidth + (isDark ? 2.2 : 1.6)
                    )
                    .frame(width: size + 12, height: size + 12)
                    .rotationEffect(.degrees(spinDegrees))
                    .blur(radius: isDark ? 1.0 : 0.6)
                    .opacity(isDark ? 0.8 : 0.55)
            } else if isSubscriber {
                Circle()
                    .fill(Theme.accent.opacity(isDark ? 0.16 : 0.08))
                    .frame(width: size + 10, height: size + 10)
                    .blur(radius: 6)
            }

            avatarImage
                .frame(width: size, height: size)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(
                            Color.white.opacity(isCelebrating ? (isDark ? 0.8 : 0.7) : 0.65),
                            lineWidth: max(1, borderWidth * 0.55)
                        )
                        .padding(borderWidth * 0.7)
                }
                .overlay {
                    Circle()
                        .strokeBorder(
                            AngularGradient(
                                colors: (isCelebrating || isSubscriber) ? (isCelebrating ? ringColors : plusRingColors) : [
                                    Color.white.opacity(0.35),
                                    Color.white.opacity(0.2)
                                ],
                                center: .center
                            ),
                            lineWidth: isCelebrating
                                ? borderWidth + (isDark ? 1.5 : 1.0)
                                : (isSubscriber ? borderWidth + 0.6 : borderWidth)
                        )
                        .rotationEffect(.degrees(isCelebrating ? spinDegrees : 0))
                }
                .shadow(
                    color: Theme.accent.opacity(dropShadowOpacity),
                    radius: dropShadowRadius,
                    y: size > 60 ? (isDark ? 4 : 2) : 1
                )
        }
        .frame(
            width: size + (isCelebrating ? bloomExtra : (isSubscriber ? 10 : 0)),
            height: size + (isCelebrating ? bloomExtra : (isSubscriber ? 10 : 0))
        )
        .onAppear { startMotionIfNeeded() }
        .onChange(of: isCelebrating) { _, celebrating in
            if celebrating {
                startMotionIfNeeded()
            } else {
                spinDegrees = 0
                glowPulse = false
            }
        }
        .accessibilityAddTraits(isCelebrating ? .isButton : [])
        .accessibilityLabel(isSubscriber ? "Profile, Oracy Pro" : "Profile")
    }

    @ViewBuilder
    private var avatarImage: some View {
        if let uiImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let imageURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    defaultAvatar
                case .empty:
                    defaultAvatar
                        .overlay { ProgressView().scaleEffect(0.7) }
                @unknown default:
                    defaultAvatar
                }
            }
        } else {
            defaultAvatar
        }
    }

    private var defaultAvatar: some View {
        ZStack {
            Color.white
            Image("bird")
                .resizable()
                .scaledToFill()
                .padding(max(4, size * 0.1))
        }
    }

    // MARK: Light vs dark glow tuning

    private var bloomOpacity: Double {
        if isDark {
            return glowPulse ? 0.38 : 0.2
        }
        return glowPulse ? 0.16 : 0.09
    }

    private var bloomExtra: CGFloat {
        isDark ? 28 : 22
    }

    private var bloomBlur: CGFloat {
        if size > 60 {
            return isDark ? 16 : 11
        }
        return isDark ? 10 : 7
    }

    private var dropShadowOpacity: Double {
        if isCelebrating {
            return isDark ? 0.42 : 0.16
        }
        if isSubscriber {
            return isDark ? 0.28 : 0.12
        }
        return isDark ? 0.22 : 0.1
    }

    private var dropShadowRadius: CGFloat {
        if isCelebrating {
            if size > 60 { return isDark ? 16 : 8 }
            return isDark ? 8 : 4
        }
        if isSubscriber {
            if size > 60 { return isDark ? 12 : 6 }
            return isDark ? 5 : 3
        }
        if size > 60 { return isDark ? 10 : 5 }
        return isDark ? 3 : 2
    }

    private func startMotionIfNeeded() {
        guard isCelebrating else { return }
        if reduceMotion {
            glowPulse = true
            return
        }
        withAnimation(.linear(duration: 5.5).repeatForever(autoreverses: false)) {
            spinDegrees = 360
        }
        withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
            glowPulse = true
        }
    }
}
