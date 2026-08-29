import Foundation

enum ExperienceLevel: String, Codable, CaseIterable, Identifiable {
    case beginner
    case intermediate
    case advanced
    case expert

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

enum UserGoal: String, Codable, CaseIterable, Identifiable {
    case speakingConfidence = "speaking_confidence"
    case vocabulary
    case grammar
    case fluency
    case interviewSkills = "interview_skills"
    case communication

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .speakingConfidence: return "Speaking confidence"
        case .vocabulary: return "Vocabulary"
        case .grammar: return "Grammar"
        case .fluency: return "Fluency"
        case .interviewSkills: return "Interview skills"
        case .communication: return "Communication"
        }
    }
}

enum ChallengeCategory: String, Codable {
    case everyday, opinion, storytelling, imagine, work, debate, interview
}

enum SessionStatus: String, Codable {
    case pending, processing, completed, failed
}

struct Profile: Codable, Identifiable {
    let id: UUID
    var displayName: String?
    var goals: [String]
    var experienceLevel: String
    var streakCount: Int
    var lastPracticeDate: String?
    var timezone: String
    var onboardingCompleted: Bool
    var age: Int?
    var priorities: [String]
    var personality: [String]
    var avatarUrl: String?
    var phone: String?
    var referralCode: String?
    var referredBy: UUID?
    var referralBonusWeeklySessions: Int
    var referralProExpiresAt: Date?
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case goals
        case experienceLevel = "experience_level"
        case streakCount = "streak_count"
        case lastPracticeDate = "last_practice_date"
        case timezone
        case onboardingCompleted = "onboarding_completed"
        case age
        case priorities
        case personality
        case avatarUrl = "avatar_url"
        case phone
        case referralCode = "referral_code"
        case referredBy = "referred_by"
        case referralBonusWeeklySessions = "referral_bonus_weekly_sessions"
        case referralProExpiresAt = "referral_pro_expires_at"
        case createdAt = "created_at"
    }

    init(
        id: UUID,
        displayName: String?,
        goals: [String],
        experienceLevel: String,
        streakCount: Int,
        lastPracticeDate: String?,
        timezone: String,
        onboardingCompleted: Bool,
        age: Int? = nil,
        priorities: [String] = [],
        personality: [String] = [],
        avatarUrl: String? = nil,
        phone: String? = nil,
        referralCode: String? = nil,
        referredBy: UUID? = nil,
        referralBonusWeeklySessions: Int = 0,
        referralProExpiresAt: Date? = nil,
        createdAt: Date?
    ) {
        self.id = id
        self.displayName = displayName
        self.goals = goals
        self.experienceLevel = experienceLevel
        self.streakCount = streakCount
        self.lastPracticeDate = lastPracticeDate
        self.timezone = timezone
        self.onboardingCompleted = onboardingCompleted
        self.age = age
        self.priorities = priorities
        self.personality = personality
        self.avatarUrl = avatarUrl
        self.phone = phone
        self.referralCode = referralCode
        self.referredBy = referredBy
        self.referralBonusWeeklySessions = referralBonusWeeklySessions
        self.referralProExpiresAt = referralProExpiresAt
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        goals = try c.decodeIfPresent([String].self, forKey: .goals) ?? []
        experienceLevel = try c.decodeIfPresent(String.self, forKey: .experienceLevel) ?? "beginner"
        streakCount = try c.decodeIfPresent(Int.self, forKey: .streakCount) ?? 0
        lastPracticeDate = try c.decodeIfPresent(String.self, forKey: .lastPracticeDate)
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? "UTC"
        onboardingCompleted = try c.decodeIfPresent(Bool.self, forKey: .onboardingCompleted) ?? false
        age = try c.decodeIfPresent(Int.self, forKey: .age)
        priorities = try c.decodeIfPresent([String].self, forKey: .priorities) ?? []
        personality = try c.decodeIfPresent([String].self, forKey: .personality) ?? []
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
        referralCode = try c.decodeIfPresent(String.self, forKey: .referralCode)
        referredBy = try c.decodeIfPresent(UUID.self, forKey: .referredBy)
        referralBonusWeeklySessions = try c.decodeIfPresent(Int.self, forKey: .referralBonusWeeklySessions) ?? 0
        referralProExpiresAt = try c.decodeIfPresent(Date.self, forKey: .referralProExpiresAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
    }
}

struct Challenge: Codable, Identifiable {
    let id: UUID
    let prompt: String
    let category: String
    let difficulty: String
    let active: Bool?
}

struct DailyAssignment: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let challengeId: UUID
    let assignedDate: String
    let challenge: Challenge?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case challengeId = "challenge_id"
        case assignedDate = "assigned_date"
        case challenge = "challenges"
    }
}

struct SpeakingSession: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let challengeId: UUID
    var audioPath: String?
    var transcript: String?
    var durationSeconds: Double?
    var wordCount: Int?
    var wordsPerMinute: Double?
    var fillerCount: Int?
    var feedbackJson: SessionFeedback?
    var overallScore: Int?
    var attemptNumber: Int
    var status: String
    let createdAt: Date?
    var challenge: Challenge?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case challengeId = "challenge_id"
        case audioPath = "audio_path"
        case transcript
        case durationSeconds = "duration_seconds"
        case wordCount = "word_count"
        case wordsPerMinute = "words_per_minute"
        case fillerCount = "filler_count"
        case feedbackJson = "feedback_json"
        case overallScore = "overall_score"
        case attemptNumber = "attempt_number"
        case status
        case createdAt = "created_at"
        case challenge = "challenges"
    }
}

struct SessionFeedback: Codable {
    let overallScore: Int
    let fluency: Int
    let grammar: Int
    let vocabulary: Int
    let clarity: Int
    let confidence: Int
    let wordsPerMinute: Int
    let fillerWords: Int
    let strengths: [String]
    let nextImprovement: String
    let grammarCorrections: [GrammarCorrection]
    let vocabularySuggestions: [VocabularySuggestion]
    let structureScore: Int
    let structureNote: String
    let paceNote: String
    let suggestedExpression: SuggestedExpression

    var scoreLabel: String {
        switch overallScore {
        case 90...100: return "Excellent"
        case 80..<90: return "Great"
        case 70..<80: return "Good"
        case 60..<70: return "Fair"
        default: return "Keep practicing"
        }
    }
}

struct GrammarCorrection: Codable, Identifiable {
    var id: String { original }
    let original: String
    let corrected: String
    let explanation: String
}

struct VocabularySuggestion: Codable, Identifiable {
    var id: String { original }
    let original: String
    let suggestions: [String]
    let context: String
}

struct SuggestedExpression: Codable {
    let instead: String
    let alternative: String

    enum CodingKeys: String, CodingKey {
        case instead
        case alternative = "try"
    }
}

struct AnalyzeResponse: Codable {
    let sessionId: String
    let transcript: String
    let feedback: SessionFeedback
    let streakCount: Int
}

/// Home scoreboard: today's average completed score vs yesterday.
struct ScoreBoardData: Equatable {
    var todayScore: Int?
    var yesterdayScore: Int?

    var delta: Int? {
        guard let todayScore, let yesterdayScore else { return nil }
        return todayScore - yesterdayScore
    }

    var hasPracticedToday: Bool { todayScore != nil }
}


struct SessionInsert: Encodable {
    let userId: UUID
    let challengeId: UUID
    let status: String
    let attemptNumber: Int

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case challengeId = "challenge_id"
        case status
        case attemptNumber = "attempt_number"
    }
}

struct ProfileUpdate: Encodable {
    var displayName: String?
    var goals: [String]?
    var experienceLevel: String?
    var timezone: String?
    var onboardingCompleted: Bool?
    var age: Int?
    var priorities: [String]?
    var personality: [String]?
    var avatarUrl: String?
    var phone: String?

    enum CodingKeys: String, CodingKey {
        case displayName = "display_name"
        case goals
        case experienceLevel = "experience_level"
        case timezone
        case onboardingCompleted = "onboarding_completed"
        case age
        case priorities
        case personality
        case avatarUrl = "avatar_url"
        case phone
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(displayName, forKey: .displayName)
        try c.encodeIfPresent(goals, forKey: .goals)
        try c.encodeIfPresent(experienceLevel, forKey: .experienceLevel)
        try c.encodeIfPresent(timezone, forKey: .timezone)
        try c.encodeIfPresent(onboardingCompleted, forKey: .onboardingCompleted)
        try c.encodeIfPresent(age, forKey: .age)
        try c.encodeIfPresent(priorities, forKey: .priorities)
        try c.encodeIfPresent(personality, forKey: .personality)
        try c.encodeIfPresent(avatarUrl, forKey: .avatarUrl)
        try c.encodeIfPresent(phone, forKey: .phone)
    }
}
