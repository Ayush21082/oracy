import Foundation
import UIKit
import AuthenticationServices
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
import Supabase

@MainActor
@Observable
final class AuthService {
    static let shared = AuthService()

    /// Local identity used by the rest of the app (works in mock + supabase).
    var userId: UUID?
    var profile: Profile?
    var isLoading = true
    var errorMessage: String?
    /// Linked Sign in with Apple identity.
    var isAppleLinked = false
    /// Linked Google identity.
    var isGoogleLinked = false
    /// Linked phone (E.164), when verified.
    var isPhoneLinked = false
    /// Display / storage form of the linked phone (E.164, e.g. `+919876543210`).
    var linkedPhone: String?

    private var client: SupabaseClient { SupabaseManager.shared.client }
    private let mockAppleKey = "auth.mock.appleLinked"
    private let mockGoogleKey = "auth.mock.googleLinked"
    private let mockPhoneKey = "auth.mock.phoneLinked"
    private let mockPhoneNumberKey = "auth.mock.phoneNumber"
    /// Pending phone while waiting for Firebase OTP (mock path only uses this).
    private var pendingPhoneE164: String?

    private init() {}

    /// True when Apple, Google, and/or phone is linked (not guest-only).
    var hasLinkedAccount: Bool { isAppleLinked || isGoogleLinked || isPhoneLinked }

    /// Same as `hasLinkedAccount` — use for feature gates (speak, rewards, Pro).
    var isLoggedIn: Bool { hasLinkedAccount }

    /// Indian mobile: 10 digits → `+91XXXXXXXXXX`.
    static func e164IndianMobile(fromDigits digits: String) -> String? {
        let cleaned = digits.filter(\.isNumber)
        guard cleaned.count == 10 else { return nil }
        return "+91\(cleaned)"
    }

    /// Pretty local display for a linked Indian number.
    static func displayPhone(_ e164: String?) -> String? {
        guard let e164, !e164.isEmpty else { return nil }
        let digits = e164.filter(\.isNumber)
        if digits.count == 12, digits.hasPrefix("91") {
            let local = String(digits.suffix(10))
            return "+91 \(local.prefix(5)) \(local.suffix(5))"
        }
        return e164
    }

    /// Local JWT / mock user only — no `user()` or profile network call.
    /// Returns `true` when a session exists so launch can route before `initialize()`.
    func restoreLocalSessionForLaunch() async -> Bool {
        if AppConfig.useMockBackend {
            guard MockStore.shared.userId != nil else { return false }
            userId = MockStore.shared.ensureUser()
            profile = MockStore.shared.profile
            if let profile { ProfileLocalCache.sync(from: profile) }
            loadMockLinkedIdentities()
            return true
        }

        do {
            let session = try await client.auth.session
            userId = session.user.id
            return true
        } catch {
            return false
        }
    }

    /// Early launch hint. Unfinished onboarding → onboarding. Cache miss → main.
    var preferredLaunchRouteIsOnboarding: Bool {
        if let profile {
            return profile.onboardingCompleted != true
        }
        guard let userId else { return false }
        return ProfileLocalCache.cachedOnboardingCompleted(userId: userId) == false
    }

    func initialize() async {
        isLoading = true
        defer { isLoading = false }

        if AppConfig.useMockBackend {
            if MockStore.shared.userId != nil {
                userId = MockStore.shared.ensureUser()
                profile = MockStore.shared.profile
                if let profile { ProfileLocalCache.sync(from: profile) }
            }
            loadMockLinkedIdentities()
            await SubscriptionService.shared.identifyWithAuthUserIfNeeded()
            return
        }

        do {
            // Local JWT can outlive a wiped auth.users row — always verify with the server.
            _ = try await client.auth.session
            let user = try await client.auth.user()
            userId = user.id
            await fetchProfile()
            if profile == nil {
                // Session points at a deleted account (e.g. dashboard / SQL wipe).
                await clearInvalidLocalSession()
                return
            }
            await refreshLinkedIdentities()
            await validateAppleCredentialStateIfNeeded()
            await SubscriptionService.shared.identifyWithAuthUserIfNeeded()
        } catch {
            await clearInvalidLocalSession()
        }
    }

    /// Drops a stale keychain session so bootstrap can create a fresh anonymous user.
    private func clearInvalidLocalSession() async {
        try? await client.auth.signOut()
        userId = nil
        profile = nil
        isAppleLinked = false
        isGoogleLinked = false
        isPhoneLinked = false
        linkedPhone = nil
        pendingPhoneE164 = nil
    }

    func signInAnonymously() async throws {
        if AppConfig.useMockBackend {
            userId = MockStore.shared.ensureUser()
            profile = MockStore.shared.profile
            loadMockLinkedIdentities()
            await SubscriptionService.shared.identifyWithAuthUserIfNeeded()
            return
        }

        let session = try await client.auth.signInAnonymously()
        userId = session.user.id
        await fetchProfile()
        await refreshLinkedIdentities()
        await SubscriptionService.shared.identifyWithAuthUserIfNeeded()
    }

    func signInWithApple(idToken: String, nonce: String) async throws {
        if AppConfig.useMockBackend {
            userId = MockStore.shared.ensureUser()
            if !hasDisplayName {
                MockStore.shared.updateProfile(ProfileUpdate(displayName: "Apple User"))
            }
            profile = MockStore.shared.profile
            UserDefaults.standard.set(true, forKey: mockAppleKey)
            loadMockLinkedIdentities()
            if let profile { ProfileLocalCache.sync(from: profile) }
            LastSignedInIdentity.rememberApple(
                userID: "mock-apple",
                displayName: profile?.displayName
            )
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            return
        }

        try await connectOAuthIdentity(
            link: { try await linkApple(idToken: idToken, nonce: nonce) },
            signIn: {
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
                )
                userId = session.user.id
                await fetchProfile()
                await refreshLinkedIdentities()
                await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            }
        )
    }

    func signInWithGoogle() async throws {
        if AppConfig.useMockBackend {
            userId = MockStore.shared.ensureUser()
            if !hasDisplayName {
                MockStore.shared.updateProfile(ProfileUpdate(displayName: "Google User"))
            }
            profile = MockStore.shared.profile
            UserDefaults.standard.set(true, forKey: mockGoogleKey)
            loadMockLinkedIdentities()
            if let profile { ProfileLocalCache.sync(from: profile) }
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            return
        }

        guard AppConfig.isGoogleSignInConfigured else {
            throw AuthError.googleNotConfigured
        }

        guard let rootVC = Self.topViewController() else {
            throw AuthError.noViewController
        }

        #if canImport(GoogleSignIn)
        // Ensure config is set even if App.init ran before Secrets were readable.
        let serverID = AppConfig.googleServerClientID
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(
            clientID: AppConfig.googleClientID,
            serverClientID: serverID.isEmpty ? nil : serverID
        )

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.noIdToken
        }
        let accessToken = result.user.accessToken.tokenString

        try await connectOAuthIdentity(
            link: { try await linkGoogle(idToken: idToken, accessToken: accessToken) },
            signIn: {
                let session = try await client.auth.signInWithIdToken(
                    credentials: .init(
                        provider: .google,
                        idToken: idToken,
                        accessToken: accessToken
                    )
                )
                userId = session.user.id
                await fetchProfile()
                await refreshLinkedIdentities()
                await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            }
        )
        #else
        throw AuthError.noIdToken
        #endif
    }

    /// Topmost VC so Google Sign-In presents above sheets / onboarding covers.
    private static func topViewController(
        base: UIViewController? = nil
    ) -> UIViewController? {
        let base = base ?? UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(base: nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(base: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(base: presented)
        }
        return base
    }

    /// Prefer linking onto the current session (keeps one `profiles.id`).
    /// If there is no session yet, sign in. Link helpers already fall back to sign-in
    /// when the identity belongs to another account, then merge abandoned guest data.
    private func connectOAuthIdentity(
        link: () async throws -> Void,
        signIn: () async throws -> Void
    ) async throws {
        // Stale JWT after account wipe still looks like a "session" locally — verify user exists.
        let hasLocalSession = (try? await client.auth.session) != nil
        var sessionIsLive = false
        if hasLocalSession, profile != nil {
            sessionIsLive = (try? await client.auth.user()) != nil
        }

        if sessionIsLive {
            do {
                try await link()
                return
            } catch {
                // Dead session / user deleted mid-flight — fall through to fresh sign-in.
                guard isInvalidOrMissingUserSession(error) else { throw error }
                await clearInvalidLocalSession()
            }
        } else if hasLocalSession {
            await clearInvalidLocalSession()
        }
        try await signIn()
    }

    private func isInvalidOrMissingUserSession(_ error: Error) -> Bool {
        let text = String(describing: error).lowercased()
        return text.contains("user not found")
            || text.contains("user_not_found")
            || text.contains("session from session_not_found")
            || text.contains("session_not_found")
            || text.contains("invalid jwt")
            || text.contains("invalid_token")
            || text.contains("jwt expired")
            || text.contains("forbidden")
            || text.contains("401")
            || text.contains("403")
    }

    /// Pull phone / practice from an abandoned anonymous guest onto the signed-in account.
    private func consolidateAbandonedGuest(
        _ fromUserId: UUID,
        phone: String?
    ) async {
        await mergeAbandonedProfileIfPossible(fromUserId)

        let normalized = phone?.trimmingCharacters(in: .whitespacesAndNewlines)
        let needsPhone = {
            guard let normalized, !normalized.isEmpty else { return false }
            return profile?.phone != normalized
        }()

        if needsPhone, let normalized {
            do {
                try await client
                    .rpc(
                        "reclaim_phone_from_guest",
                        params: [
                            "p_from_user_id": fromUserId.uuidString,
                            "p_phone": normalized
                        ]
                    )
                    .execute()
            } catch {
                // Guest may already be merged or phone blocked — refresh anyway.
            }
        }

        await fetchProfile()
        await refreshLinkedIdentities()
    }

    /// Pull phone / practice from an abandoned anonymous guest onto the signed-in account.
    private func mergeAbandonedProfileIfPossible(_ fromUserId: UUID) async {
        do {
            try await client
                .rpc("merge_profile_into_current", params: ["p_from_user_id": fromUserId.uuidString])
                .execute()
        } catch {
            // SOURCE_HAS_OAUTH / missing source — leave accounts separate.
        }
    }

    func linkApple(idToken: String, nonce: String) async throws {
        if AppConfig.useMockBackend {
            if !hasDisplayName {
                MockStore.shared.updateProfile(ProfileUpdate(displayName: "Apple User"))
            }
            profile = MockStore.shared.profile
            UserDefaults.standard.set(true, forKey: mockAppleKey)
            loadMockLinkedIdentities()
            if let profile { ProfileLocalCache.sync(from: profile) }
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            return
        }

        let abandonedId = userId
        let abandonedPhone = profile?.phone ?? linkedPhone
        do {
            let session = try await client.auth.linkIdentityWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            userId = session.user.id
            await fetchProfile()
            await refreshLinkedIdentities()
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
        } catch {
            guard isIdentityAlreadyExists(error) else { throw error }
            // Apple already owns another profiles.id — switch to that account and
            // fold this phone/guest profile into it (one ID).
            let session = try await client.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            userId = session.user.id
            await fetchProfile()
            if let abandonedId, abandonedId != userId {
                await consolidateAbandonedGuest(abandonedId, phone: abandonedPhone)
            } else {
                await refreshLinkedIdentities()
            }
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
        }
    }

    func linkGoogle(idToken: String, accessToken: String? = nil) async throws {
        if AppConfig.useMockBackend {
            if !hasDisplayName {
                MockStore.shared.updateProfile(ProfileUpdate(displayName: "Google User"))
            }
            profile = MockStore.shared.profile
            UserDefaults.standard.set(true, forKey: mockGoogleKey)
            loadMockLinkedIdentities()
            if let profile { ProfileLocalCache.sync(from: profile) }
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            return
        }

        let abandonedId = userId
        let abandonedPhone = profile?.phone ?? linkedPhone
        let credentials = OpenIDConnectCredentials(
            provider: .google,
            idToken: idToken,
            accessToken: accessToken
        )
        do {
            _ = try await client.auth.linkIdentityWithIdToken(credentials: credentials)
            if let id = try? await client.auth.session.user.id {
                userId = id
            }
            await fetchProfile()
            await refreshLinkedIdentities()
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
        } catch {
            guard isIdentityAlreadyExists(error) else { throw error }
            let session = try await client.auth.signInWithIdToken(credentials: credentials)
            userId = session.user.id
            await fetchProfile()
            if let abandonedId, abandonedId != userId {
                await consolidateAbandonedGuest(abandonedId, phone: abandonedPhone)
            } else {
                await refreshLinkedIdentities()
            }
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
        }
    }

    /// Sends an SMS OTP via Firebase Phone Auth (Indian +91 / 10 digits).
    func sendPhoneOTP(digits: String) async throws {
        guard let e164 = Self.e164IndianMobile(fromDigits: digits) else {
            throw AuthError.invalidPhone
        }

        if AppConfig.useMockBackend {
            pendingPhoneE164 = e164
            return
        }

        try await FirebasePhoneAuthService.shared.sendOTP(e164: e164)
        pendingPhoneE164 = e164
    }

    /// Verifies the 6-digit SMS OTP, then stores the phone on the Supabase profile.
    func verifyPhoneOTP(code: String) async throws {
        let token = code.filter(\.isNumber)
        guard token.count == 6 else { throw AuthError.invalidOTP }

        if AppConfig.useMockBackend {
            guard let e164 = pendingPhoneE164 else { throw AuthError.otpNotSent }
            userId = MockStore.shared.ensureUser()
            MockStore.shared.updateProfile(ProfileUpdate(phone: e164))
            profile = MockStore.shared.profile
            UserDefaults.standard.set(true, forKey: mockPhoneKey)
            UserDefaults.standard.set(e164, forKey: mockPhoneNumberKey)
            loadMockLinkedIdentities()
            pendingPhoneE164 = nil
            if let profile { ProfileLocalCache.sync(from: profile) }
            await SubscriptionService.shared.refreshEntitlementsAfterLogin()
            return
        }

        let phone = try await FirebasePhoneAuthService.shared.verifyOTP(code: token)
        // Keep pendingPhoneE164 until the profile write succeeds so a DB failure
        // can retry save without forcing a new SMS (Firebase OTP is already consumed).
        pendingPhoneE164 = phone

        // Keep the existing Supabase (guest/Apple/Google) session; only persist phone.
        if userId == nil {
            try await signInAnonymously()
        }
        try await attachVerifiedPhone(phone)
        pendingPhoneE164 = nil
        linkedPhone = phone
        isPhoneLinked = true
        await SubscriptionService.shared.refreshEntitlementsAfterLogin()
    }

    /// If Firebase already accepted the OTP but the profile write failed, retry save only.
    func retryPendingPhoneProfileSaveIfNeeded() async throws -> Bool {
        guard let phone = pendingPhoneE164, phone.hasPrefix("+"),
              !FirebasePhoneAuthService.shared.hasPendingVerification
        else { return false }
        if userId == nil { try await signInAnonymously() }
        try await attachVerifiedPhone(phone)
        pendingPhoneE164 = nil
        linkedPhone = phone
        isPhoneLinked = true
        await SubscriptionService.shared.refreshEntitlementsAfterLogin()
        return true
    }

    /// Saves a Firebase-verified E.164 onto the current profile.
    /// Free numbers attach. A number that already belongs to another established
    /// account is rejected (`PHONE_ALREADY_ASSOCIATED_WITH_ANOTHER_ACCOUNT`).
    /// A fresh guest who verifies an OAuth-owned number is switched into that
    /// existing account instead of being locked out.
    private func attachVerifiedPhone(_ phone: String) async throws {
        if profile?.phone == phone || linkedPhone == phone {
            linkedPhone = phone
            isPhoneLinked = true
            return
        }

        do {
            try await client
                .rpc("claim_verified_phone", params: ["p_phone": phone])
                .execute()
            await fetchProfile()
        } catch {
            let text = (error as NSError).localizedDescription.lowercased()
            if text.contains("phone_login_switch_required")
                || text.contains("phone_owned_by_oauth_account") {
                try await switchToPhoneOwnerAccount(phone: phone)
                return
            }
            if text.contains("phone_already_associated_with_another_account")
                || text.contains("phone_already_in_use")
                || text.contains("profiles_phone_uidx")
                || text.contains("duplicate key") {
                throw AuthError.phoneAlreadyAssociatedWithAnotherAccount
            }
            throw error
        }
    }

    /// After OTP, become the account that already owns this phone (no merge).
    private func switchToPhoneOwnerAccount(phone: String) async throws {
        struct RequestBody: Encodable {
            let phone: String
        }
        struct SessionReply: Decodable {
            let hashedToken: String?
            let ownerUserId: UUID?
            let alreadyOwned: Bool?

            enum CodingKeys: String, CodingKey {
                case hashedToken = "hashed_token"
                case ownerUserId = "owner_user_id"
                case alreadyOwned = "already_owned"
            }
        }

        let reply: SessionReply
        do {
            reply = try await client.functions.invoke(
                "resolve-phone-session",
                options: .init(body: RequestBody(phone: phone))
            )
        } catch {
            if let functionsError = error as? FunctionsError,
               case .httpError(let code, let data) = functionsError {
                let body = String(data: data, encoding: .utf8)?.lowercased() ?? ""
                if code == 409 || body.contains("phone_already_associated") {
                    throw AuthError.phoneAlreadyAssociatedWithAnotherAccount
                }
            }
            let text = String(describing: error).lowercased()
            if text.contains("phone_already_associated_with_another_account") {
                throw AuthError.phoneAlreadyAssociatedWithAnotherAccount
            }
            throw AuthError.phoneLoginSwitchFailed
        }

        if reply.alreadyOwned == true {
            await fetchProfile()
            await refreshLinkedIdentities()
            return
        }
        guard let hashedToken = reply.hashedToken else {
            throw AuthError.phoneLoginSwitchFailed
        }

        let response = try await client.auth.verifyOTP(
            tokenHash: hashedToken,
            type: .magiclink
        )
        userId = response.user.id
        await fetchProfile()
        await refreshLinkedIdentities()
    }

    /// Resends OTP to the pending phone (or a new 10-digit number).
    func resendPhoneOTP(digits: String? = nil) async throws {
        if let digits {
            try await sendPhoneOTP(digits: digits)
            return
        }
        guard let e164 = pendingPhoneE164 else { throw AuthError.otpNotSent }
        let local = String(e164.filter(\.isNumber).suffix(10))
        try await sendPhoneOTP(digits: local)
    }

    func signOut() async throws {
        if AppConfig.useMockBackend {
            UserDefaults.standard.set(false, forKey: mockAppleKey)
            UserDefaults.standard.set(false, forKey: mockGoogleKey)
            UserDefaults.standard.set(false, forKey: mockPhoneKey)
            UserDefaults.standard.removeObject(forKey: mockPhoneNumberKey)
            isAppleLinked = false
            isGoogleLinked = false
            isPhoneLinked = false
            linkedPhone = nil
            ProfileLocalCache.clearLegacyUnscoped()
            userId = MockStore.shared.userId
            profile = MockStore.shared.profile
            if let profile { ProfileLocalCache.sync(from: profile) }
            return
        }

        try await client.auth.signOut()
        InviteService.shared.resetSessionState()
        userId = nil
        profile = nil
        isAppleLinked = false
        isGoogleLinked = false
        isPhoneLinked = false
        linkedPhone = nil
        pendingPhoneE164 = nil
        FirebasePhoneAuthService.shared.clearPending()
        // Drop device-global cache so the next guest doesn't inherit the previous user's fields.
        ProfileLocalCache.clearLegacyUnscoped()
    }

    /// Permanently deletes the current account and local data, then starts a fresh guest.
    func deleteAccount() async throws {
        if AppConfig.useMockBackend {
            await resetMockDataReturningToOnboarding()
            LocalAudioStore.deleteAll()
            ProfileLocalCache.clearAllAvatars()
            ProfileLocalCache.clearLegacyUnscoped()
            LastSignedInIdentity.clear()
            await SubscriptionService.shared.resetAfterAccountDeletion()
            return
        }

        // Wipe media + session rows first (best-effort) before removing auth.users.
        try? await SessionService.shared.deleteAllRecordings()
        LocalAudioStore.deleteAll()

        try await client.rpc("delete_own_account").execute()

        InviteService.shared.resetSessionState()
        userId = nil
        profile = nil
        isAppleLinked = false
        isGoogleLinked = false
        isPhoneLinked = false
        linkedPhone = nil
        UserDefaults.standard.set(false, forKey: mockAppleKey)
        UserDefaults.standard.set(false, forKey: mockGoogleKey)
        UserDefaults.standard.set(false, forKey: mockPhoneKey)
        UserDefaults.standard.removeObject(forKey: mockPhoneNumberKey)
        ProfileLocalCache.clearAllAvatars()
        ProfileLocalCache.clearLegacyUnscoped()
        LastSignedInIdentity.clear()
        SessionService.shared.sessions = []
        ChallengeService.shared.todaysChallenge = nil
        ChallengeService.shared.todaysAssignment = nil

        // Drop Pro from this device guest until they buy / restore / link again.
        await SubscriptionService.shared.resetAfterAccountDeletion()

        // User is already gone — signOut may no-op / fail; clear local session anyway.
        try? await client.auth.signOut()
        try await signInAnonymously()
    }

    func refreshLinkedIdentities() async {
        if AppConfig.useMockBackend {
            loadMockLinkedIdentities()
            return
        }

        do {
            let identities = try await client.auth.userIdentities()
            let providers = Set(identities.map { $0.provider.lowercased() })
            isAppleLinked = providers.contains("apple")
            isGoogleLinked = providers.contains("google")
        } catch {
            if let identities = try? await client.auth.session.user.identities {
                let providers = Set(identities.map { $0.provider.lowercased() })
                isAppleLinked = providers.contains("apple")
                isGoogleLinked = providers.contains("google")
            } else {
                isAppleLinked = false
                isGoogleLinked = false
            }
        }

        // Phone is verified via Firebase and stored on profiles — not a Supabase auth identity.
        if let phone = profile?.phone, !phone.isEmpty {
            linkedPhone = phone
            isPhoneLinked = true
        } else {
            linkedPhone = nil
            isPhoneLinked = false
        }
    }

    private func loadMockLinkedIdentities() {
        isAppleLinked = UserDefaults.standard.bool(forKey: mockAppleKey)
        isGoogleLinked = UserDefaults.standard.bool(forKey: mockGoogleKey)
        isPhoneLinked = UserDefaults.standard.bool(forKey: mockPhoneKey)
        linkedPhone = UserDefaults.standard.string(forKey: mockPhoneNumberKey)
        if linkedPhone == nil || linkedPhone?.isEmpty == true {
            isPhoneLinked = false
        }
    }

    func fetchProfile() async {
        if AppConfig.useMockBackend {
            profile = MockStore.shared.profile
            if let profile {
                ProfileLocalCache.sync(from: profile)
                SubscriptionService.shared.applyReferralGrants(from: profile)
            }
            return
        }

        guard let userId else { return }
        do {
            profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userId)
                .single()
                .execute()
                .value
            if let profile {
                ProfileLocalCache.sync(from: profile)
                SubscriptionService.shared.applyReferralGrants(from: profile)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateProfile(_ update: ProfileUpdate) async throws {
        if AppConfig.useMockBackend {
            MockStore.shared.updateProfile(update)
            profile = MockStore.shared.profile
            if let profile { ProfileLocalCache.sync(from: profile) }
            return
        }

        guard let userId else { return }
        try await client
            .from("profiles")
            .update(update)
            .eq("id", value: userId)
            .execute()
        await fetchProfile()
    }

    /// Uploads a JPEG avatar to `avatars/{userId}/avatar.jpg` and saves `avatar_url` on the profile.
    @discardableResult
    func uploadAvatar(_ image: UIImage) async throws -> String {
        guard let userId else { throw AuthError.notSignedIn }

        let maxDimension: CGFloat = 1024
        let rendered = image.resizedForAvatar(maxDimension: maxDimension)
        guard let data = rendered.jpegData(compressionQuality: 0.82) else {
            throw AuthError.avatarEncodeFailed
        }

        if AppConfig.useMockBackend {
            let url = "mock://avatar/\(userId.uuidString)"
            MockStore.shared.updateProfile(ProfileUpdate(avatarUrl: url))
            profile = MockStore.shared.profile
            ProfileLocalCache.storeAvatarJPEG(data, userId: userId)
            LastSignedInIdentity.rememberProfileSnapshot()
            return url
        }

        let path = "\(userId.uuidString.lowercased())/avatar.jpg"
        try await client.storage
            .from("avatars")
            .upload(path, data: data, options: .init(contentType: "image/jpeg", upsert: true))

        let publicURL = try client.storage.from("avatars").getPublicURL(path: path)
        // Cache-bust so UI refreshes after replace.
        let stamped = publicURL.absoluteString + "?t=\(Int(Date().timeIntervalSince1970))"
        try await updateProfile(ProfileUpdate(avatarUrl: stamped))
        ProfileLocalCache.storeAvatarJPEG(data, userId: userId)
        LastSignedInIdentity.rememberProfileSnapshot()
        return stamped
    }

    var isAuthenticated: Bool { userId != nil }
    var needsOnboarding: Bool { profile?.onboardingCompleted != true }

    /// Applies Apple's given/family name only when the profile has no display name yet.
    func applyAppleDisplayNameIfNeeded(_ fullName: PersonNameComponents?) async {
        guard let name = AppleSignInSupport.displayName(from: fullName), !hasDisplayName else { return }
        try? await updateProfile(ProfileUpdate(displayName: name))
    }

    /// Apple HIG: if the user revoked Sign in with Apple for this app, clear the session.
    func validateAppleCredentialStateIfNeeded() async {
        guard isAppleLinked, !AppConfig.useMockBackend else { return }
        guard let appleUserID = await appleIdentityUserID() else { return }

        let state: ASAuthorizationAppleIDProvider.CredentialState = await withCheckedContinuation { cont in
            ASAuthorizationAppleIDProvider().getCredentialState(forUserID: appleUserID) { state, _ in
                cont.resume(returning: state)
            }
        }

        if state == .revoked || state == .notFound {
            try? await signOut()
            try? await signInAnonymously()
            await refreshLinkedIdentities()
        }
    }

    private var hasDisplayName: Bool {
        Self.isRealDisplayName(profile?.displayName)
    }

    /// True when the stored name is a real user-chosen (or provider) name — not empty / "Speaker".
    static func isRealDisplayName(_ raw: String?) -> Bool {
        let name = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return false }
        return name.caseInsensitiveCompare("Speaker") != .orderedSame
    }

    /// Prefer a real profile name; never treat the UI placeholder as source of truth.
    static func preferredDisplayName(_ candidates: String?...) -> String? {
        for candidate in candidates {
            if isRealDisplayName(candidate) {
                return candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return nil
    }

    private func isIdentityAlreadyExists(_ error: Error) -> Bool {
        if let authError = error as? Supabase.AuthError {
            return authError.errorCode == .identityAlreadyExists
        }
        let text = String(describing: error).lowercased()
        return text.contains("identity_already_exists") || text.contains("already been linked")
    }

    private func appleIdentityUserID() async -> String? {
        if let identities = try? await client.auth.userIdentities() {
            return identities.first { $0.provider.lowercased() == "apple" }?.id
        }
        if let identities = try? await client.auth.session.user.identities {
            return identities.first { $0.provider.lowercased() == "apple" }?.id
        }
        return nil
    }

    /// Clears mock store and recreates a fresh guest who still needs onboarding.
    func resetMockDataReturningToOnboarding() async {
        guard AppConfig.useMockBackend else { return }

        MockStore.shared.resetAll()
        ChallengeService.shared.todaysChallenge = nil
        ChallengeService.shared.todaysAssignment = nil
        SessionService.shared.sessions = []

        UserDefaults.standard.set(false, forKey: mockAppleKey)
        UserDefaults.standard.set(false, forKey: mockGoogleKey)
        UserDefaults.standard.set(false, forKey: mockPhoneKey)
        UserDefaults.standard.removeObject(forKey: mockPhoneNumberKey)
        isAppleLinked = false
        isGoogleLinked = false
        isPhoneLinked = false
        linkedPhone = nil

        userId = nil
        // Force observers to see a change even if the next profile also starts incomplete.
        profile = nil

        userId = MockStore.shared.ensureUser()
        profile = MockStore.shared.profile
    }

    /// Switch mock ↔ supabase and re-bootstrap auth/session state.
    func switchBackend(to mode: BackendMode) async {
        guard mode != AppConfig.backendMode else { return }

        AppConfig.setBackendMode(mode, notify: false)
        SupabaseManager.shared.resetClient()

        ChallengeService.shared.todaysChallenge = nil
        ChallengeService.shared.todaysAssignment = nil
        SessionService.shared.sessions = []
        userId = nil
        profile = nil
        errorMessage = nil
        isAppleLinked = false
        isGoogleLinked = false
        isPhoneLinked = false
        linkedPhone = nil
        pendingPhoneE164 = nil

        await initialize()

        if !isAuthenticated {
            do {
                try await signInAnonymously()
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        NotificationCenter.default.post(name: .backendModeDidChange, object: mode)
    }
}

enum AuthError: LocalizedError {
    case noViewController
    case noIdToken
    case notSignedIn
    case avatarEncodeFailed
    case invalidPhone
    case invalidOTP
    case otpNotSent
    case firebaseNotConfigured
    case googleNotConfigured
    case phoneAlreadyInUse
    case phoneOwnedByOAuthAccount
    case phoneAlreadyAssociatedWithAnotherAccount
    case phoneLoginSwitchFailed

    var errorDescription: String? {
        switch self {
        case .noViewController: return "Could not find view controller"
        case .noIdToken: return "Could not get ID token from the provider"
        case .notSignedIn: return "You need to be signed in"
        case .avatarEncodeFailed: return "Could not prepare that photo"
        case .invalidPhone: return "Enter a valid 10-digit mobile number"
        case .invalidOTP: return "Enter the 6-digit code from your SMS"
        case .otpNotSent: return "Request a code first"
        case .firebaseNotConfigured:
            return "Add GoogleService-Info.plist and enable Phone in Firebase Auth"
        case .googleNotConfigured:
            return "Add GOOGLE_CLIENT_ID to Secrets.plist and enable Google in Supabase Auth"
        case .phoneAlreadyInUse, .phoneAlreadyAssociatedWithAnotherAccount, .phoneOwnedByOAuthAccount:
            return "This number is already associated with another account. Sign in with that account to continue."
        case .phoneLoginSwitchFailed:
            return "We verified this number. Sign in with the Apple or Google account that already uses it."
        }
    }
}
