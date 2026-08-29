import Foundation

enum BackendMode: String, CaseIterable, Identifiable {
    /// Local mock — no Supabase or OpenAI keys required
    case mock
    /// Live Supabase + OpenAI edge function
    case supabase

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .mock: return "Mock"
        case .supabase: return "Supabase"
        }
    }
}

enum AppConfig {
    /// Secrets.plist default when no runtime override is set.
    private static let defaultMode: BackendMode = .mock
    private static let backendOverrideKey = "app.backendMode.override"

    private static let secrets: [String: Any] = {
        guard let url = Bundle.main.url(forResource: "Secrets", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else {
            return [:]
        }
        return dict
    }()

    /// Runtime override (Settings) wins, then Secrets.plist, then default.
    /// Overrides are DEBUG-only so TestFlight / App Store never inherit a mock switch.
    static var backendMode: BackendMode {
        #if DEBUG
        if let raw = UserDefaults.standard.string(forKey: backendOverrideKey),
           let mode = BackendMode(rawValue: raw.lowercased()) {
            return mode
        }
        #endif
        if let raw = secrets["BACKEND_MODE"] as? String,
           let mode = BackendMode(rawValue: raw.lowercased()) {
            return mode
        }
        return defaultMode
    }

    static func setBackendMode(_ mode: BackendMode, notify: Bool = true) {
        #if DEBUG
        UserDefaults.standard.set(mode.rawValue, forKey: backendOverrideKey)
        if notify {
            NotificationCenter.default.post(name: .backendModeDidChange, object: mode)
        }
        #endif
    }

    static var useMockBackend: Bool { backendMode == .mock }

    static var supabaseURL: URL {
        guard let urlString = secrets["SUPABASE_URL"] as? String,
              let url = URL(string: urlString) else {
            return URL(string: "https://placeholder.supabase.co")!
        }
        return url
    }

    static var supabaseAnonKey: String {
        secrets["SUPABASE_ANON_KEY"] as? String ?? ""
    }

    static var googleClientID: String {
        secrets["GOOGLE_CLIENT_ID"] as? String ?? ""
    }

    /// Web OAuth client ID (optional). When set, used as `serverClientID` so the
    /// Google ID token `aud` matches what Supabase expects for native sign-in.
    static var googleServerClientID: String {
        let value = secrets["GOOGLE_SERVER_CLIENT_ID"] as? String ?? ""
        guard !value.isEmpty, !value.contains("your-google") else { return "" }
        return value
    }

    static var isGoogleSignInConfigured: Bool {
        let id = googleClientID
        return !id.isEmpty && !id.contains("your-google") && id.contains(".apps.googleusercontent.com")
    }

    /// RevenueCat public SDK key.
    /// Debug → test key (Test Store). Release / TestFlight → App Store (`appl_`) key.
    static var revenueCatAPIKey: String {
        #if DEBUG
        let test = secrets["REVENUECAT_API_KEY_TEST"] as? String ?? ""
        if isUsableRevenueCatKey(test) { return test }
        #endif
        return secrets["REVENUECAT_API_KEY"] as? String ?? ""
    }

    static var isRevenueCatConfigured: Bool {
        isUsableRevenueCatKey(revenueCatAPIKey)
    }

    private static func isUsableRevenueCatKey(_ key: String) -> Bool {
        !key.isEmpty
            && !key.contains("your-revenuecat")
            && (key.hasPrefix("appl_") || key.hasPrefix("test_"))
    }

    /// Entitlement identifier configured in RevenueCat dashboard.
    static let proEntitlementID = "oracy_pro"

    /// Completed analyses allowed per calendar week without Pro.
    static let freeWeeklySessionLimit = 3

    /// True when supabase mode has real credentials (not placeholders).
    static var isSupabaseConfigured: Bool {
        guard let urlString = secrets["SUPABASE_URL"] as? String,
              let key = secrets["SUPABASE_ANON_KEY"] as? String else { return false }
        return !urlString.contains("your-project") && !key.isEmpty && !key.contains("your-anon")
    }

    static var isConfigured: Bool {
        useMockBackend || isSupabaseConfigured
    }
}

extension Notification.Name {
    static let backendModeDidChange = Notification.Name("oracy.backendModeDidChange")
}
