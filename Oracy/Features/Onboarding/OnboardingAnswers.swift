import Foundation

enum OnboardingPriority: String, CaseIterable, Identifiable {
    case confidence
    case conversation
    case clarity
    case communication
    case presence

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .confidence: return "Confidence"
        case .conversation: return "Conversation"
        case .clarity: return "Clarity"
        case .communication: return "Communication"
        case .presence: return "Presence"
        }
    }
}

enum OnboardingPersonalityTag: String, CaseIterable, Identifiable {
    case technology
    case entrepreneur
    case remote
    case finance
    case doctor
    case creative
    case student
    case builder

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .technology: return "Technology"
        case .entrepreneur: return "Entrepreneur"
        case .remote: return "Remote"
        case .finance: return "Finance"
        case .doctor: return "Doctor"
        case .creative: return "Creative"
        case .student: return "Student"
        case .builder: return "Builder"
        }
    }
}

struct OnboardingAnswers {
    var displayName: String = ""
    var authChoice: AuthChoice = .guest
    var priorities: Set<OnboardingPriority> = []
    var age: Int = 24
    var personality: Set<OnboardingPersonalityTag> = []
    var goals: Set<UserGoal> = []
    var level: ExperienceLevel = .intermediate
    /// Optional friend code entered near the end of onboarding.
    var referralCode: String = ""
    var didSkipReferralCode: Bool = false

    enum AuthChoice {
        case apple, google, phone, guest
    }

    var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedReferralCode: String {
        InviteService.parseReferralCode(referralCode)
    }

    var prioritiesStorageValue: String {
        priorities.map(\.rawValue).sorted().joined(separator: ",")
    }

    var occupationStorageValue: String {
        personality.map(\.displayName).sorted().joined(separator: ", ")
    }

    var ageStorageValue: String { String(age) }
}

enum ConversationBeat: Int, CaseIterable, Identifiable {
    case greeting
    case auth
    case name
    case priorities
    case age
    case personality
    case goals
    case level
    case review
    /// Optional — only inserted when RC `referral_rewards_enabled` is on.
    case referral

    var id: Int { rawValue }

    var next: ConversationBeat? {
        ConversationBeat(rawValue: rawValue + 1)
    }

    /// Conversation prompts are left-aligned (same layout for every beat, including greeting).
    var isCentered: Bool { false }

    var title: String {
        switch self {
        case .greeting: return "Hey 👋"
        case .auth: return "Have we met before?"
        case .name: return "What should I call you?"
        case .priorities: return "What matters most to you?"
        case .age: return "How old are you?"
        case .personality: return "What best describes you?"
        case .goals: return "What do you want to improve when you speak?"
        case .level: return "How comfortable are you speaking aloud?"
        case .review: return "Alright."
        case .referral: return "Got a friend’s code?"
        }
    }

    var subtitle: String? {
        switch self {
        case .greeting:
            return "I'll help you get set up for one-minute speaking practice."
        case .auth:
            return "Let's see if I can make this a little quicker."
        case .name:
            return "Just your first name is perfect."
        case .priorities:
            return "Tell me what you'd like to get better at."
        case .age:
            return "Just so I can understand you a little better."
        case .personality:
            return "Pick whatever feels most like you."
        case .goals:
            return "This helps me personalize your practice."
        case .level:
            return "Be honest — there's no wrong answer."
        case .review:
            return "I think I've got enough to get you started."
        case .referral:
            return "Optional — you both get +2 weekly speaks if someone invited you."
        }
    }
}

enum ConversationCopy {
    static func authAcknowledgment(_ choice: OnboardingAnswers.AuthChoice) -> [String] {
        switch choice {
        case .apple, .google, .phone:
            return ["Thanks for joining."]
        case .guest:
            return ["Okay.", "We can keep going."]
        }
    }

    static func prioritiesAcknowledgment(_ selected: Set<OnboardingPriority>) -> [String] {
        let ordered = OnboardingPriority.allCases.filter { selected.contains($0) }
        guard !ordered.isEmpty else { return ["Got it."] }

        let body: String
        let names = Set(ordered.map(\.self))

        if names == [.confidence, .conversation] || names == [.confidence, .conversation, .clarity] {
            body = "You want to feel more confident in conversations."
        } else if names.contains(.clarity) && names.contains(.communication) {
            body = "You want to communicate with more clarity."
        } else if names.contains(.confidence) && names.contains(.clarity) {
            body = "You came here to build confidence and communicate with more clarity."
        } else if names.contains(.confidence) && names.contains(.communication) {
            body = "You want to build confidence and communicate more clearly."
        } else if names.contains(.presence) && names.contains(.confidence) {
            body = "You're looking for more presence and confidence when you speak."
        } else if ordered.count == 1 {
            switch ordered[0] {
            case .confidence: body = "You're here to feel more confident when you speak."
            case .conversation: body = "You want conversations to feel easier and more natural."
            case .clarity: body = "You're looking for clearer, sharper expression."
            case .communication: body = "You want to communicate with more impact."
            case .presence: body = "You're looking for a stronger presence when you speak."
            }
        } else {
            let list = joinDisplay(ordered.map(\.displayName))
            body = "You came here to get better at \(list.lowercased())."
        }

        return ["Got it.", body]
    }

    static func ageAcknowledgment(_ age: Int) -> [String] {
        ["Nice, \(age)."]
    }

    static func nameAcknowledgment(_ name: String) -> [String] {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ["Nice to meet you."] }
        return ["Nice to meet you, \(trimmed)."]
    }

    static func personalityAcknowledgment(_ selected: Set<OnboardingPersonalityTag>) -> [String] {
        let ordered = OnboardingPersonalityTag.allCases.filter { selected.contains($0) }
        guard !ordered.isEmpty else { return ["That makes sense."] }
        let list = joinDisplay(ordered.map(\.displayName))
        return ["You picked \(list).", "That makes sense."]
    }

    static func goalsAcknowledgment(_ selected: Set<UserGoal>) -> [String] {
        let ordered = UserGoal.allCases.filter { selected.contains($0) }
        guard !ordered.isEmpty else { return ["Perfect."] }
        if ordered.count == 1 {
            return ["Perfect.", "We'll focus on \(ordered[0].displayName.lowercased())."]
        }
        let list = joinDisplay(ordered.prefix(3).map(\.displayName))
        return ["Perfect.", "We'll keep \(list.lowercased()) in mind."]
    }

    static func levelAcknowledgment(_ level: ExperienceLevel) -> [String] {
        switch level {
        case .beginner:
            return ["Got it.", "We'll start gently and build from there."]
        case .intermediate:
            return ["Got it.", "A solid place to practice from."]
        case .advanced:
            return ["Got it.", "We'll keep the challenges sharp."]
        case .expert:
            return ["Got it."]
        }
    }

    static func reviewAcknowledgment() -> [String] {
        ["Let's build your setup."]
    }

    static func referralAcknowledgment(skipped: Bool, code: String) -> [String] {
        if skipped || code.isEmpty {
            return ["No worries.", "We can keep going."]
        }
        return ["Nice — you’re both in.", "You each got +2 weekly speaks."]
    }

    static func answerSummary(for beat: ConversationBeat, answers: OnboardingAnswers) -> [String] {
        switch beat {
        case .greeting:
            return []
        case .name:
            let name = answers.trimmedDisplayName
            return name.isEmpty ? [] : [name]
        case .auth:
            switch answers.authChoice {
            case .apple: return ["Continued with Apple"]
            case .google: return ["Continued with Google"]
            case .phone: return ["Continued with phone"]
            case .guest: return ["Continuing as guest"]
            }
        case .priorities:
            let parts = OnboardingPriority.allCases.filter { answers.priorities.contains($0) }.map(\.displayName)
            return parts.isEmpty ? [] : [parts.joined(separator: " · ")]
        case .age:
            return ["\(answers.age)"]
        case .personality:
            let parts = OnboardingPersonalityTag.allCases.filter { answers.personality.contains($0) }.map(\.displayName)
            return parts.isEmpty ? [] : [parts.joined(separator: " · ")]
        case .goals:
            let parts = UserGoal.allCases.filter { answers.goals.contains($0) }.map(\.displayName)
            return parts.isEmpty ? [] : [parts.joined(separator: " · ")]
        case .level:
            return [answers.level.displayName]
        case .review:
            return []
        case .referral:
            if answers.didSkipReferralCode || answers.trimmedReferralCode.isEmpty {
                return ["Skipped"]
            }
            return [answers.trimmedReferralCode]
        }
    }

    static func acknowledgment(for beat: ConversationBeat, answers: OnboardingAnswers) -> [String] {
        switch beat {
        case .greeting: return []
        case .name: return nameAcknowledgment(answers.displayName)
        case .auth: return authAcknowledgment(answers.authChoice)
        case .priorities: return prioritiesAcknowledgment(answers.priorities)
        case .age: return ageAcknowledgment(answers.age)
        case .personality: return personalityAcknowledgment(answers.personality)
        case .goals: return goalsAcknowledgment(answers.goals)
        case .level: return levelAcknowledgment(answers.level)
        case .review:
            return RemoteConfigService.shared.isReferralRewardsEnabled
                ? ["Almost there."]
                : reviewAcknowledgment()
        case .referral:
            return referralAcknowledgment(
                skipped: answers.didSkipReferralCode,
                code: answers.trimmedReferralCode
            )
        }
    }

    private static func joinDisplay(_ parts: [String]) -> String {
        switch parts.count {
        case 0: return ""
        case 1: return parts[0]
        case 2: return "\(parts[0]) and \(parts[1])"
        default:
            let head = parts.dropLast().joined(separator: ", ")
            return "\(head), and \(parts.last!)"
        }
    }
}

/// Append-only conversation row — same identity for the whole beat (live → complete).
/// Stable `id` keeps the prompt mounted when a turn finishes.
struct ConversationEntry: Identifiable, Equatable {
    let id: UUID
    let beat: ConversationBeat
    var answerLines: [String]
    var acknowledgment: [String]
    var isComplete: Bool

    init(beat: ConversationBeat) {
        self.id = UUID()
        self.beat = beat
        self.answerLines = []
        self.acknowledgment = []
        self.isComplete = false
    }
}

/// Legacy alias — prefer `ConversationEntry`.
typealias ConversationTurn = ConversationEntry
