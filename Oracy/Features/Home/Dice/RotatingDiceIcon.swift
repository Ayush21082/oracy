import SwiftUI

/// Compact dice glyph — spins only while a shuffle is in progress.
struct RotatingDiceIcon: View {
    var isSpinning: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var angle: Double = 0

    var body: some View {
        Image(systemName: "dice.fill")
            .rotationEffect(.degrees(angle))
            .onChange(of: isSpinning) { _, spinning in
                updateSpin(spinning)
            }
            .onAppear {
                updateSpin(isSpinning)
            }
            .accessibilityHidden(true)
    }

    private func updateSpin(_ spinning: Bool) {
        if reduceMotion || !spinning {
            withAnimation(.easeOut(duration: 0.25)) {
                angle = 0
            }
            return
        }
        angle = 0
        withAnimation(.linear(duration: 0.6).repeatForever(autoreverses: false)) {
            angle = 360
        }
    }
}
