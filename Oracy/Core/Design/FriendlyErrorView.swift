import SwiftUI

// MARK: - Global presenter

/// App-wide friendly errors — never surfaces technical messages to the user.
@Observable
@MainActor
final class AppErrorCenter {
    static let shared = AppErrorCenter()

    private(set) var isPresented = false
    private(set) var title = FriendlyErrorCopy.defaultTitle
    private(set) var message = FriendlyErrorCopy.defaultMessage
    private var retryHandler: (() -> Void)?

    func present(
        title: String? = nil,
        message: String? = nil,
        retry: (() -> Void)? = nil
    ) {
        self.title = title ?? FriendlyErrorCopy.defaultTitle
        self.message = message ?? FriendlyErrorCopy.defaultMessage
        self.retryHandler = retry
        withAnimation(reduceMotionPreferred ? .easeOut(duration: 0.2) : .themeBounce) {
            isPresented = true
        }
        Haptics.soft()
    }

    /// Convenience: always shows calm copy; ignores technical `Error` text.
    func presentFriendly(retry: (() -> Void)? = nil) {
        present(title: nil, message: nil, retry: retry)
    }

    func dismiss() {
        withAnimation(.easeOut(duration: 0.22)) {
            isPresented = false
        }
        retryHandler = nil
    }

    func retry() {
        let action = retryHandler
        dismiss()
        action?()
    }

    private var reduceMotionPreferred: Bool {
        UIAccessibility.isReduceMotionEnabled
    }
}

enum FriendlyErrorCopy {
    nonisolated static let defaultTitle = "Please try again"
    nonisolated static let defaultMessage = "Something didn’t go through just now. Nothing’s lost — take a breath and try once more."
    nonisolated static let uploadTitle = "Couldn’t finish that"
    nonisolated static let uploadMessage = "Your practice is still here. Give it another moment and we’ll pick up where you left off."
    nonisolated static let loadTitle = "Couldn’t load that"
    nonisolated static let loadMessage = "The connection hiccuped. Pull to refresh or try again in a moment."
    nonisolated static let deleteTitle = "Couldn’t complete that"
    nonisolated static let deleteMessage = "Nothing was changed. Please try again in a moment."
}

// MARK: - Full-screen page

struct FriendlyErrorView: View {
    var title: String = FriendlyErrorCopy.defaultTitle
    var message: String = FriendlyErrorCopy.defaultMessage
    var retryTitle: String = "Try again"
    var showsDismiss: Bool = true
    var onRetry: (() -> Void)?
    var onDismiss: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var breathe = false

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 0) {
                if showsDismiss {
                    HStack {
                        Spacer()
                        Button {
                            Haptics.light()
                            onDismiss?()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss")
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }

                Spacer(minLength: 24)

                VStack(spacing: 28) {
                    SoftPauseMark(breathe: breathe)
                        .scaleEffect(appeared ? 1 : 0.86)
                        .opacity(appeared ? 1 : 0)

                    VStack(spacing: 12) {
                        Text(title)
                            .font(Theme.fraunces(34, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(message)
                            .font(Theme.grotesk(16))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 8)
                    }
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 10)
                }
                .padding(.horizontal, 28)

                Spacer(minLength: 24)

                VStack(spacing: 12) {
                    if onRetry != nil {
                        Button(retryTitle) {
                            Haptics.medium()
                            onRetry?()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }

                    if showsDismiss, onDismiss != nil {
                        Button("Not now") {
                            Haptics.light()
                            onDismiss?()
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .opacity(appeared ? 1 : 0)
            }
        }
        .accessibilityElement(children: .contain)
        .onAppear {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .themeBounce) {
                appeared = true
            }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                breathe = true
            }
        }
    }
}

// MARK: - Soft mark

private struct SoftPauseMark: View {
    var breathe: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.accent.opacity(0.10))
                .frame(width: 148, height: 148)
                .scaleEffect(breathe ? 1.06 : 0.94)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.92, green: 0.62, blue: 0.48).opacity(0.35),
                            Theme.accent.opacity(0.18),
                            .clear
                        ],
                        center: UnitPoint(x: 0.4, y: 0.35),
                        startRadius: 4,
                        endRadius: 70
                    )
                )
                .frame(width: 120, height: 120)

            Circle()
                .fill(Theme.cardBackground.opacity(0.92))
                .frame(width: 88, height: 88)
                .shadow(color: Theme.accent.opacity(0.18), radius: 16, y: 6)

            SoftPauseWave()
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 42, height: 22)
                .opacity(0.9)
        }
        .accessibilityHidden(true)
    }
}

private struct SoftPauseWave: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let w = rect.width
        let h = rect.height

        path.move(to: CGPoint(x: 0, y: midY))
        path.addCurve(
            to: CGPoint(x: w * 0.28, y: midY - h * 0.32),
            control1: CGPoint(x: w * 0.1, y: midY),
            control2: CGPoint(x: w * 0.18, y: midY - h * 0.32)
        )
        path.addCurve(
            to: CGPoint(x: w * 0.55, y: midY + h * 0.28),
            control1: CGPoint(x: w * 0.38, y: midY - h * 0.32),
            control2: CGPoint(x: w * 0.45, y: midY + h * 0.28)
        )
        path.addCurve(
            to: CGPoint(x: w, y: midY),
            control1: CGPoint(x: w * 0.68, y: midY + h * 0.28),
            control2: CGPoint(x: w * 0.86, y: midY)
        )
        return path
    }
}

// MARK: - Inline state (embedded screens)

struct FriendlyErrorInline: View {
    var title: String = FriendlyErrorCopy.defaultTitle
    var message: String = FriendlyErrorCopy.defaultMessage
    var retryTitle: String = "Try again"
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            SoftPauseMark(breathe: false)
                .scaleEffect(0.72)
                .frame(height: 110)

            VStack(spacing: 8) {
                Text(title)
                    .font(Theme.fraunces(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(Theme.grotesk(15))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let onRetry {
                Button(retryTitle, action: onRetry)
                    .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Overlay modifier

extension View {
    /// Presents the global friendly error page above the app.
    func appErrorOverlay() -> some View {
        modifier(AppErrorOverlayModifier())
    }
}

private struct AppErrorOverlayModifier: ViewModifier {
    @State private var errors = AppErrorCenter.shared

    func body(content: Content) -> some View {
        content
            .overlay {
                if errors.isPresented {
                    FriendlyErrorView(
                        title: errors.title,
                        message: errors.message,
                        onRetry: { errors.retry() },
                        onDismiss: { errors.dismiss() }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .zIndex(999)
                }
            }
            .animation(.easeOut(duration: 0.25), value: errors.isPresented)
    }
}

#if DEBUG
#Preview("Full page") {
    FriendlyErrorView(
        onRetry: {},
        onDismiss: {}
    )
}

#Preview("Inline") {
    FriendlyErrorInline(onRetry: {})
        .padding()
        .themeBackground()
}
#endif
