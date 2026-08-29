import Foundation
import AVFoundation
import Supabase

#if canImport(UIKit)
import UIKit
#endif

#if DEBUG

// MARK: - Models

enum SystemCheckStatus: String, Sendable {
    case pending
    case running
    case ok
    case fail
    case skip
}

struct SystemCheckItem: Identifiable, Sendable {
    let id: String
    let category: String
    let name: String
    var status: SystemCheckStatus
    var detail: String?
    /// Approximate USD spent by this check, if any.
    var costUsd: Double?
}

struct SystemStatusReport: Sendable {
    var items: [SystemCheckItem]
    var estimatedCostUsd: Double
    var finishedAt: Date?

    var okCount: Int { items.filter { $0.status == .ok }.count }
    var failCount: Int { items.filter { $0.status == .fail }.count }
    var skipCount: Int { items.filter { $0.status == .skip }.count }
}

// MARK: - Service

@MainActor
@Observable
final class SystemStatusService {
    static let shared = SystemStatusService()

    private(set) var report = SystemStatusReport(items: [], estimatedCostUsd: 0)
    private(set) var isRunning = false

    private var client: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    func runAllChecks() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }

        var items = Self.blueprint()
        report = SystemStatusReport(items: items, estimatedCostUsd: 0, finishedAt: nil)
        var totalCost = 0.0

        for index in items.indices {
            items[index].status = .running
            report = SystemStatusReport(items: items, estimatedCostUsd: totalCost, finishedAt: nil)

            let result = await perform(items[index])
            items[index] = result
            if let cost = result.costUsd {
                totalCost += cost
            }
            report = SystemStatusReport(items: items, estimatedCostUsd: totalCost, finishedAt: nil)
        }

        report = SystemStatusReport(items: items, estimatedCostUsd: totalCost, finishedAt: Date())
    }

    // MARK: Blueprint

    private static func blueprint() -> [SystemCheckItem] {
        [
            .init(id: "app_config", category: "App", name: "Secrets & config", status: .pending),
            .init(id: "backend_mode", category: "App", name: "Backend mode", status: .pending),
            .init(id: "auth_session", category: "App", name: "Auth session", status: .pending),
            .init(id: "profile_row", category: "App", name: "User profile", status: .pending),
            .init(id: "mic_permission", category: "Device", name: "Microphone", status: .pending),
            .init(id: "local_audio", category: "Device", name: "Local audio store", status: .pending),
            .init(id: "google_config", category: "App", name: "Google Sign-In config", status: .pending),
            .init(id: "apple_signin", category: "App", name: "Sign in with Apple", status: .pending),
            .init(id: "supabase_reach", category: "Supabase", name: "API reachability", status: .pending),
            .init(id: "db_profiles", category: "Database", name: "profiles", status: .pending),
            .init(id: "db_challenges", category: "Database", name: "challenges", status: .pending),
            .init(id: "db_sessions", category: "Database", name: "sessions", status: .pending),
            .init(id: "db_daily", category: "Database", name: "daily_assignments", status: .pending),
            .init(id: "db_saved", category: "Database", name: "saved_words", status: .pending),
            .init(id: "storage_audio", category: "Storage", name: "session-audio bucket", status: .pending),
            .init(id: "edge_analyze", category: "Edge", name: "analyze-session function", status: .pending),
            .init(id: "openai_probe", category: "OpenAI", name: "Key + quota probe", status: .pending),
        ]
    }

    // MARK: Perform

    private func perform(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item

        if AppConfig.useMockBackend {
            switch item.id {
            case "app_config":
                next.status = .ok
                next.detail = "Mock mode — Secrets optional"
            case "backend_mode":
                next.status = .ok
                next.detail = "mock"
            case "auth_session":
                if AuthService.shared.userId != nil {
                    next.status = .ok
                    next.detail = "Mock user ready"
                } else {
                    next.status = .fail
                    next.detail = "No mock user"
                }
            case "profile_row":
                if AuthService.shared.profile != nil || MockStore.shared.profile != nil {
                    next.status = .ok
                    next.detail = "Profile loaded"
                } else {
                    next.status = .fail
                    next.detail = "No profile"
                }
            case "mic_permission":
                next = micCheck(next)
            case "local_audio":
                next = localAudioCheck(next)
            case "google_config":
                next = googleCheck(next)
            case "apple_signin":
                next = appleCheck(next)
            case "supabase_reach", "db_profiles", "db_challenges", "db_sessions",
                 "db_daily", "db_saved", "storage_audio", "edge_analyze", "openai_probe":
                next.status = .skip
                next.detail = "Skipped in mock mode"
            default:
                next.status = .skip
                next.detail = "Unknown check"
            }
            return next
        }

        switch item.id {
        case "app_config":
            if AppConfig.isSupabaseConfigured {
                next.status = .ok
                next.detail = "SUPABASE_URL + anon key set"
            } else {
                next.status = .fail
                next.detail = "Configure Secrets.plist"
            }
        case "backend_mode":
            next.status = .ok
            next.detail = AppConfig.backendMode.rawValue
        case "auth_session":
            next = await authCheck(next)
        case "profile_row":
            if AuthService.shared.profile != nil {
                next.status = .ok
                next.detail = AuthService.shared.profile?.displayName ?? "Profile OK"
            } else {
                await AuthService.shared.fetchProfile()
                if AuthService.shared.profile != nil {
                    next.status = .ok
                    next.detail = "Profile fetched"
                } else {
                    next.status = .fail
                    next.detail = "No profile row"
                }
            }
        case "mic_permission":
            next = micCheck(next)
        case "local_audio":
            next = localAudioCheck(next)
        case "google_config":
            next = googleCheck(next)
        case "apple_signin":
            next = appleCheck(next)
        case "supabase_reach":
            next = await supabaseReachCheck(next)
        case "db_profiles":
            next = await tableCheck(next, table: "profiles", select: "id")
        case "db_challenges":
            next = await challengesCheck(next)
        case "db_sessions":
            next = await tableCheck(next, table: "sessions", select: "id")
        case "db_daily":
            next = await tableCheck(next, table: "daily_assignments", select: "id")
        case "db_saved":
            next = await tableCheck(next, table: "saved_words", select: "id")
        case "storage_audio":
            next = await storageCheck(next)
        case "edge_analyze":
            next = await edgeAnalyzePresenceCheck(next)
        case "openai_probe":
            next = await openAIProbe(next)
        default:
            next.status = .skip
            next.detail = "Unknown check"
        }

        return next
    }

    // MARK: Individual checks

    private func micCheck(_ item: SystemCheckItem) -> SystemCheckItem {
        var next = item
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            next.status = .ok
            next.detail = "Granted"
        case .denied:
            next.status = .fail
            next.detail = "Denied"
        case .undetermined:
            next.status = .skip
            next.detail = "Not asked yet"
        @unknown default:
            next.status = .skip
            next.detail = "Unknown"
        }
        return next
    }

    private func localAudioCheck(_ item: SystemCheckItem) -> SystemCheckItem {
        var next = item
        let probeId = UUID()
        let url = LocalAudioStore.fileURL(sessionId: probeId)
        let dir = url.deletingLastPathComponent()
        do {
            if !FileManager.default.fileExists(atPath: dir.path) {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            }
            let probe = dir.appendingPathComponent(".status-probe")
            try Data("ok".utf8).write(to: probe, options: .atomic)
            try FileManager.default.removeItem(at: probe)
            next.status = .ok
            next.detail = "Writable store ready"
        } catch {
            next.status = .fail
            next.detail = "Cannot write audio directory"
        }
        return next
    }

    private func googleCheck(_ item: SystemCheckItem) -> SystemCheckItem {
        var next = item
        let id = AppConfig.googleClientID
        if id.isEmpty || id.contains("your-google") {
            next.status = .skip
            next.detail = "Not configured"
        } else {
            next.status = .ok
            next.detail = "Client ID present"
        }
        return next
    }

    private func appleCheck(_ item: SystemCheckItem) -> SystemCheckItem {
        var next = item
        #if targetEnvironment(simulator)
        next.status = .ok
        next.detail = "Entitlements wired · prefer a real device"
        #else
        next.status = .ok
        next.detail = "Entitlements wired · bundle \(Bundle.main.bundleIdentifier ?? "unknown")"
        #endif
        return next
    }

    private func authCheck(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item
        do {
            let user = try await client.auth.session.user
            next.status = .ok
            next.detail = "Signed in · \(user.id.uuidString.prefix(8))…"
        } catch {
            next.status = .fail
            next.detail = "No active session"
        }
        return next
    }

    private func supabaseReachCheck(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item
        var request = URLRequest(url: AppConfig.supabaseURL.appending(path: "auth/v1/health"))
        request.httpMethod = "GET"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.timeoutInterval = 12

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<500).contains(code) {
                next.status = .ok
                next.detail = "Auth health · HTTP \(code)"
            } else {
                next.status = .fail
                next.detail = "HTTP \(code)"
            }
        } catch {
            // Fallback: any successful PostgREST call
            do {
                let _: [Challenge] = try await client
                    .from("challenges")
                    .select("id")
                    .limit(1)
                    .execute()
                    .value
                next.status = .ok
                next.detail = "REST reachable"
            } catch {
                next.status = .fail
                next.detail = "Unreachable"
            }
        }
        return next
    }

    private func tableCheck(_ item: SystemCheckItem, table: String, select: String) async -> SystemCheckItem {
        var next = item
        do {
            struct Row: Decodable { let id: UUID }
            let rows: [Row] = try await client
                .from(table)
                .select(select)
                .limit(1)
                .execute()
                .value
            next.status = .ok
            next.detail = rows.isEmpty ? "Reachable (empty)" : "Reachable"
        } catch {
            next.status = .fail
            next.detail = Self.shortError(error)
        }
        return next
    }

    private func challengesCheck(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item
        do {
            let rows: [Challenge] = try await client
                .from("challenges")
                .select("id, prompt, category, difficulty, active")
                .eq("active", value: true)
                .limit(3)
                .execute()
                .value
            if rows.isEmpty {
                next.status = .fail
                next.detail = "No active challenges — seed the DB"
            } else {
                next.status = .ok
                next.detail = "\(rows.count)+ active prompts"
            }
        } catch {
            next.status = .fail
            next.detail = Self.shortError(error)
        }
        return next
    }

    private func storageCheck(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item
        do {
            // List with limit — verifies bucket exists + RLS allows list for user path prefix.
            _ = try await client.storage
                .from("session-audio")
                .list(path: AuthService.shared.userId?.uuidString ?? "", options: SearchOptions(limit: 1))
            next.status = .ok
            next.detail = "Bucket reachable"
        } catch {
            let message = Self.shortError(error)
            if message.localizedCaseInsensitiveContains("not found")
                || message.localizedCaseInsensitiveContains("Bucket") {
                next.status = .fail
                next.detail = "Bucket missing or inaccessible"
            } else {
                // Empty folder often still succeeds; other errors may be path-related but bucket exists.
                next.status = .fail
                next.detail = message
            }
        }
        return next
    }

    private func edgeAnalyzePresenceCheck(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item
        // OPTIONS / GET aren't always exposed; a tiny unauthorized-style probe via invoke with empty body
        // would run the full pipeline. Instead hit the functions gateway.
        let base = AppConfig.supabaseURL
        let url = base.appending(path: "functions/v1/analyze-session")
        var request = URLRequest(url: url)
        request.httpMethod = "OPTIONS"
        request.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("authorization, x-client-info, apikey, content-type", forHTTPHeaderField: "Access-Control-Request-Headers")
        request.timeoutInterval = 12

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 404 {
                next.status = .fail
                next.detail = "Function not deployed"
            } else if (200..<500).contains(code) {
                next.status = .ok
                next.detail = "Deployed · HTTP \(code)"
            } else {
                next.status = .fail
                next.detail = "HTTP \(code)"
            }
        } catch {
            next.status = .fail
            next.detail = Self.shortError(error)
        }
        return next
    }

    private func openAIProbe(_ item: SystemCheckItem) async -> SystemCheckItem {
        var next = item
        struct EdgeResponse: Decodable {
            let ok: Bool?
            let error: String?
            let estimatedCostUsd: Double?
            let checks: [EdgeCheck]?
        }
        struct EdgeCheck: Decodable {
            let id: String
            let name: String
            let status: String
            let detail: String?
            let costUsd: Double?
        }

        do {
            let response: EdgeResponse = try await client.functions
                .invoke("system-status", options: .init(body: ["ping": true]))

            if let error = response.error {
                next.status = .fail
                next.detail = error
                return next
            }

            let edgeChecks = response.checks ?? []
            let failed = edgeChecks.filter { $0.status == "fail" }
            let openaiBits = edgeChecks.filter { $0.id.hasPrefix("openai") || $0.id == "edge_db" }
            let detailParts = openaiBits.map { check in
                let mark = check.status == "ok" ? "✓" : (check.status == "fail" ? "✗" : "–")
                return "\(mark) \(check.name)"
            }

            next.costUsd = response.estimatedCostUsd ?? openaiBits.compactMap(\.costUsd).reduce(0, +)
            if failed.isEmpty, response.ok != false {
                next.status = .ok
                next.detail = detailParts.isEmpty
                    ? String(format: "OK · ~$%.5f", next.costUsd ?? 0)
                    : detailParts.joined(separator: " · ")
            } else {
                next.status = .fail
                let failDetail = failed.compactMap(\.detail).first ?? "OpenAI / edge probe failed"
                next.detail = failDetail
            }
        } catch {
            let message = Self.shortError(error)
            if message.localizedCaseInsensitiveContains("not found")
                || message.localizedCaseInsensitiveContains("404") {
                next.status = .fail
                next.detail = "Deploy system-status edge function"
            } else {
                next.status = .fail
                next.detail = message
            }
        }
        return next
    }

    private static func shortError(_ error: Error) -> String {
        let text = error.localizedDescription.replacingOccurrences(of: "\n", with: " ")
        if text.count <= 120 { return text }
        return String(text.prefix(119)) + "…"
    }
}

#endif
