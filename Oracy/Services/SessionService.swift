import Foundation
import Supabase

@MainActor
@Observable
final class SessionService {
    static let shared = SessionService()

    var sessions: [SpeakingSession] = []
    var isLoading = false
    var isAnalyzing = false
    var analysisError: String?

    private var client: SupabaseClient { SupabaseManager.shared.client }

    private init() {}

    func createSession(challengeId: UUID) async throws -> SpeakingSession {
        guard let userId = AuthService.shared.userId else {
            throw SessionError.notAuthenticated
        }

        if AppConfig.useMockBackend {
            let session = MockStore.shared.createSession(challengeId: challengeId)
            AnalyticsService.shared.track(.sessionCreated, [
                "session_id": session.id.uuidString.lowercased(),
                "challenge_id": challengeId.uuidString.lowercased(),
                "backend": "mock"
            ])
            return session
        }

        let insert = SessionInsert(
            userId: userId,
            challengeId: challengeId,
            status: "pending",
            attemptNumber: 1
        )

        let session: SpeakingSession = try await client
            .from("sessions")
            .insert(insert)
            .select()
            .single()
            .execute()
            .value
        AnalyticsService.shared.track(.sessionCreated, [
            "session_id": session.id.uuidString.lowercased(),
            "challenge_id": challengeId.uuidString.lowercased()
        ])
        return session
    }

    func uploadAudio(sessionId: UUID, userId: UUID, audioURL: URL) async throws -> String {
        let path = "\(userId.uuidString.lowercased())/\(sessionId.uuidString.lowercased()).m4a"

        if AppConfig.useMockBackend {
            // Persist a local copy so History can play it back.
            return try LocalAudioStore.save(from: audioURL, sessionId: sessionId)
        }

        let data = try Data(contentsOf: audioURL)

        // Also keep a local cache for offline History playback.
        _ = try? LocalAudioStore.save(from: audioURL, sessionId: sessionId)

        try await client.storage
            .from("session-audio")
            .upload(path, data: data, options: .init(contentType: "audio/m4a", upsert: true))

        try await client
            .from("sessions")
            .update(["audio_path": path, "status": "processing"])
            .eq("id", value: sessionId)
            .execute()

        return path
    }

    /// Resolves a playable file URL for a session (local cache or remote download).
    func audioURL(for session: SpeakingSession) async -> URL? {
        if let local = LocalAudioStore.url(forStoredPath: session.audioPath, sessionId: session.id) {
            return local
        }

        guard !AppConfig.useMockBackend, let remotePath = session.audioPath else { return nil }

        do {
            let data = try await client.storage
                .from("session-audio")
                .download(path: remotePath)
            let dest = LocalAudioStore.fileURL(sessionId: session.id)
            try data.write(to: dest, options: .atomic)
            return dest
        } catch {
            return nil
        }
    }

    func deleteSession(_ session: SpeakingSession) async throws {
        LocalAudioStore.delete(sessionId: session.id)

        if AppConfig.useMockBackend {
            var all = MockStore.shared.sessions
            all.removeAll { $0.id == session.id }
            MockStore.shared.sessions = all
            sessions.removeAll { $0.id == session.id }
            return
        }

        if let path = session.audioPath {
            try? await client.storage.from("session-audio").remove(paths: [path])
        }

        try await client
            .from("sessions")
            .delete()
            .eq("id", value: session.id)
            .execute()

        sessions.removeAll { $0.id == session.id }
    }

    func analyzeSession(
        sessionId: UUID,
        audioPath: String,
        challengePrompt: String,
        userLevel: String,
        userGoals: [String],
        durationSeconds: Double
    ) async throws -> AnalyzeResponse {
        isAnalyzing = true
        analysisError = nil
        defer { isAnalyzing = false }

        AnalyticsService.shared.track(.analysisStarted, [
            "session_id": sessionId.uuidString.lowercased(),
            "duration_seconds": String(Int(durationSeconds.rounded()))
        ])

        if AppConfig.useMockBackend {
            // Simulate network latency
            try await Task.sleep(for: .seconds(1.5))
            var response = MockFeedbackFactory.make(
                challengePrompt: challengePrompt,
                durationSeconds: durationSeconds
            )
            _ = MockStore.shared.completeSession(
                id: sessionId,
                audioPath: audioPath,
                durationSeconds: durationSeconds,
                response: response
            )
            await AuthService.shared.fetchProfile()
            await PracticeReminderService.shared.didCompletePracticeToday()
            response = AnalyzeResponse(
                sessionId: sessionId.uuidString,
                transcript: response.transcript,
                feedback: response.feedback,
                streakCount: AuthService.shared.profile?.streakCount ?? 1
            )
            AnalyticsService.shared.track(.analysisSucceeded, [
                "session_id": sessionId.uuidString.lowercased(),
                "backend": "mock",
                "score": String(response.feedback.overallScore)
            ])
            return response
        }

        struct AnalyzeRequest: Encodable {
            let sessionId: String
            let audioPath: String
            let challengePrompt: String
            let userLevel: String
            let userGoals: [String]
            let durationSeconds: Double
        }

        let request = AnalyzeRequest(
            sessionId: sessionId.uuidString,
            audioPath: audioPath,
            challengePrompt: challengePrompt,
            userLevel: userLevel,
            userGoals: userGoals,
            durationSeconds: durationSeconds
        )

        do {
            let response: AnalyzeResponse = try await client.functions
                .invoke("analyze-session", options: .init(body: request))

            await AuthService.shared.fetchProfile()
            await PracticeReminderService.shared.didCompletePracticeToday()
            AnalyticsService.shared.track(.analysisSucceeded, [
                "session_id": sessionId.uuidString.lowercased(),
                "score": String(response.feedback.overallScore)
            ])
            return response
        } catch let FunctionsError.httpError(_, data) {
            let message = Self.edgeFunctionMessage(from: data)
            AnalyticsService.shared.track(.analysisFailed, [
                "session_id": sessionId.uuidString.lowercased(),
                "reason": String(message.prefix(120))
            ])
            throw SessionError.analysisFailed(message)
        } catch {
            AnalyticsService.shared.track(.analysisFailed, [
                "session_id": sessionId.uuidString.lowercased(),
                "reason": String(error.localizedDescription.prefix(120))
            ])
            throw error
        }
    }

    /// Prefer the edge function's `{ "error": "..." }` body over the SDK's generic non-2xx text.
    private static func edgeFunctionMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? String,
           !error.isEmpty {
            if error.localizedCaseInsensitiveContains("insufficient_quota")
                || error.localizedCaseInsensitiveContains("exceeded your current quota") {
                return "OpenAI quota exceeded. Add billing credits or update OPENAI_API_KEY in Supabase secrets."
            }
            return error
        }
        if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        return "Analysis failed. Please try again."
    }

    func fetchSessions() async {
        guard AuthService.shared.userId != nil else { return }
        isLoading = true
        defer { isLoading = false }

        if AppConfig.useMockBackend {
            sessions = MockStore.shared.sessions.filter { $0.status == "completed" }
            return
        }

        guard let userId = AuthService.shared.userId else { return }

        do {
            sessions = try await client
                .from("sessions")
                .select("*, challenges(*)")
                .eq("user_id", value: userId)
                .eq("status", value: "completed")
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            analysisError = error.localizedDescription
        }
    }

    func fetchSession(id: UUID) async throws -> SpeakingSession {
        if AppConfig.useMockBackend {
            guard let session = MockStore.shared.sessions.first(where: { $0.id == id }) else {
                throw SessionError.notFound
            }
            return session
        }

        return try await client
            .from("sessions")
            .select("*, challenges(*)")
            .eq("id", value: id)
            .single()
            .execute()
            .value
    }

    func deleteAllRecordings() async throws {
        if AppConfig.useMockBackend {
            MockStore.shared.deleteAllSessions()
            sessions = []
            return
        }

        guard let userId = AuthService.shared.userId else { return }

        let userSessions: [SpeakingSession] = try await client
            .from("sessions")
            .select("id, audio_path")
            .eq("user_id", value: userId)
            .execute()
            .value

        let paths = userSessions.compactMap(\.audioPath)
        if !paths.isEmpty {
            try await client.storage.from("session-audio").remove(paths: paths)
        }

        try await client
            .from("sessions")
            .delete()
            .eq("user_id", value: userId)
            .execute()

        sessions = []
    }

    /// Average completed overall score for today and yesterday (calendar days).
    func scoreBoard() async -> ScoreBoardData {
        if AppConfig.useMockBackend {
            return MockStore.shared.scoreBoard()
        }

        guard let userId = AuthService.shared.userId else {
            return ScoreBoardData(todayScore: nil, yesterdayScore: nil)
        }

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        guard let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart),
              let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else {
            return ScoreBoardData(todayScore: nil, yesterdayScore: nil)
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        struct ScoreBoardRow: Decodable {
            let overallScore: Int?
            let createdAt: Date?
            let status: String

            enum CodingKeys: String, CodingKey {
                case overallScore = "overall_score"
                case createdAt = "created_at"
                case status
            }
        }

        do {
            let recent: [ScoreBoardRow] = try await client
                .from("sessions")
                .select("overall_score, created_at, status")
                .eq("user_id", value: userId)
                .eq("status", value: "completed")
                .gte("created_at", value: formatter.string(from: yesterdayStart))
                .lt("created_at", value: formatter.string(from: tomorrowStart))
                .execute()
                .value

            let todayScores = recent.compactMap { row -> Int? in
                guard let date = row.createdAt,
                      calendar.isDate(date, inSameDayAs: todayStart) else { return nil }
                return row.overallScore
            }
            let yesterdayScores = recent.compactMap { row -> Int? in
                guard let date = row.createdAt,
                      calendar.isDate(date, inSameDayAs: yesterdayStart) else { return nil }
                return row.overallScore
            }

            return ScoreBoardData(
                todayScore: Self.averageScore(todayScores),
                yesterdayScore: Self.averageScore(yesterdayScores)
            )
        } catch {
            return ScoreBoardData(todayScore: nil, yesterdayScore: nil)
        }
    }

    private static func averageScore(_ scores: [Int]) -> Int? {
        guard !scores.isEmpty else { return nil }
        let total = scores.reduce(0, +)
        return Int((Double(total) / Double(scores.count)).rounded())
    }
}

enum SessionError: LocalizedError {
    case notAuthenticated
    case notFound
    case analysisFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to record a session"
        case .notFound: return "Session not found"
        case .analysisFailed(let message): return message
        }
    }
}
