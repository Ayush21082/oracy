import Foundation
import Supabase

/// Lazily creates the Supabase client only when server mode is active.
final class SupabaseManager {
    static let shared = SupabaseManager()

    private var _client: SupabaseClient?
    private let lock = NSLock()

    var client: SupabaseClient {
        lock.lock()
        defer { lock.unlock() }
        if let _client { return _client }
        precondition(
            !AppConfig.useMockBackend,
            "Supabase client should not be accessed in mock mode"
        )
        let created = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey
        )
        _client = created
        return created
    }

    /// Drop the cached client after a backend mode switch.
    func resetClient() {
        lock.lock()
        _client = nil
        lock.unlock()
    }

    private init() {}
}
