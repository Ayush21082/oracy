import Foundation
import UIKit

/// Device hint for a previously signed-in person — drives the returning-user auth CTA.
@MainActor
enum LastSignedInIdentity {
    private static let defaults = UserDefaults.standard
    private static let nameKey = "auth.last.displayName"
    private static let providerKey = "auth.last.provider"
    private static let appleUserKey = "auth.last.appleUserID"
    private static let oracyUserKey = "auth.last.oracyUserID"
    private static let avatarURLKey = "auth.last.avatarURL"

    static var displayName: String? {
        AuthService.preferredDisplayName(defaults.string(forKey: nameKey))
    }

    static var provider: String? {
        defaults.string(forKey: providerKey)
    }

    static var appleUserID: String? {
        defaults.string(forKey: appleUserKey)
    }

    static var oracyUserID: UUID? {
        guard let raw = defaults.string(forKey: oracyUserKey) else { return nil }
        return UUID(uuidString: raw)
    }

    static var remoteAvatarURL: URL? {
        guard let raw = defaults.string(forKey: avatarURLKey),
              let url = URL(string: raw),
              url.scheme == "http" || url.scheme == "https"
        else { return nil }
        return url
    }

    /// Photo for the returning Apple CTA — only the last remembered user, never a leftover file.
    static var cachedAvatarImage: UIImage? {
        guard let id = oracyUserID else { return nil }
        return ProfileLocalCache.loadAvatarImage(userId: id)
    }

    /// True when we've seen Apple sign-in on this device before.
    static var hasReturningAppleUser: Bool {
        provider == "apple" && (displayName != nil || appleUserID != nil)
    }

    static func updateDisplayNameIfNeeded(_ name: String?) {
        guard let name, AuthService.isRealDisplayName(name) else { return }
        defaults.set(name.trimmingCharacters(in: .whitespacesAndNewlines), forKey: nameKey)
    }

    static func rememberApple(userID: String, displayName: String?) {
        defaults.set("apple", forKey: providerKey)
        defaults.set(userID, forKey: appleUserKey)
        updateDisplayNameIfNeeded(displayName)
        rememberProfileSnapshot()
    }

    static func rememberGoogle(displayName: String?) {
        defaults.set("google", forKey: providerKey)
        updateDisplayNameIfNeeded(displayName)
        rememberProfileSnapshot()
    }

    static func rememberProfileSnapshot() {
        if let id = AuthService.shared.userId {
            defaults.set(id.uuidString, forKey: oracyUserKey)
        }
        if let url = AuthService.shared.profile?.avatarUrl, !url.isEmpty {
            defaults.set(url, forKey: avatarURLKey)
        } else {
            defaults.removeObject(forKey: avatarURLKey)
        }
    }

    static func clear() {
        defaults.removeObject(forKey: nameKey)
        defaults.removeObject(forKey: providerKey)
        defaults.removeObject(forKey: appleUserKey)
        defaults.removeObject(forKey: oracyUserKey)
        defaults.removeObject(forKey: avatarURLKey)
    }
}
