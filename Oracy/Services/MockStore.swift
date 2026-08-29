import Foundation

/// In-memory + UserDefaults store for mock backend mode.
@MainActor
final class MockStore {
    static let shared = MockStore()

    private let defaults = UserDefaults.standard
    private let profileKey = "mock.profile"
    private let sessionsKey = "mock.sessions"
    private let assignmentKey = "mock.assignment"
    private let userIdKey = "mock.userId"

    private(set) var challenges: [Challenge]

    var userId: UUID? {
        get {
            guard let raw = defaults.string(forKey: userIdKey) else { return nil }
            return UUID(uuidString: raw)
        }
        set {
            defaults.set(newValue?.uuidString, forKey: userIdKey)
        }
    }

    var profile: Profile? {
        get { load(profileKey) }
        set { save(newValue, key: profileKey) }
    }

    var sessions: [SpeakingSession] {
        get { load(sessionsKey) ?? [] }
        set { save(newValue, key: sessionsKey) }
    }

    var assignment: DailyAssignment? {
        get { load(assignmentKey) }
        set { save(newValue, key: assignmentKey) }
    }

    private init() {
        challenges = Self.seedChallenges
    }

    func ensureUser() -> UUID {
        if let existing = userId { return existing }
        let id = UUID()
        userId = id
        profile = Profile(
            id: id,
            displayName: nil,
            goals: [],
            experienceLevel: "intermediate",
            streakCount: 0,
            lastPracticeDate: nil,
            timezone: TimeZone.current.identifier,
            onboardingCompleted: false,
            age: nil,
            priorities: [],
            personality: [],
            createdAt: Date()
        )
        return id
    }

    func updateProfile(_ update: ProfileUpdate) {
        guard var current = profile else { return }
        if let name = update.displayName { current.displayName = name }
        if let goals = update.goals { current.goals = goals }
        if let level = update.experienceLevel { current.experienceLevel = level }
        if let tz = update.timezone { current.timezone = tz }
        if let done = update.onboardingCompleted { current.onboardingCompleted = done }
        if let age = update.age { current.age = age }
        if let priorities = update.priorities { current.priorities = priorities }
        if let personality = update.personality { current.personality = personality }
        if let avatarUrl = update.avatarUrl { current.avatarUrl = avatarUrl }
        if let phone = update.phone { current.phone = phone }
        profile = current
    }

    func assignTodaysChallenge() -> Challenge {
        let today = Self.todayString()
        if let existing = assignment, existing.assignedDate == today, let challenge = existing.challenge {
            return challenge
        }

        let level = profile?.experienceLevel ?? "intermediate"
        let pool = challenges.filter { $0.difficulty == level }
        let pick = (pool.isEmpty ? challenges : pool).randomElement()!
        let user = ensureUser()

        assignment = DailyAssignment(
            id: UUID(),
            userId: user,
            challengeId: pick.id,
            assignedDate: today,
            challenge: pick
        )
        return pick
    }

    /// Replaces today's assignment with a different random challenge.
    func shuffleTodaysChallenge(excluding currentId: UUID?) -> Challenge {
        let level = profile?.experienceLevel ?? "intermediate"
        var pool = challenges.filter { $0.difficulty == level }
        if pool.isEmpty { pool = challenges }

        var candidates = pool.filter { $0.id != currentId }
        if candidates.isEmpty { candidates = pool }

        let pick = candidates.randomElement()!
        let user = ensureUser()
        let today = Self.todayString()

        assignment = DailyAssignment(
            id: assignment?.id ?? UUID(),
            userId: user,
            challengeId: pick.id,
            assignedDate: today,
            challenge: pick
        )
        return pick
    }

    func createSession(challengeId: UUID) -> SpeakingSession {
        let user = ensureUser()
        let session = SpeakingSession(
            id: UUID(),
            userId: user,
            challengeId: challengeId,
            audioPath: nil,
            transcript: nil,
            durationSeconds: nil,
            wordCount: nil,
            wordsPerMinute: nil,
            fillerCount: nil,
            feedbackJson: nil,
            overallScore: nil,
            attemptNumber: 1,
            status: "pending",
            createdAt: Date(),
            challenge: challenges.first { $0.id == challengeId }
        )
        var all = sessions
        all.insert(session, at: 0)
        sessions = all
        return session
    }

    func completeSession(
        id: UUID,
        audioPath: String,
        durationSeconds: Double,
        response: AnalyzeResponse
    ) -> SpeakingSession {
        var all = sessions
        guard let index = all.firstIndex(where: { $0.id == id }) else {
            fatalError("Session not found")
        }

        let wordCount = response.transcript.split { $0.isWhitespace || $0.isNewline }.filter { !$0.isEmpty }.count
        all[index].audioPath = audioPath
        all[index].transcript = response.transcript
        all[index].durationSeconds = durationSeconds
        all[index].wordCount = wordCount
        all[index].wordsPerMinute = Double(response.feedback.wordsPerMinute)
        all[index].fillerCount = response.feedback.fillerWords
        all[index].feedbackJson = response.feedback
        all[index].overallScore = response.feedback.overallScore
        all[index].status = "completed"

        sessions = all
        bumpStreak()
        return all[index]
    }

    func bumpStreak() {
        guard var current = profile else { return }
        let today = Self.todayString()
        if current.lastPracticeDate == today {
            return
        }
        if let last = current.lastPracticeDate,
           let lastDate = Self.date(from: last),
           Calendar.current.isDate(lastDate, inSameDayAs: Calendar.current.date(byAdding: .day, value: -1, to: Date())!) {
            current.streakCount += 1
        } else {
            current.streakCount = 1
        }
        current.lastPracticeDate = today
        profile = current
    }

    // MARK: - Debug / preview helpers

    /// Sets streak without requiring a real practice day.
    func setDebugStreak(_ count: Int) {
        _ = ensureUser()
        guard var current = profile else { return }
        current.streakCount = max(0, count)
        current.lastPracticeDate = count > 0 ? Self.todayString() : nil
        profile = current
    }

    /// Replaces sessions with a synthetic pattern for Profile celebration testing.
    /// - Parameters:
    ///   - weekActiveDays: how many of the last 7 days have practice (including today, going backward)
    ///   - yearActiveDays: roughly how many days in the year ahead have at least one session
    ///   - streakDays: consecutive days starting today and running into the year ahead
    ///   - busyDaySessions: sessions on the busiest days (drives heatmap intensity)
    func applyDebugPractice(
        weekActiveDays: Int,
        yearActiveDays: Int,
        streakDays: Int = 0,
        busyDaySessions: Int = 2
    ) {
        let user = ensureUser()
        let challengeId = challenges.first?.id ?? UUID()
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var seeded: [SpeakingSession] = []

        func makeSession(on day: Date, index: Int, duration: Double, words: Int) -> SpeakingSession {
            let stamp = cal.date(byAdding: .minute, value: 10 * index, to: day) ?? day
            return SpeakingSession(
                id: UUID(),
                userId: user,
                challengeId: challengeId,
                audioPath: "mock://debug/\(stamp.timeIntervalSince1970)",
                transcript: "Debug practice session.",
                durationSeconds: duration,
                wordCount: words,
                wordsPerMinute: 120,
                fillerCount: 1,
                feedbackJson: nil,
                overallScore: 78,
                attemptNumber: index + 1,
                status: "completed",
                createdAt: stamp,
                challenge: challenges.first { $0.id == challengeId }
            )
        }

        var occupied = Set<Date>()

        func seedDay(_ dayStart: Date, sessions: Int) {
            guard !occupied.contains(dayStart) else { return }
            occupied.insert(dayStart)
            for i in 0..<max(sessions, 1) {
                seeded.append(makeSession(on: dayStart, index: i, duration: 45 + Double(i * 8), words: 90 + i * 20))
            }
        }

        // This week — consecutive days ending today (week-days stat).
        let weekCount = min(max(weekActiveDays, 0), 7)
        for offset in 0..<weekCount {
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { continue }
            seedDay(cal.startOfDay(for: day), sessions: offset == 0 ? busyDaySessions : 1)
        }

        // Visible “on fire” run: today → the year ahead, consecutive.
        let streakCount = min(max(streakDays, 0), 365)
        for offset in 0..<streakCount {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            seedDay(cal.startOfDay(for: day), sessions: busyDaySessions)
        }

        // Spread remaining year days across the year ahead (skip already occupied).
        let yearTarget = min(max(yearActiveDays, 0), 120)
        var spreadNeeded = max(0, yearTarget - occupied.count)
        var dayCursor = 1
        while spreadNeeded > 0, dayCursor < 365 {
            guard let day = cal.date(byAdding: .day, value: dayCursor, to: today) else { break }
            let dayStart = cal.startOfDay(for: day)
            // Skip some days for a natural look.
            if dayCursor % 3 != 0 {
                dayCursor += 1
                continue
            }
            if !occupied.contains(dayStart) {
                occupied.insert(dayStart)
                let intensity = spreadNeeded % 4 == 0 ? max(busyDaySessions, 1) : 1
                for i in 0..<intensity {
                    seeded.append(makeSession(on: dayStart, index: i, duration: 40, words: 80))
                }
                spreadNeeded -= 1
            }
            dayCursor += 1
        }

        sessions = seeded.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    func deleteAllSessions() {
        sessions = []
    }

    func resetAll() {
        defaults.removeObject(forKey: profileKey)
        defaults.removeObject(forKey: sessionsKey)
        defaults.removeObject(forKey: assignmentKey)
        defaults.removeObject(forKey: userIdKey)
        defaults.removeObject(forKey: referralClaimsKey)
        defaults.removeObject(forKey: referralRedemptionsKey)
        defaults.removeObject(forKey: referralFakeCountKey)
    }

    // MARK: - Referral rewards (mock)

    private var referralClaimsKey: String { "mock.referralClaims" }
    private var referralRedemptionsKey: String { "mock.referralRedemptions" }
    /// Debug/sim count of friends who redeemed this user's code.
    private var referralFakeCountKey: String { "mock.referralInviteCount" }

    private struct MockRedemption: Codable {
        let inviteeId: UUID
        let inviterId: UUID
        let code: String
    }

    func ensureReferralCode() -> String {
        _ = ensureUser()
        if let existing = profile?.referralCode, existing.count >= 6 {
            return existing
        }
        let seed = (userId ?? UUID()).uuidString
        let code = Self.makeReferralCode(from: seed)
        guard var current = profile else { return code }
        current.referralCode = code
        profile = current
        return code
    }

    func referralInviteCount() -> Int {
        max(defaults.integer(forKey: referralFakeCountKey), 0)
    }

    /// DEBUG / Settings: set how many friends have joined via your code.
    func setDebugReferralInviteCount(_ count: Int) {
        defaults.set(max(0, count), forKey: referralFakeCountKey)
    }

    func claimedReferralMilestones() -> Set<Int> {
        let raw = defaults.array(forKey: referralClaimsKey) as? [Int] ?? []
        return Set(raw)
    }

    func referralRewardState() -> ReferralRewardState {
        let code = ensureReferralCode()
        let p = profile
        return ReferralRewardState(
            count: referralInviteCount(),
            bonusSessions: p?.referralBonusWeeklySessions ?? 0,
            proExpiresAt: p?.referralProExpiresAt,
            claimedMilestones: claimedReferralMilestones(),
            referralCode: code,
            milestones: ReferralMilestoneCatalog.fallback
        )
    }

    enum MockRedeemError: Error {
        case invalidCode
        case selfRedeem
        case alreadyRedeemed
        case notFound
    }

    func redeemReferralCode(_ raw: String) throws {
        let code = Self.normalizeReferralCode(raw)
        guard code.count >= 6, code.count <= 10 else { throw MockRedeemError.invalidCode }

        let me = ensureUser()
        let mine = ensureReferralCode()
        guard code != mine else { throw MockRedeemError.selfRedeem }

        var redemptions: [MockRedemption] = load(referralRedemptionsKey) ?? []
        if redemptions.contains(where: { $0.inviteeId == me }) {
            throw MockRedeemError.alreadyRedeemed
        }

        // Mock: any non-self code succeeds and attributes to a synthetic inviter
        // while also bumping "my" invite count when testing as the sharer via debug count.
        let inviter = UUID()
        redemptions.append(MockRedemption(inviteeId: me, inviterId: inviter, code: code))
        save(redemptions, key: referralRedemptionsKey)

        guard var current = profile else { return }
        if current.referredBy == nil {
            current.referredBy = inviter
            current.referralBonusWeeklySessions += 2
            profile = current
        }
    }

    enum MockClaimError: Error {
        case invalidMilestone
        case notUnlocked
        case alreadyClaimed
    }

    @discardableResult
    func claimReferralMilestone(_ milestone: ReferralMilestoneOffer) throws -> ReferralRewardState {
        let count = referralInviteCount()
        guard count >= milestone.friendsRequired else { throw MockClaimError.notUnlocked }

        var claimed = claimedReferralMilestones()
        guard !claimed.contains(milestone.friendsRequired) else { throw MockClaimError.alreadyClaimed }

        guard var current = profile else { throw MockClaimError.notUnlocked }

        if milestone.bonusWeeklySessions > 0 {
            current.referralBonusWeeklySessions += milestone.bonusWeeklySessions
        }
        if milestone.proDays > 0 {
            let base = max(current.referralProExpiresAt ?? Date(), Date())
            current.referralProExpiresAt = Calendar.current.date(
                byAdding: .day,
                value: milestone.proDays,
                to: base
            )
        }
        profile = current

        claimed.insert(milestone.friendsRequired)
        defaults.set(Array(claimed).sorted(), forKey: referralClaimsKey)
        return referralRewardState()
    }

    private static func normalizeReferralCode(_ raw: String) -> String {
        raw.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func makeReferralCode(from seed: String) -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        var hash: UInt64 = 5381
        for byte in seed.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        var chars: [Character] = []
        var value = hash == 0 ? 1 : hash
        for _ in 0..<8 {
            let index = Int(value % UInt64(alphabet.count))
            chars.append(alphabet[index])
            value /= UInt64(alphabet.count)
            value ^= value << 7
        }
        return String(chars)
    }

    func weeklyCompletionCount() -> Int {
        let calendar = Calendar.current
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: Date())!
        let days = Set(
            sessions
                .filter { $0.status == "completed" }
                .compactMap(\.createdAt)
                .filter { $0 >= weekAgo }
                .map { calendar.startOfDay(for: $0).timeIntervalSince1970 }
        )
        return days.count
    }

    func scoreBoard() -> ScoreBoardData {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let completed = sessions.filter { $0.status == "completed" && $0.overallScore != nil }

        let todayScores = completed.compactMap { session -> Int? in
            guard let date = session.createdAt,
                  calendar.isDate(date, inSameDayAs: today) else { return nil }
            return session.overallScore
        }

        let yesterdayScores = completed.compactMap { session -> Int? in
            guard let date = session.createdAt,
                  calendar.isDate(date, inSameDayAs: yesterday) else { return nil }
            return session.overallScore
        }

        return ScoreBoardData(
            todayScore: Self.averageScore(todayScores),
            yesterdayScore: Self.averageScore(yesterdayScores)
        )
    }

    private static func averageScore(_ scores: [Int]) -> Int? {
        guard !scores.isEmpty else { return nil }
        let total = scores.reduce(0, +)
        return Int((Double(total) / Double(scores.count)).rounded())
    }

    // MARK: - Persistence helpers

    private func save<T: Encodable>(_ value: T?, key: String) {
        guard let value else {
            defaults.removeObject(forKey: key)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        defaults.set(try? encoder.encode(value), forKey: key)
    }

    private func load<T: Decodable>(_ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }

    private static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: string)
    }

    private static let seedChallenges: [Challenge] = [
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111001")!, prompt: "Would you rather be rich or famous?", category: "opinion", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111002")!, prompt: "Describe your perfect Sunday.", category: "everyday", difficulty: "beginner", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111003")!, prompt: "What makes a good manager?", category: "work", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111004")!, prompt: "Tell me about a time you failed.", category: "storytelling", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111005")!, prompt: "Is money necessary for happiness?", category: "opinion", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111006")!, prompt: "What is your favorite food?", category: "everyday", difficulty: "beginner", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111007")!, prompt: "Tell me about yourself.", category: "interview", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111008")!, prompt: "Is technological progress always beneficial?", category: "opinion", difficulty: "advanced", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111009")!, prompt: "You wake up on Mars. What do you do?", category: "imagine", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111010")!, prompt: "Social media has made society less social. Agree or disagree?", category: "debate", difficulty: "advanced", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111011")!, prompt: "Why do you like your current job?", category: "opinion", difficulty: "intermediate", active: true),
        Challenge(id: UUID(uuidString: "11111111-1111-1111-1111-111111111012")!, prompt: "Describe your morning routine.", category: "everyday", difficulty: "beginner", active: true),
    ]
}

enum MockFeedbackFactory {
    static func make(
        challengePrompt: String,
        durationSeconds: Double
    ) -> AnalyzeResponse {
        let duration = max(durationSeconds, 1)
        let wordCount = Int.random(in: 80...140)
        let wpm = Int(Double(wordCount) / duration * 60)
        let fillers = Int.random(in: 2...8)
        let overall = Int.random(in: 68...88)

        let feedback = SessionFeedback(
            overallScore: overall,
            fluency: Int.random(in: 70...90),
            grammar: Int.random(in: 65...88),
            vocabulary: Int.random(in: 60...85),
            clarity: Int.random(in: 72...92),
            confidence: Int.random(in: 68...88),
            wordsPerMinute: wpm,
            fillerWords: fillers,
            strengths: [
                "You clearly stated your opinion and supported it with reasons.",
                "Your pacing made the answer easy to follow.",
            ],
            nextImprovement: "You repeated “I think” a few times. Try stronger transitions like “I’d argue that…” or “What stands out is…”.",
            grammarCorrections: [
                GrammarCorrection(
                    original: "Yesterday I go to the office.",
                    corrected: "Yesterday I went to the office.",
                    explanation: "You’re talking about something that already happened, so use the past tense."
                ),
            ],
            vocabularySuggestions: [
                VocabularySuggestion(
                    original: "very good",
                    suggestions: ["rewarding", "impressive", "compelling"],
                    context: "A more precise word makes your point land harder."
                ),
            ],
            structureScore: Int.random(in: 6...9),
            structureNote: "You had a clear opinion, but the answer ended without a short conclusion.",
            paceNote: wpm > 160
                ? "You spoke quite quickly. Try slowing down slightly to make your ideas clearer."
                : "Your pace is comfortable and easy to follow.",
            suggestedExpression: SuggestedExpression(
                instead: "I think this is very important.",
                alternative: "I’d argue that this is crucial."
            )
        )

        return AnalyzeResponse(
            sessionId: UUID().uuidString,
            transcript: mockTranscript(for: challengePrompt),
            feedback: feedback,
            streakCount: MockStore.shared.profile?.streakCount ?? 1
        )
    }

    private static func mockTranscript(for prompt: String) -> String {
        """
        So, thinking about the question — \(prompt.lowercased()) — I’d say it really depends on what matters most to you. \
        For me, I’d choose the option that gives more freedom and long-term satisfaction. \
        Um, I think confidence comes from practice, and speaking for even one minute a day can make a big difference. \
        Overall, I’d argue that clarity and honesty matter more than trying to sound perfect.
        """
    }
}
