import SwiftUI

struct AuthSheet: View {
    var showsSkip: Bool = true
    var title: String = "Save your progress"
    var message: String = "Link your account to keep your streak and history across devices."
    /// Called after a successful Apple/Google link (sheet also dismisses).
    var onAuthenticated: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()

                Theme.title(title)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Theme.body(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 32)

                Spacer()

                AuthLinkButtons(
                    onSuccess: {
                        onAuthenticated?()
                        dismiss()
                    },
                    onSkip: showsSkip ? { dismiss() } : nil,
                    showsSkip: showsSkip
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
            .themeBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: showsSkip ? .cancellationAction : .confirmationAction) {
                    Button(showsSkip ? "Skip" : "Close") { dismiss() }
                }
            }
        }
        .appErrorOverlay()
    }
}
