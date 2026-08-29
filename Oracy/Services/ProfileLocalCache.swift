import Foundation
import UIKit

/// Device cache for profile onboarding fields, scoped per auth user id.
/// Source of truth is Supabase `profiles`; this avoids cross-user bleed on shared devices.
enum ProfileLocalCache {
    private static let defaults = UserDefaults.standard

    private static func key(_ suffix: String, userId: UUID) -> String {
        "profile.\(userId.uuidString).\(suffix)"
    }

    private static var avatarDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Oracy/Avatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func sync(from profile: Profile) {
        let id = profile.id
        defaults.set(profile.age.map(String.init) ?? "", forKey: key("age", userId: id))
        defaults.set(profile.priorities.sorted().joined(separator: ","), forKey: key("priorities", userId: id))
        let occupation = profile.personality.compactMap { raw in
            OnboardingPersonalityTag(rawValue: raw)?.displayName
        }.sorted().joined(separator: ", ")
        defaults.set(occupation, forKey: key("occupation", userId: id))
        defaults.set(profile.onboardingCompleted, forKey: key("onboardingCompleted", userId: id))

        // Legacy unscoped keys (pre user-scoped) — keep in sync for current user only.
        defaults.set(profile.age.map(String.init) ?? "", forKey: "profile.age")
        defaults.set(profile.priorities.sorted().joined(separator: ","), forKey: "profile.priorities")
        defaults.set(occupation, forKey: "profile.occupation")
    }

    static func storeAvatarJPEG(_ data: Data, userId: UUID) {
        let url = avatarDirectory.appendingPathComponent("\(userId.uuidString).jpg")
        try? data.write(to: url, options: .atomic)
    }

    static func loadAvatarImage(userId: UUID) -> UIImage? {
        decodeAvatar(at: avatarDirectory.appendingPathComponent("\(userId.uuidString).jpg"))
    }

    private static func decodeAvatar(at url: URL) -> UIImage? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let image = UIImage(data: data) else { return nil }
        // Decode once at a display-friendly size — full JPEGs stall pull-to-stretch.
        return image.resizedForAvatar(maxDimension: 320)
    }

    static func clearAvatar(userId: UUID) {
        let url = avatarDirectory.appendingPathComponent("\(userId.uuidString).jpg")
        try? FileManager.default.removeItem(at: url)
    }

    /// Wipe every cached JPEG — used on account delete so the next guest never inherits a face.
    static func clearAllAvatars() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: avatarDirectory,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// `nil` when this user has never been cached on device.
    static func cachedOnboardingCompleted(userId: UUID) -> Bool? {
        let k = key("onboardingCompleted", userId: userId)
        guard defaults.object(forKey: k) != nil else { return nil }
        return defaults.bool(forKey: k)
    }

    static func clearLegacyUnscoped() {
        defaults.removeObject(forKey: "profile.age")
        defaults.removeObject(forKey: "profile.priorities")
        defaults.removeObject(forKey: "profile.occupation")
    }
}

extension UIImage {
    func resizedForAvatar(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
