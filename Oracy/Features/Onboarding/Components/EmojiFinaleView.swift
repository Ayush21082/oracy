import SwiftUI

/// Subtle floating emoji cluster for the onboarding finale.
struct EmojiFinaleView: View {
    var emojis: [String] = ["👋", "✨", "🧠", "🎙️", "🚀"]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0
    @State private var appeared = false

    var body: some View {
        TimelineView(.animation(minimumInterval: reduceMotion ? 60 : 1 / 30, paused: reduceMotion)) { timeline in
            let t = reduceMotion
                ? 0
                : timeline.date.timeIntervalSinceReferenceDate
            HStack(spacing: 14) {
                ForEach(Array(emojis.enumerated()), id: \.offset) { index, emoji in
                    let offset = Double(index) * 0.7
                    let y = sin(t * 0.9 + offset) * 6
                    let rot = sin(t * 0.55 + offset) * 6
                    let scale = 1 + sin(t * 0.7 + offset) * 0.04

                    Text(emoji)
                        .font(.system(size: 36))
                        .offset(y: appeared ? y : 12)
                        .rotationEffect(.degrees(appeared ? rot : 0))
                        .scaleEffect(appeared ? scale : 0.86)
                        .opacity(appeared ? 1 : 0)
                }
            }
        }
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .themeBounce) {
                appeared = true
            }
        }
        .accessibilityHidden(true)
    }
}
