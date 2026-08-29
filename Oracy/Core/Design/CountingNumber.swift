import SwiftUI

/// Integer that ticks digitally from its previous value to `value`.
struct CountingNumber: View {
    let value: Int
    var duration: TimeInterval = 0.9
    var font: Font = Theme.fraunces(48, weight: .semibold)
    var foreground: Color = Theme.textPrimary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayed = 0
    @State private var hasAppeared = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        Text("\(displayed)")
            .font(font)
            .foregroundStyle(foreground)
            .monospacedDigit()
            .contentTransition(.numericText())
            .onAppear {
                guard !hasAppeared else { return }
                hasAppeared = true
                // First paint: always count up from 0 → target
                displayed = 0
                animate(to: value)
            }
            .onChange(of: value) { _, newValue in
                animate(to: newValue)
            }
            .onDisappear {
                animationTask?.cancel()
            }
            .accessibilityLabel("\(value)")
    }

    private func animate(to target: Int) {
        animationTask?.cancel()

        if reduceMotion || displayed == target {
            displayed = target
            return
        }

        let from = displayed
        let delta = target - from
        guard delta != 0 else { return }

        let steps = abs(delta)
        // Keep animation snappy for large jumps (e.g. 0→100)
        let stepCount = min(steps, 40)
        let stepSize = Double(delta) / Double(stepCount)
        let interval = duration / Double(stepCount)

        animationTask = Task { @MainActor in
            for i in 1...stepCount {
                if Task.isCancelled { return }
                let next = i == stepCount
                    ? target
                    : from + Int((stepSize * Double(i)).rounded())
                withAnimation(.linear(duration: interval * 0.85)) {
                    displayed = next
                }
                try? await Task.sleep(for: .seconds(interval))
            }
            displayed = target
            Haptics.soft()
        }
    }
}
