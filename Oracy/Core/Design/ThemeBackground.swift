import SwiftUI
import UIKit

/// App-wide scenic background: light mode gets a soft parchment gradient + film grain;
/// dark mode stays a quiet warm charcoal.
/// Pass `ambientMotion: true` for a slow liquid drift (onboarding).
struct ThemeBackground: View {
    var ambientMotion: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private var shouldAnimate: Bool { ambientMotion && !reduceMotion }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            ZStack {
                baseFill

                // Terracotta bloom — top trailing
                blob(
                    colors: colorScheme == .dark
                        ? [Theme.accent.opacity(0.34), Theme.accent.opacity(0.08), .clear]
                        : [
                            Color(red: 0.92, green: 0.58, blue: 0.44).opacity(0.55),
                            Color(red: 0.92, green: 0.58, blue: 0.44).opacity(0.18),
                            .clear
                        ],
                    size: min(w, h) * 1.35
                )
                .offset(
                    x: shouldAnimate ? (drift ? w * 0.18 : w * 0.28) : w * 0.22,
                    y: shouldAnimate ? (drift ? -h * 0.08 : h * 0.02) : -h * 0.04
                )

                // Sage wash — bottom leading
                blob(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.52, green: 0.72, blue: 0.56).opacity(0.22),
                            Color(red: 0.52, green: 0.72, blue: 0.56).opacity(0.06),
                            .clear
                        ]
                        : [
                            Color(red: 0.68, green: 0.82, blue: 0.72).opacity(0.52),
                            Color(red: 0.68, green: 0.82, blue: 0.72).opacity(0.14),
                            .clear
                        ],
                    size: min(w, h) * 1.4
                )
                .offset(
                    x: shouldAnimate ? (drift ? -w * 0.22 : -w * 0.12) : -w * 0.18,
                    y: shouldAnimate ? (drift ? h * 0.42 : h * 0.52) : h * 0.48
                )

                // Gold mid-glow
                blob(
                    colors: colorScheme == .dark
                        ? [
                            Color(red: 0.92, green: 0.74, blue: 0.40).opacity(0.14),
                            .clear
                        ]
                        : [
                            Color(red: 0.98, green: 0.86, blue: 0.55).opacity(0.32),
                            Color(red: 0.98, green: 0.86, blue: 0.55).opacity(0.08),
                            .clear
                        ],
                    size: min(w, h) * 1.1
                )
                .offset(
                    x: shouldAnimate ? (drift ? w * 0.02 : -w * 0.08) : -w * 0.02,
                    y: shouldAnimate ? (drift ? h * 0.28 : h * 0.18) : h * 0.22
                )
                .scaleEffect(shouldAnimate ? (drift ? 1.08 : 0.94) : 1)

                // Soft veil
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [Color.black.opacity(0.12), .clear, Color.black.opacity(0.18)]
                        : [
                            Color.white.opacity(0.28),
                            .clear,
                            Color(red: 0.55, green: 0.42, blue: 0.36).opacity(0.07)
                        ],
                    startPoint: .top,
                    endPoint: .bottom
                )

                FilmGrainOverlay(opacity: colorScheme == .dark ? 0.05 : 0.09)
            }
            .frame(width: w, height: h)
            // Extra scale so drifting blobs never flash edges
            .scaleEffect(shouldAnimate ? (drift ? 1.06 : 1.12) : 1.08)
            .frame(width: w, height: h)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .onAppear {
            guard shouldAnimate else { return }
            withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }

    private var baseFill: some View {
        Group {
            if colorScheme == .dark {
                LinearGradient(
                    colors: [
                        Color(red: 0.16, green: 0.13, blue: 0.12),
                        Color(red: 0.11, green: 0.10, blue: 0.09),
                        Color(red: 0.10, green: 0.09, blue: 0.08)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else {
                LinearGradient(
                    colors: [
                        Color(red: 0.99, green: 0.97, blue: 0.94),
                        Color(red: 0.97, green: 0.93, blue: 0.88),
                        Color(red: 0.94, green: 0.86, blue: 0.79)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    private func blob(colors: [Color], size: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: colors,
                    center: .center,
                    startRadius: 0,
                    endRadius: size * 0.5
                )
            )
            .frame(width: size, height: size)
            .blur(radius: 2)
            .allowsHitTesting(false)
    }
}

/// Tiled procedural grain — soft paper texture without an asset.
struct FilmGrainOverlay: View {
    var opacity: Double = 0.06

    var body: some View {
        Image(uiImage: FilmGrainCache.image)
            .resizable(resizingMode: .tile)
            .opacity(opacity)
            .blendMode(.softLight)
            .allowsHitTesting(false)
    }
}

private enum FilmGrainCache {
    static let image: UIImage = makeNoise(size: 128)

    private static func makeNoise(size: Int) -> UIImage {
        let width = size
        let height = size
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for i in stride(from: 0, to: pixels.count, by: 4) {
            let v = UInt8.random(in: 0...255)
            pixels[i] = v
            pixels[i + 1] = v
            pixels[i + 2] = v
            pixels[i + 3] = 255
        }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ),
        let cgImage = context.makeImage() else {
            return UIImage()
        }

        return UIImage(cgImage: cgImage)
    }
}

extension View {
    /// Fills behind content with the themed gradient + grain background.
    func themeBackground() -> some View {
        background { ThemeBackground() }
    }
}

/// True while the branded launch splash still covers the first destination.
private struct LaunchOverlayActiveKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var launchOverlayActive: Bool {
        get { self[LaunchOverlayActiveKey.self] }
        set { self[LaunchOverlayActiveKey.self] = newValue }
    }
}
