import Foundation
import UIKit
import UserNotifications
import FirebaseCore
import FirebaseAuth

/// Boots Firebase for phone OTP only. Supabase remains the app session source of truth.
enum FirebaseBootstrap {
    private static let lock = NSLock()
    private(set) static var isConfigured = false
    private static let verificationIDKey = "firebase.authVerificationID"
    private static let pendingPhoneKey = "firebase.pendingPhoneE164"
    private static var pendingAPNSToken: Data?

    /// Call only from `AppDelegate.application(_:didFinishLaunchingWithOptions:)`.
    /// Configuring earlier (e.g. SwiftUI `App.init`) leaves Auth phone managers nil forever.
    static func configure() {
        lock.lock()
        defer { lock.unlock() }

        if FirebaseApp.app() != nil {
            isConfigured = true
            return
        }

        // Standard Firebase setup — loads GoogleService-Info.plist from the app bundle.
        let plistPath = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist")
        guard plistPath != nil else {
            assertionFailure(
                "GoogleService-Info.plist is not in the app bundle. Select the file in Xcode → File Inspector → ensure Target Membership includes Oracy."
            )
            return
        }

        FirebaseApp.configure()
        isConfigured = FirebaseApp.app() != nil
        // Touch Auth while UIApplication exists so always-eager Auth can init phone managers.
        if isConfigured {
            _ = Auth.auth()
        }

        // Auth phone managers are assigned on Firebase's auth work queue asynchronously.
        schedulePhoneAuthReadyProbe()
    }

    /// Safe Auth instance for the default app — nil if Firebase isn’t ready.
    /// Does not configure; callers must ensure `configure()` already ran in AppDelegate.
    static var auth: Auth? {
        guard isConfigured, let app = FirebaseApp.app() else { return nil }
        return Auth.auth(app: app)
    }

    /// Whether Auth's internal phone-auth managers finished initializing (Mirror; no IUO crash).
    static func phoneAuthReady(_ auth: Auth) -> Bool {
        for child in Mirror(reflecting: auth).children {
            if child.label == "notificationManager" {
                return String(describing: child.value) != "nil"
            }
        }
        return false
    }

    static func storeAPNSToken(_ token: Data) {
        pendingAPNSToken = token
        applyPendingAPNSTokenIfReady()
    }

    @discardableResult
    static func applyPendingAPNSTokenIfReady() -> Bool {
        guard let token = pendingAPNSToken, let auth = auth, phoneAuthReady(auth) else {
            return false
        }
        auth.setAPNSToken(token, type: .unknown)
        return true
    }

    private static func schedulePhoneAuthReadyProbe() {
        // Retry briefly until Auth's async protectedDataInitialization finishes.
        for delayMs in [50, 150, 400, 1000] as [Int] {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delayMs)) {
                guard let auth = auth, phoneAuthReady(auth) else { return }
                _ = applyPendingAPNSTokenIfReady()
            }
        }
    }

    /// Handles a Firebase / reCAPTCHA redirect URL. Safe when Firebase isn’t configured.
    @discardableResult
    static func handleOpenURL(_ url: URL) -> Bool {
        guard let auth = auth, phoneAuthReady(auth) else { return false }
        return auth.canHandle(url)
    }

    /// Forward silent APNs / prober notifications to Auth. Safe when managers aren’t ready.
    @discardableResult
    static func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard let auth = auth, phoneAuthReady(auth) else { return false }
        return auth.canHandleNotification(userInfo)
    }

    static func storePendingVerification(id: String, phone: String) {
        UserDefaults.standard.set(id, forKey: verificationIDKey)
        UserDefaults.standard.set(phone, forKey: pendingPhoneKey)
    }

    static func loadPendingVerification() -> (id: String, phone: String)? {
        guard let id = UserDefaults.standard.string(forKey: verificationIDKey), !id.isEmpty,
              let phone = UserDefaults.standard.string(forKey: pendingPhoneKey), !phone.isEmpty
        else { return nil }
        return (id, phone)
    }

    static func clearPendingVerification() {
        UserDefaults.standard.removeObject(forKey: verificationIDKey)
        UserDefaults.standard.removeObject(forKey: pendingPhoneKey)
    }
}

/// Configure Firebase in AppDelegate launch, then register for remote notifications.
final class OracyAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        FirebaseBootstrap.configure()
        UNUserNotificationCenter.current().delegate = self
        if FirebaseBootstrap.isConfigured {
            application.registerForRemoteNotifications()
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        // Stash + apply when Auth phone managers are ready (avoids IUO crash).
        FirebaseBootstrap.storeAPNSToken(deviceToken)
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        // Manual forward required for SwiftUI AppDelegateAdaptor + phone auth probe.
        _ = FirebaseBootstrap.handleRemoteNotification(userInfo)
        completionHandler(.noData)
    }

    func application(
        _ app: UIApplication,
        open url: URL,
        options: [UIApplication.OpenURLOptionsKey: Any] = [:]
    ) -> Bool {
        FirebaseBootstrap.handleOpenURL(url)
    }
}

/// Firebase Phone Auth wrapper. Verifies SMS, then callers persist phone onto the Supabase profile.
@MainActor
final class FirebasePhoneAuthService {
    static let shared = FirebasePhoneAuthService()

    private var verificationID: String?
    private var pendingE164: String?

    private init() {
        if let pending = FirebaseBootstrap.loadPendingVerification() {
            verificationID = pending.id
            pendingE164 = pending.phone
        }
    }

    var hasPendingVerification: Bool { verificationID != nil && pendingE164 != nil }

    func sendOTP(e164: String) async throws {
        guard let auth = FirebaseBootstrap.auth else {
            throw AuthError.firebaseNotConfigured
        }

        _ = FirebaseBootstrap.applyPendingAPNSTokenIfReady()

        let id: String = try await withCheckedThrowingContinuation { cont in
            PhoneAuthProvider.provider(auth: auth).verifyPhoneNumber(e164, uiDelegate: nil) { verificationID, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                guard let verificationID else {
                    cont.resume(throwing: AuthError.otpNotSent)
                    return
                }
                cont.resume(returning: verificationID)
            }
        }
        verificationID = id
        pendingE164 = e164
        FirebaseBootstrap.storePendingVerification(id: id, phone: e164)
    }

    /// Verifies the SMS code. Returns the confirmed E.164 phone, then signs out of Firebase
    /// so Supabase stays the only long-lived session.
    @discardableResult
    func verifyOTP(code: String) async throws -> String {
        let token = code.filter(\.isNumber)
        guard token.count == 6 else { throw AuthError.invalidOTP }

        let storedID = verificationID ?? FirebaseBootstrap.loadPendingVerification()?.id
        let storedPhone = pendingE164 ?? FirebaseBootstrap.loadPendingVerification()?.phone
        guard let verificationID = storedID, let pendingE164 = storedPhone else {
            throw AuthError.otpNotSent
        }
        guard let auth = FirebaseBootstrap.auth else {
            throw AuthError.firebaseNotConfigured
        }

        let credential = PhoneAuthProvider.provider(auth: auth).credential(
            withVerificationID: verificationID,
            verificationCode: token
        )
        _ = try await auth.signIn(with: credential)
        let phone = auth.currentUser?.phoneNumber ?? pendingE164
        try? auth.signOut()
        self.verificationID = nil
        self.pendingE164 = nil
        FirebaseBootstrap.clearPendingVerification()
        return phone
    }

    func clearPending() {
        verificationID = nil
        pendingE164 = nil
        FirebaseBootstrap.clearPendingVerification()
    }
}
