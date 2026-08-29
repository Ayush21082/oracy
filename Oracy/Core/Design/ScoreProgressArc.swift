import SwiftUI

/// Incomplete circular progress arc (Pi-style gap) for the home score.
/// Draws behind existing score content — does not replace typography or layout.
struct ScoreProgressArc: View {
    /// 0...1 fill amount along the open arc.
    let progress: Double
    var lineWidth: CGFloat = 5
    var trackColor: Color = Theme.accentMuted
    var fillColor: Color = Theme.accent

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animatedProgress: Double = 0

    /// Fraction of the circle left open (gap). ~0.22 ≈ 80°.
    private let gapFraction: CGFloat = 0.22

    var body: some View {
        ZStack {
            // Background track — incomplete ring with deliberate gap
            Circle()
                .trim(from: 0, to: 1 - gapFraction)
                .stroke(
                    trackColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )

            // Progress fill along the same open path
            Circle()
                .trim(from: 0, to: max(0.001, (1 - gapFraction) * animatedProgress))
                .stroke(
                    fillColor,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
        }
        // Rotate so the gap sits toward the bottom-right (Pi-like opening)
        .rotationEffect(.degrees(90 + Double(gapFraction) * 180))
        .accessibilityHidden(true)
        .onAppear {
            animate(to: clampedProgress)
        }
        .onChange(of: progress) { _, newValue in
            animate(to: min(1, max(0, newValue)))
        }
    }

    private var clampedProgress: Double {
        min(1, max(0, progress))
    }

    private func animate(to value: Double) {
        if reduceMotion {
            animatedProgress = value
            return
        }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.9)) {
            animatedProgress = value
        }
    }
}
