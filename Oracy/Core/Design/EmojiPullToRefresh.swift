import SwiftUI

// MARK: - Public API

extension View {
    /// Custom pull-to-refresh that shows a random emoji instead of the system spinner.
    func emojiPullToRefresh(action: @escaping () async -> Void) -> some View {
        modifier(EmojiPullToRefreshModifier(action: action))
    }
}

// MARK: - Modifier

private struct EmojiPullToRefreshModifier: ViewModifier {
    let action: () async -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pullDistance: CGFloat = 0
    @State private var isRefreshing = false
    @State private var isArmed = false
    @State private var emoji = "🔥"
    @State private var didPickEmoji = false
    @State private var bounce = false

    private let threshold: CGFloat = 72

    private static let pool: [String] = [
        "🔥", "🎙️", "🗣️", "💬", "🧠", "✨", "🎯", "⚡",
        "🌊", "🎤", "📖", "🏆", "👏", "💫", "🚀", "⭐",
        "💡", "🎵", "🙌", "🌈", "🪄", "🦋", "☕", "🌙"
    ]

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                -(geometry.contentOffset.y + geometry.contentInsets.top)
            } action: { _, rawPull in
                handlePull(max(0, rawPull))
            }
            .onScrollPhaseChange { _, newPhase in
                guard newPhase == .idle else { return }
                if isArmed && !isRefreshing {
                    startRefresh()
                } else if !isRefreshing {
                    resetPullState()
                }
            }
            .overlay(alignment: .top) {
                emojiIndicator
                    .allowsHitTesting(false)
            }
    }

    private var emojiIndicator: some View {
        let progress = min(pullDistance / threshold, 1.2)
        let visible = isRefreshing || pullDistance > 6

        return Text(emoji)
            .font(.system(size: 34))
            .scaleEffect(isRefreshing ? (bounce ? 1.12 : 0.92) : (0.55 + 0.45 * min(progress, 1)))
            .rotationEffect(.degrees(isRefreshing ? 0 : Double((progress - 1) * 12)))
            .opacity(visible ? (isRefreshing ? 1 : min(progress * 1.2, 1)) : 0)
            .offset(y: indicatorOffset)
            .accessibilityHidden(true)
    }

    private var indicatorOffset: CGFloat {
        if isRefreshing { return 10 }
        return max(pullDistance * 0.55 - 28, -20)
    }

    private func handlePull(_ distance: CGFloat) {
        pullDistance = distance

        guard !isRefreshing else { return }

        if distance > 10, !didPickEmoji {
            emoji = Self.pool.randomElement() ?? "✨"
            didPickEmoji = true
        }

        if distance >= threshold, !isArmed {
            isArmed = true
            Haptics.light()
        } else if distance < threshold * 0.55 {
            isArmed = false
        }
    }

    private func startRefresh() {
        isRefreshing = true
        isArmed = false
        Haptics.soft()

        if !reduceMotion {
            withAnimation(.easeInOut(duration: 0.45).repeatForever(autoreverses: true)) {
                bounce = true
            }
        }

        Task {
            await action()
            await MainActor.run {
                finishRefresh()
            }
        }
    }

    private func finishRefresh() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            bounce = false
        }
        withAnimation(.easeOut(duration: 0.22)) {
            isRefreshing = false
            pullDistance = 0
        }
        resetPullState()
    }

    private func resetPullState() {
        isArmed = false
        didPickEmoji = false
    }
}
