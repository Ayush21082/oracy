import SwiftUI

/// Full-bleed analysis curtain. Falls downward as `fallProgress` goes 0 → 1.
struct AnalysisGradientCurtain: View {
    /// 0 = covering the screen, 1 = fully fallen off the bottom.
    var fallProgress: CGFloat
    var reduceMotion: Bool

    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let travel = height * 1.2
            let y = fallProgress * travel

            ZStack {
                ambientField
                softBottomVeil
            }
            .frame(width: geo.size.width, height: height + 80)
            .offset(y: y)
            // Soft trailing dissolve so the fall reads as gradient, not a hard slab
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.78),
                        .init(color: .black.opacity(0.45), location: 0.9),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(fallProgress < 0.95)
        .accessibilityHidden(true)
    }

    private var ambientField: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 24, paused: reduceMotion || fallProgress > 0.02)) { timeline in
            let t = reduceMotion || fallProgress > 0.02
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
            let wave = CGFloat(sin(t * 0.45) * 0.5 + 0.5)
            let wave2 = CGFloat(sin(t * 0.31 + 1.1) * 0.5 + 0.5)

            ZStack {
                LinearGradient(
                    colors: isDark ? darkBase : lightBase,
                    startPoint: UnitPoint(x: 0.2 + wave * 0.06, y: 0),
                    endPoint: UnitPoint(x: 0.8 - wave * 0.05, y: 1)
                )

                RadialGradient(
                    colors: isDark
                        ? [
                            Color(red: 0.82, green: 0.56, blue: 0.46).opacity(0.42),
                            Color(red: 0.82, green: 0.56, blue: 0.46).opacity(0.12),
                            .clear
                        ]
                        : [
                            Color(red: 0.82, green: 0.52, blue: 0.42).opacity(0.58),
                            Color(red: 0.82, green: 0.52, blue: 0.42).opacity(0.16),
                            .clear
                        ],
                    center: UnitPoint(x: 0.8 + wave * 0.06, y: 0.18 + wave2 * 0.05),
                    startRadius: 16,
                    endRadius: 420
                )

                RadialGradient(
                    colors: isDark
                        ? [
                            Color(red: 0.52, green: 0.72, blue: 0.56).opacity(0.28),
                            Color(red: 0.52, green: 0.72, blue: 0.56).opacity(0.08),
                            .clear
                        ]
                        : [
                            Color(red: 0.58, green: 0.70, blue: 0.62).opacity(0.5),
                            Color(red: 0.58, green: 0.70, blue: 0.62).opacity(0.1),
                            .clear
                        ],
                    center: UnitPoint(x: 0.14 - wave * 0.04, y: 0.82 - wave2 * 0.04),
                    startRadius: 10,
                    endRadius: 400
                )

                RadialGradient(
                    colors: isDark
                        ? [
                            Color(red: 0.92, green: 0.74, blue: 0.40).opacity(0.18),
                            .clear
                        ]
                        : [
                            Color(red: 0.90, green: 0.72, blue: 0.48).opacity(0.3),
                            .clear
                        ],
                    center: UnitPoint(x: 0.48 + wave2 * 0.08, y: 0.42 + wave * 0.06),
                    startRadius: 8,
                    endRadius: 280
                )
            }
        }
    }

    private var lightBase: [Color] {
        [
            Color(red: 0.97, green: 0.94, blue: 0.90),
            Color(red: 0.93, green: 0.86, blue: 0.80),
            Color(red: 0.86, green: 0.74, blue: 0.68)
        ]
    }

    private var darkBase: [Color] {
        [
            Color(red: 0.18, green: 0.14, blue: 0.13),
            Color(red: 0.13, green: 0.11, blue: 0.10),
            Color(red: 0.09, green: 0.08, blue: 0.07)
        ]
    }

    private var softBottomVeil: some View {
        LinearGradient(
            colors: isDark
                ? [
                    Color.white.opacity(0.06),
                    .clear,
                    Color(red: 0.82, green: 0.56, blue: 0.46).opacity(0.12)
                ]
                : [
                    Color.white.opacity(0.14),
                    .clear,
                    Color(red: 0.55, green: 0.40, blue: 0.34).opacity(0.1)
                ],
            startPoint: .top,
            endPoint: .bottom
        )
        .allowsHitTesting(false)
    }
}

// MARK: - Loading vocabulary

enum AnalysisLoadingCopy {
    static let phrases: [String] = [
        "Listening closely…",
        "Finding your voice…",
        "Tracing your rhythm…",
        "Gathering insights…",
        "Shaping your feedback…",
        "Reading between the lines…",
        "Tuning into nuance…",
        "Polishing your notes…",
        "Weaving your story…",
        "Capturing clarity…",
        "Noticing the pauses…",
        "Mapping your momentum…"
    ]

    static func randomPhrase(excluding current: String? = nil) -> String {
        let pool = phrases.filter { $0 != current }
        return pool.randomElement() ?? phrases[0]
    }
}
