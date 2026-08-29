import Foundation

/// One offer from the backend `referral_milestones` catalog.
struct ReferralMilestoneOffer: Identifiable, Equatable, Hashable, Codable {
    let friendsRequired: Int
    let rewardKey: String
    let bonusWeeklySessions: Int
    let proDays: Int
    let title: String
    let hook: String
    let sortOrder: Int

    var id: Int { friendsRequired }

    var friendsLabel: String {
        friendsRequired == 1 ? "1 friend" : "\(friendsRequired) friends"
    }

    enum CodingKeys: String, CodingKey {
        case friendsRequired = "friends_required"
        case rewardKey = "reward_key"
        case bonusWeeklySessions = "bonus_weekly_sessions"
        case proDays = "pro_days"
        case title
        case hook
        case sortOrder = "sort_order"
    }
}

enum ReferralMilestoneStatus: Equatable {
    case locked(remaining: Int)
    case claimable
    case claimed
}

struct ReferralRewardState: Equatable {
    var count: Int
    var bonusSessions: Int
    var proExpiresAt: Date?
    var claimedMilestones: Set<Int>
    var referralCode: String
    /// Backend catalog (sorted). Empty until refreshed / mock seeded.
    var milestones: [ReferralMilestoneOffer]

    static let empty = ReferralRewardState(
        count: 0,
        bonusSessions: 0,
        proExpiresAt: nil,
        claimedMilestones: [],
        referralCode: "",
        milestones: ReferralMilestoneCatalog.fallback
    )

    var hasActiveReferralPro: Bool {
        guard let proExpiresAt else { return false }
        return proExpiresAt > Date()
    }

    func status(for milestone: ReferralMilestoneOffer) -> ReferralMilestoneStatus {
        if claimedMilestones.contains(milestone.friendsRequired) {
            return .claimed
        }
        if count >= milestone.friendsRequired {
            return .claimable
        }
        return .locked(remaining: milestone.friendsRequired - count)
    }

    var nextMilestone: ReferralMilestoneOffer? {
        milestones.first { $0.friendsRequired > count }
    }

    var nextTeaser: String? {
        guard let next = nextMilestone else {
            return !milestones.isEmpty && claimedMilestones.count >= milestones.count
                ? "Every milestone claimed — you’re a legend."
                : nil
        }
        let remaining = next.friendsRequired - count
        let friendWord = remaining == 1 ? "friend" : "friends"
        return "\(remaining) more \(friendWord) → \(next.title)"
    }
}

/// Fallback catalog for mock backend / offline UI before first fetch.
enum ReferralMilestoneCatalog {
    static let fallback: [ReferralMilestoneOffer] = [
        .init(friendsRequired: 1, rewardKey: "bonus_weekly_2", bonusWeeklySessions: 2, proDays: 0,
              title: "+2 weekly speaks", hook: "One friend in — more practice room this week.", sortOrder: 10),
        .init(friendsRequired: 3, rewardKey: "pro_days_7", bonusWeeklySessions: 0, proDays: 7,
              title: "7 days of Pro", hook: "Tiny squad unlock. Taste unlimited speaking.", sortOrder: 20),
        .init(friendsRequired: 5, rewardKey: "pro_days_30", bonusWeeklySessions: 0, proDays: 30,
              title: "30 days of Pro", hook: "Your hero milestone. A full month on Pro.", sortOrder: 30),
        .init(friendsRequired: 10, rewardKey: "bonus_weekly_3", bonusWeeklySessions: 3, proDays: 0,
              title: "+3 weekly speaks", hook: "Stack more free sessions every week.", sortOrder: 40),
        .init(friendsRequired: 20, rewardKey: "pro_days_90", bonusWeeklySessions: 0, proDays: 90,
              title: "90 days of Pro", hook: "Inner circle. Three months of Pro.", sortOrder: 50),
        .init(friendsRequired: 50, rewardKey: "pro_days_365", bonusWeeklySessions: 0, proDays: 365,
              title: "1 year of Pro", hook: "Legendary share goal. A whole year.", sortOrder: 60),
        .init(friendsRequired: 100, rewardKey: "pro_days_365_bonus_weekly_5", bonusWeeklySessions: 5, proDays: 365,
              title: "1 year Pro + 5 speaks", hook: "Capstone — year of Pro plus a bigger weekly limit.", sortOrder: 70)
    ]
}
