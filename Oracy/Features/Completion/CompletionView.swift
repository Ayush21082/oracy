import SwiftUI
import AVFoundation
import UIKit

struct CompletionView: View {
    let streakCount: Int
    let durationSeconds: Double
    let wordCount: Int
    let fillerCount: Int
    var overallScore: Int? = nil
    let onDone: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var showConfetti = false
    @State private var soundPlayer: AVAudioPlayer?

    private var stats: [CompletionStat] {
        let score = overallScore ?? 0
        return [
            CompletionStat(
                text: "\(Int(durationSeconds)) seconds spoken",
                passed: durationSeconds >= 45 || score >= 70
            ),
            CompletionStat(
                text: "\(wordCount) words",
                passed: wordCount >= 60 || score >= 75
            ),
            CompletionStat(
                text: "\(fillerCount) filler word\(fillerCount == 1 ? "" : "s")",
                passed: fillerCount <= 3 || (score >= 80 && fillerCount <= 5)
            )
        ]
    }

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                Spacer(minLength: 24)

                VStack(spacing: 28) {
                    if streakCount > 0 {
                        HStack(spacing: 6) {
                            Text("🔥")
                            Text("\(streakCount) day streak")
                                .font(Theme.grotesk(18, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                        }
                        .scaleEffect(appeared ? 1 : 0.7)
                        .opacity(appeared ? 1 : 0)
                        .accessibilityLabel("\(streakCount) day streak")
                    }

                    Text("Today's practice\ncompleted.")
                        .font(Theme.fraunces(34, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .scaleEffect(appeared ? 1 : 0.92)
                        .opacity(appeared ? 1 : 0)

                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(stats) { stat in
                            HStack(spacing: 12) {
                                Image(systemName: stat.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(stat.passed ? Theme.success : Theme.accent)
                                    .frame(width: 24, alignment: .center)

                                Text(stat.text)
                                    .font(Theme.grotesk(17, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("\(stat.text), \(stat.passed ? "good" : "needs work")")
                        }
                    }
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity)
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)

                Spacer(minLength: 24)

                Button("Done", action: onDone)
                    .buttonStyle(PrimaryButtonStyle(minHeight: 60, fontSize: 18))
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
            }

            if showConfetti && !reduceMotion {
                ConfettiCannonView()
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .task {
            AnalyticsService.shared.track(.completionViewed, [
                "streak": String(streakCount),
                "score": String(overallScore ?? 0)
            ])
            Haptics.success()
            withAnimation(reduceMotion ? .none : .themeBounce) {
                appeared = true
            }

            // Let the first layout + content animation settle before effects.
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 120))
            guard !Task.isCancelled else { return }

            if !reduceMotion {
                showConfetti = true
            }
            playCelebrationSound()
        }
        .onDisappear {
            soundPlayer?.stop()
            soundPlayer = nil
        }
    }

    private func playCelebrationSound() {
        guard let url = Bundle.main.url(forResource: "celebration", withExtension: "wav") else {
            return
        }
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.85
            player.prepareToPlay()
            player.play()
            soundPlayer = player
        } catch {
            // Non-fatal — visual celebration still runs.
        }
    }
}

private struct CompletionStat: Identifiable {
    let id = UUID()
    let text: String
    let passed: Bool
}
