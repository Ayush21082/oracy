import Foundation
import Supabase

@MainActor
@Observable
final class ChallengeService {
    static let shared = ChallengeService()

    var todaysChallenge: Challenge?
    var todaysAssignment: DailyAssignment?
    var isLoading = false

    private var client: SupabaseClient { SupabaseManager.shared.client }
    private var lastTrackedChallengeId: UUID?

    private init() {}

    func loadTodaysChallenge() async throws {
        guard AuthService.shared.userId != nil else { return }
        isLoading = true
        defer { isLoading = false }

        if AppConfig.useMockBackend {
            let challenge = MockStore.shared.assignTodaysChallenge()
            todaysChallenge = challenge
            todaysAssignment = MockStore.shared.assignment
            trackChallengeViewedIfNeeded(challenge, backend: "mock")
            return
        }

        guard let userId = AuthService.shared.userId else { return }

        _ = try await client.rpc("assign_daily_challenge", params: ["p_user_id": userId.uuidString])
            .execute()

        let assignments: [DailyAssignment] = try await client
            .from("daily_assignments")
            .select("*, challenges(*)")
            .eq("user_id", value: userId)
            .order("assigned_date", ascending: false)
            .limit(1)
            .execute()
            .value

        if let assignment = assignments.first {
            todaysAssignment = assignment
            todaysChallenge = assignment.challenge
            if let challenge = assignment.challenge {
                trackChallengeViewedIfNeeded(challenge)
            }
        }
    }

    private func trackChallengeViewedIfNeeded(_ challenge: Challenge, backend: String? = nil) {
        guard challenge.id != lastTrackedChallengeId else { return }
        lastTrackedChallengeId = challenge.id
        var props = [
            "challenge_id": challenge.id.uuidString.lowercased(),
            "category": challenge.category
        ]
        if let backend { props["backend"] = backend }
        AnalyticsService.shared.track(.challengeViewed, props)
    }

    /// Pick a different challenge for today (keeps streak/score intact).
    @discardableResult
    func shuffleTodaysChallenge() async throws -> Challenge {
        let excluding = todaysChallenge?.id

        if AppConfig.useMockBackend {
            let challenge = MockStore.shared.shuffleTodaysChallenge(excluding: excluding)
            todaysChallenge = challenge
            todaysAssignment = MockStore.shared.assignment
            lastTrackedChallengeId = challenge.id
            return challenge
        }

        guard let userId = AuthService.shared.userId else {
            throw ChallengeError.notAuthenticated
        }

        // Load a random active challenge different from current
        let all: [Challenge] = try await client
            .from("challenges")
            .select()
            .eq("active", value: true)
            .execute()
            .value
        let level = AuthService.shared.profile?.experienceLevel ?? "intermediate"
        var pool = all.filter { $0.difficulty == level }
        if pool.isEmpty { pool = all }
        var candidates = pool.filter { $0.id != excluding }
        if candidates.isEmpty { candidates = pool }

        guard let pick = candidates.randomElement() else {
            throw ChallengeError.noChallenges
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())

        if let assignmentId = todaysAssignment?.id {
            try await client
                .from("daily_assignments")
                .update(["challenge_id": pick.id.uuidString])
                .eq("id", value: assignmentId)
                .execute()
        } else {
            struct AssignmentInsert: Encodable {
                let user_id: String
                let challenge_id: String
                let assigned_date: String
            }
            try await client
                .from("daily_assignments")
                .insert(AssignmentInsert(
                    user_id: userId.uuidString,
                    challenge_id: pick.id.uuidString,
                    assigned_date: today
                ))
                .execute()
        }

        try await loadTodaysChallenge()
        let challenge = todaysChallenge ?? pick
        lastTrackedChallengeId = challenge.id
        return challenge
    }

    func weeklyCompletionCount() async -> Int {
        if AppConfig.useMockBackend {
            return MockStore.shared.weeklyCompletionCount()
        }

        guard let userId = AuthService.shared.userId else { return 0 }
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!

        do {
            let sessions: [SpeakingSession] = try await client
                .from("sessions")
                .select("id, created_at")
                .eq("user_id", value: userId)
                .eq("status", value: "completed")
                .gte("created_at", value: ISO8601DateFormatter().string(from: weekAgo))
                .execute()
                .value

            let uniqueDays = Set(sessions.compactMap { session -> String? in
                guard let date = session.createdAt else { return nil }
                return calendar.startOfDay(for: date).description
            })
            return uniqueDays.count
        } catch {
            return 0
        }
    }
}

enum ChallengeError: LocalizedError {
    case notAuthenticated
    case noChallenges

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "You must be signed in to shuffle topics"
        case .noChallenges: return "No challenges available"
        }
    }
}
