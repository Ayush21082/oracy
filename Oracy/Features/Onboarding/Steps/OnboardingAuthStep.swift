import SwiftUI
import AuthenticationServices

struct OnboardingAuthStep: View {
    var onContinue: () -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var showActions = false
    @State private var showMore = false
    @State private var currentNonce: String?
    @State private var isWorking = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            ConversationalText(
                lines: [
                    "Have we met before?",
                    "Let's see if we can make this a little quicker."
                ],
                mode: .sequenced(delay: 0.5),
                font: Theme.fraunces(30, weight: .bold)
            ) {
                withAnimation(.themeBounce) { showActions = true }
            }
            .padding(.horizontal, 32)

            Spacer()

            VStack(spacing: 12) {
                SignInWithAppleButton(.continue) { request in
                    let nonce = AppleSignInSupport.makeNonce()
                    currentNonce = nonce
                    AppleSignInSupport.configureRequest(request, rawNonce: nonce)
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                .frame(height: Theme.minTapTarget)
                .clipShape(Capsule())
                .disabled(isWorking)

                if RemoteConfigService.shared.isGoogleAuthEnabled {
                    if showMore {
                        Button {
                            Task { await signInGoogle() }
                        } label: {
                            if isWorking {
                                ProgressView().tint(Theme.accent)
                            } else {
                                Text("Continue with Google")
                                    .font(Theme.grotesk(17, weight: .medium))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Theme.minTapTarget)
                        .buttonStyle(.glass)
                        .disabled(isWorking)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else {
                        OnboardingSecondaryButton(title: "Continue another way") {
                            withAnimation(.themeBounce) { showMore = true }
                        }
                    }
                }

                OnboardingSecondaryButton(title: "Continue as guest") {
                    onContinue()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .opacity(showActions ? 1 : 0)
            .offset(y: showActions ? 0 : 12)
            .allowsHitTesting(showActions)
        }
    }

    private func signInGoogle() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await AuthService.shared.signInWithGoogle()
            Haptics.success()
            onContinue()
        } catch {
            AppErrorCenter.shared.presentFriendly()
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = currentNonce else {
                AppErrorCenter.shared.presentFriendly()
                return
            }

            Task {
                isWorking = true
                defer { isWorking = false }
                do {
                    let idToken = try AppleSignInSupport.idToken(from: credential)
                    try await AuthService.shared.signInWithApple(idToken: idToken, nonce: nonce)
                    await AuthService.shared.applyAppleDisplayNameIfNeeded(credential.fullName)
                    Haptics.success()
                    onContinue()
                } catch {
                    AppErrorCenter.shared.present(
                        title: "Couldn’t continue with Apple",
                        message: "Check that Sign in with Apple is enabled, then try again."
                    )
                }
            }
        case .failure(let error):
            if AppleSignInSupport.isUserCancel(error) { return }
            AppErrorCenter.shared.present(
                title: "Couldn’t continue with Apple",
                message: "Something went wrong with Apple. Please try again."
            )
        }
    }
}
