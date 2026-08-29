import AuthenticationServices
import CryptoKit
import Foundation

/// Shared Sign in with Apple helpers (nonce + credential parsing).
enum AppleSignInSupport {
    /// Raw nonce for Supabase `signInWithIdToken` / `linkIdentityWithIdToken`.
    static func makeNonce(length: Int = 32) -> String {
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        precondition(status == errSecSuccess, "Unable to generate nonce")
        return randomBytes.map { String(format: "%02x", $0) }.joined()
    }

    /// SHA256 hex digest — pass this as `request.nonce` to Apple.
    static func sha256Nonce(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    static func configureRequest(_ request: ASAuthorizationAppleIDRequest, rawNonce: String) {
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256Nonce(rawNonce)
    }

    static func idToken(from credential: ASAuthorizationAppleIDCredential) throws -> String {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              !idToken.isEmpty else {
            throw AuthError.noIdToken
        }
        return idToken
    }

    static func displayName(from fullName: PersonNameComponents?) -> String? {
        guard let fullName else { return nil }
        let parts = [fullName.givenName, fullName.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " ")
    }

    static func isUserCancel(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == ASAuthorizationError.errorDomain,
           ns.code == ASAuthorizationError.canceled.rawValue {
            return true
        }
        return false
    }
}
