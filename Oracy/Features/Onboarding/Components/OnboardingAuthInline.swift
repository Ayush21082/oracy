import SwiftUI
import AuthenticationServices

/// Compact Apple / Google / phone / guest controls for the active auth beat.
struct OnboardingAuthInline: View {
    @Binding var showMore: Bool
    /// Name typed earlier in onboarding (preferred over cached identity when present).
    var preferredName: String = ""
    var onAuthenticated: (OnboardingAnswers.AuthChoice) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWorking = false
    @State private var showReturningCTA = false
    @State private var returningAvatar: UIImage?
    @State private var applePresenter = AppleSignInPresenter()
    @State private var mode: Mode = .providers

    private enum Mode: Equatable {
        case providers
        case phone
    }

    private var resolvedName: String {
        let typed = preferredName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty { return typed }
        if let cached = LastSignedInIdentity.displayName { return cached }
        return "Speaker"
    }

    var body: some View {
        Group {
            switch mode {
            case .providers:
                providersContent
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            case .phone:
                PhoneOTPFlowView(
                    title: "What's your number?",
                    subtitle: "We'll text a 6-digit code to verify it's you.",
                    onVerified: {
                        // Returning phone user: claim adopts a phone-only profile, or the
                        // app switches into the existing Apple/Google owner after OTP.
                        if AuthService.shared.profile?.onboardingCompleted == true {
                            return
                        }
                        onAuthenticated(.phone)
                    },
                    onCancel: {
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                            mode = .providers
                        }
                    }
                )
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce, value: mode)
        .task {
            showReturningCTA = await shouldShowReturningCTA()
            if showReturningCTA {
                returningAvatar = LastSignedInIdentity.cachedAvatarImage
            }
        }
    }

    private var providersContent: some View {
        VStack(spacing: 14) {
            if showReturningCTA {
                returningAppleCTA
            } else {
                primaryAppleButton
            }

            orDivider

            if showMore {
                anotherWaysRow
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                Button {
                    Haptics.light()
                    withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                        showMore = true
                    }
                } label: {
                    Text("Log in another way")
                        .font(Theme.grotesk(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
                .disabled(isWorking)
            }
        }
    }

    // MARK: - Returning user

    private var returningAppleCTA: some View {
        Button {
            Task { await continueWithApple() }
        } label: {
            HStack(spacing: 14) {
                ProfileAvatarView(
                    size: 44,
                    borderWidth: 1.5,
                    uiImage: returningAvatar,
                    imageURL: returningAvatar == nil ? LastSignedInIdentity.remoteAvatarURL : nil
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(resolvedName)
                        .font(Theme.grotesk(17, weight: .semibold))
                        .foregroundStyle(Color(red: 0.99, green: 0.98, blue: 0.96))
                        .lineLimit(1)
                    Text("Continue with Apple")
                        .font(Theme.grotesk(13, weight: .medium))
                        .foregroundStyle(Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.82))
                }

                Spacer(minLength: 8)

                if isWorking {
                    ProgressView()
                        .tint(Color(red: 0.99, green: 0.98, blue: 0.96))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.99, green: 0.98, blue: 0.96).opacity(0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
            .background(returningGradient, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("Continue with Apple as \(resolvedName)")
    }

    private var returningGradient: some ShapeStyle {
        LinearGradient(
            colors: [
                Theme.accent,
                Color(red: 0.78, green: 0.48, blue: 0.38),
                Color(red: 0.86, green: 0.60, blue: 0.48)
            ],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - First-time Apple

    private var primaryAppleButton: some View {
        Button {
            Task { await continueWithApple() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 18, weight: .semibold))
                if isWorking {
                    ProgressView()
                        .tint(colorScheme == .dark ? .black : .white)
                } else {
                    Text("Continue with Apple")
                        .font(Theme.grotesk(17, weight: .semibold))
                }
            }
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Theme.minTapTarget)
            .background(colorScheme == .dark ? Color.white : Color.black, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityLabel("Continue with Apple")
    }

    // MARK: - Another ways

    private var orDivider: some View {
        Text("or")
            .font(Theme.grotesk(13, weight: .medium))
            .foregroundStyle(Theme.textSecondary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    private var anotherWaysRow: some View {
        VStack(spacing: 10) {
            Text("Log in another way")
                .font(Theme.grotesk(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            HStack(spacing: 8) {
                if RemoteConfigService.shared.isGoogleAuthEnabled {
                    anotherWayChip(title: "Google") {
                        GoogleMark()
                            .frame(width: 18, height: 18)
                    } action: {
                        Task { await signInGoogle() }
                    }
                }

                if RemoteConfigService.shared.isPhoneAuthEnabled {
                    anotherWayChip(title: "Phone") {
                        Image(systemName: "iphone")
                            .font(.system(size: 17, weight: .semibold))
                    } action: {
                        Haptics.light()
                        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .themeBounce) {
                            mode = .phone
                        }
                    }
                }

                anotherWayChip(title: "Guest") {
                    Image(systemName: "person.fill")
                        .font(.system(size: 17, weight: .semibold))
                } action: {
                    Haptics.light()
                    onAuthenticated(.guest)
                }
            }
        }
    }

    private func anotherWayChip<Icon: View>(
        title: String,
        @ViewBuilder icon: () -> Icon,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard !isWorking else { return }
            action()
        } label: {
            VStack(spacing: 6) {
                icon()
                    .frame(height: 20)
                Text(title)
                    .font(Theme.grotesk(12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 64)
        }
        .buttonStyle(.glass)
        .disabled(isWorking)
    }

    // MARK: - Actions

    private func shouldShowReturningCTA() async -> Bool {
        if LastSignedInIdentity.hasReturningAppleUser {
            return true
        }
        // Mock: treat previously linked Apple as returning.
        if AppConfig.useMockBackend, AuthService.shared.isAppleLinked {
            return true
        }
        guard let appleUserID = LastSignedInIdentity.appleUserID else { return false }
        return await withCheckedContinuation { cont in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, _ in
                cont.resume(returning: state == .authorized)
            }
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
                AppleSignInSupport.displayName(from: credential.fullName),
                preferredName
            )
            LastSignedInIdentity.rememberApple(userID: credential.user, displayName: name)

            onAuthenticated(.apple)
        } catch {
            if AppleSignInSupport.isUserCancel(error) { return }
            AppErrorCenter.shared.present(
                title: "Couldn’t continue with Apple",
                message: "Check that Sign in with Apple is enabled, then try again."
            )
        }
    }

    private func signInGoogle() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.shared.signInWithGoogle()
            let name = AuthService.preferredDisplayName(
                AuthService.shared.profile?.displayName,
                preferredName
            )
            LastSignedInIdentity.rememberGoogle(displayName: name)
            onAuthenticated(.google)
        } catch {
            let ns = error as NSError
            if ns.domain == "com.google.GIDSignIn", ns.code == -5 { return }
            AppErrorCenter.shared.present(
                title: "Couldn’t continue with Google",
                message: (error as? LocalizedError)?.errorDescription
                    ?? "Check that Google Sign-In is enabled, then try again."
            )
        }
    }
}
