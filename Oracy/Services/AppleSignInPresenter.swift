import AuthenticationServices
import UIKit

/// Presents the system Sign in with Apple sheet from a custom button.
@MainActor
final class AppleSignInPresenter: NSObject {
    private var continuation: CheckedContinuation<ASAuthorizationAppleIDCredential, Error>?
    private var rawNonce: String?

    func signIn() async throws -> (credential: ASAuthorizationAppleIDCredential, nonce: String) {
        let nonce = AppleSignInSupport.makeNonce()
        rawNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        AppleSignInSupport.configureRequest(request, rawNonce: nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self

        let credential: ASAuthorizationAppleIDCredential = try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            controller.performRequests()
        }
        return (credential, nonce)
    }
}

extension AppleSignInPresenter: ASAuthorizationControllerDelegate {
    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            continuation?.resume(throwing: AuthError.noIdToken)
            continuation = nil
            return
        }
        continuation?.resume(returning: credential)
        continuation = nil
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

extension AppleSignInPresenter: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
    }
}
