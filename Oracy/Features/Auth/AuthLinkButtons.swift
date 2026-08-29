import SwiftUI
import AuthenticationServices

/// Shared Apple / Google link controls used by onboarding and Settings auth sheet.
struct AuthLinkButtons: View {
    var onSuccess: () -> Void
    var onSkip: (() -> Void)? = nil
    var showsSkip: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @State private var isWorking = false
    @State private var applePresenter = AppleSignInPresenter()

    var body: some View {
        VStack(spacing: 12) {
            authProviderButton(
                title: "Continue with Apple",
                systemImage: "apple.logo",
                style: .apple
            ) {
                Task { await continueWithApple() }
            }

            authProviderButton(
                title: "Continue with Google",
                systemImage: nil,
                style: .google
            ) {
                Task { await signInGoogle() }
            }

            if showsSkip, let onSkip {
                Button("Skip for now") {
                    Haptics.light()
                    onSkip()
                }
                .font(Theme.grotesk(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 4)
            }
        }
    }

    private enum ProviderStyle {
        case apple, google
    }

    private func authProviderButton(
        title: String,
        systemImage: String?,
        style: ProviderStyle,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isWorking else { return }
            action()
        } label: {
            HStack(spacing: 12) {
                providerLogo(systemImage: systemImage, style: style)
                    .frame(width: 22, height: 22)

                if isWorking {
                    ProgressView()
                        .tint(labelColor(for: style))
                } else {
                    Text(title)
                        .font(Theme.grotesk(17, weight: .semibold))
                }
            }
            .foregroundStyle(labelColor(for: style))
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .background(background(for: style), in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(borderColor(for: style), lineWidth: style == .google ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .opacity(isWorking ? 0.7 : 1)
        .accessibilityLabel(title)
    }

    @ViewBuilder
    private func providerLogo(systemImage: String?, style: ProviderStyle) -> some View {
        switch style {
        case .apple:
            Image(systemName: systemImage ?? "apple.logo")
                .font(.system(size: 18, weight: .semibold))
        case .google:
            GoogleMark()
                .frame(width: 18, height: 18)
        }
    }

    private func labelColor(for style: ProviderStyle) -> Color {
        switch style {
        case .apple:
            return colorScheme == .dark ? .black : .white
        case .google:
            return Theme.textPrimary
        }
    }

    private func background(for style: ProviderStyle) -> Color {
        switch style {
        case .apple:
            return colorScheme == .dark ? .white : .black
        case .google:
            return Theme.cardBackground.opacity(0.92)
        }
    }

    private func borderColor(for style: ProviderStyle) -> Color {
        switch style {
        case .apple:
            return .clear
        case .google:
            return Theme.textSecondary.opacity(0.22)
        }
    }

    private func continueWithApple() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let (credential, nonce) = try await applePresenter.signIn()
            let idToken = try AppleSignInSupport.idToken(from: credential)
            try await AuthService.shared.signInWithApple(idToken: idToken, nonce: nonce)
            await AuthService.shared.applyAppleDisplayNameIfNeeded(credential.fullName)
            let name = AuthService.preferredDisplayName(
                AuthService.shared.profile?.displayName,
                AppleSignInSupport.displayName(from: credential.fullName)
            )
            LastSignedInIdentity.rememberApple(userID: credential.user, displayName: name)
            Haptics.success()
            onSuccess()
        } catch {
            if AppleSignInSupport.isUserCancel(error) { return }
            AppErrorCenter.shared.present(
                title: "Couldn’t sign in with Apple",
                message: "Check that Sign in with Apple is enabled for this app, then try again."
            )
        }
    }

    private func signInGoogle() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.shared.signInWithGoogle()
            let name = AuthService.preferredDisplayName(AuthService.shared.profile?.displayName)
            LastSignedInIdentity.rememberGoogle(displayName: name)
            Haptics.success()
            onSuccess()
        } catch {
            if Self.isGoogleCancel(error) { return }
            AppErrorCenter.shared.present(
                title: "Couldn’t continue with Google",
                message: (error as? LocalizedError)?.errorDescription
                    ?? "Check that Google Sign-In is enabled, then try again."
            )
        }
    }

    private static func isGoogleCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        // GIDSignInErrorCode.canceled == -5
        return ns.domain == "com.google.GIDSignIn" && ns.code == -5
    }
}

/// Compact Google “G” mark for auth buttons (no asset dependency).
struct GoogleMark: View {
    var body: some View {
        Canvas { context, size in
            let inset = size.width * 0.08
            let rect = CGRect(
                x: inset,
                y: inset,
                width: size.width - inset * 2,
                height: size.height - inset * 2
            )
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let radius = min(rect.width, rect.height) / 2
            let lineWidth = radius * 0.42
            let colors: [Color] = [
                Color(red: 0.26, green: 0.52, blue: 0.96), // blue
                Color(red: 0.22, green: 0.73, blue: 0.33), // green
                Color(red: 0.98, green: 0.74, blue: 0.02), // yellow
                Color(red: 0.92, green: 0.26, blue: 0.21)  // red
            ]
            let segments: [(start: Double, end: Double)] = [
                (-40, 50),
                (50, 140),
                (140, 230),
                (230, 320)
            ]
            for (index, segment) in segments.enumerated() {
                var path = Path()
                path.addArc(
                    center: center,
                    radius: radius - lineWidth / 2,
                    startAngle: .degrees(segment.start),
                    endAngle: .degrees(segment.end),
                    clockwise: false
                )
                context.stroke(
                    path,
                    with: .color(colors[index]),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt)
                )
            }

            // Horizontal bar of the G
            let barHeight = lineWidth * 0.92
            let barRect = CGRect(
                x: center.x,
                y: center.y - barHeight / 2,
                width: radius - lineWidth * 0.15,
                height: barHeight
            )
            context.fill(Path(barRect), with: .color(colors[0]))
        }
        .accessibilityHidden(true)
    }
}
