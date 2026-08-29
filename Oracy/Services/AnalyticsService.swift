import Foundation
import Supabase

/// Queues product analytics and flushes batches to Supabase `track_analytics_events`.
@MainActor
@Observable
final class AnalyticsService {
    static let shared = AnalyticsService()

    private let installIdKey = "analytics.installId"
    private let maxQueue = 100
    private let flushBatchSize = 20
    private let flushInterval: TimeInterval = 12

    private(set) var pendingCount = 0

    private var queue: [QueuedEvent] = []
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private var sessionId = UUID().uuidString.lowercased()
    private var lastScreen: String?

    private var installId: String {
        if let existing = UserDefaults.standard.string(forKey: installIdKey), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString.lowercased()
        UserDefaults.standard.set(id, forKey: installIdKey)
        return id
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private init() {
        schedulePeriodicFlush()
    }

    /// Call on cold start / after auth is ready.
    func startSession() {
        sessionId = UUID().uuidString.lowercased()
        track(.appOpened, [
            "backend": AppConfig.useMockBackend ? "mock" : "supabase"
        ])
    }

    func track(_ event: AnalyticsEvent, _ properties: [String: String] = [:]) {
        track(name: event.rawValue, properties: properties)
    }

    func track(name: String, properties: [String: String] = [:]) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let item = QueuedEvent(
            clientEventId: UUID(),
            name: trimmed,
            properties: properties,
            createdAt: Date()
        )
        queue.append(item)
        if queue.count > maxQueue {
            queue.removeFirst(queue.count - maxQueue)
        }
        pendingCount = queue.count

        #if DEBUG
        if AppConfig.useMockBackend {
            print("[Analytics] \(trimmed) \(properties)")
        }
        #endif

        if queue.count >= flushBatchSize {
            Task { await flush() }
        }
    }

    func screen(_ name: String, _ properties: [String: String] = [:]) {
        guard name != lastScreen else { return }
        lastScreen = name
        var props = properties
        props["screen"] = name
        track(.screenViewed, props)
    }

    func flushSoon() {
        Task { await flush() }
    }

    func flush() async {
        guard !isFlushing else { return }
        guard !queue.isEmpty else { return }

        // Wait until we have a user (anon or linked) — RLS requires auth.uid().
        guard AuthService.shared.userId != nil else { return }

        if AppConfig.useMockBackend {
            queue.removeAll()
            pendingCount = 0
            return
        }

        guard AppConfig.isSupabaseConfigured else { return }

        isFlushing = true
        defer { isFlushing = false }

        let batch = Array(queue.prefix(flushBatchSize))
        let payload: [[String: AnyJSON]] = batch.map { event in
            var props: [String: AnyJSON] = [:]
            for (key, value) in event.properties {
                props[key] = .string(value)
            }
            return [
                "client_event_id": .string(event.clientEventId.uuidString.lowercased()),
                "name": .string(event.name),
                "properties": .object(props),
                "platform": .string("ios"),
                "app_version": .string(appVersion),
                "install_id": .string(installId),
                "session_id": .string(sessionId),
                "created_at": .string(ISO8601DateFormatter.analytics.string(from: event.createdAt))
            ]
        }

        do {
            struct Params: Encodable {
                let events: AnyJSON
            }
            try await SupabaseManager.shared.client
                .rpc(
                    "track_analytics_events",
                    params: Params(events: .array(payload.map { .object($0) }))
                )
                .execute()

            queue.removeAll { item in
                batch.contains(where: { $0.clientEventId == item.clientEventId })
            }
            pendingCount = queue.count
        } catch {
            #if DEBUG
            print("[Analytics] flush failed: \(error.localizedDescription)")
            #endif
            // Keep queued events for the next flush.
        }
    }

    private func schedulePeriodicFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                await self?.flush()
            }
        }
    }
}

private struct QueuedEvent: Identifiable, Equatable {
    var id: UUID { clientEventId }
    let clientEventId: UUID
    let name: String
    let properties: [String: String]
    let createdAt: Date
}

private extension ISO8601DateFormatter {
    static let analytics: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

// MARK: - SwiftUI helpers

import SwiftUI

extension View {
    /// Tracks a screen view once when the view appears (deduped per consecutive screen).
    func trackScreen(_ name: String, _ properties: [String: String] = [:]) -> some View {
        onAppear {
            AnalyticsService.shared.screen(name, properties)
        }
    }
}
