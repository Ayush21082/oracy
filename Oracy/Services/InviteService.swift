import Foundation
import UIKit
import Supabase

enum InviteRedeemResult: Equatable {
    case success
    case invalidCode
    case selfRedeem
    case alreadyRedeemed
    case notFound
    case notSignedIn
    case failed(String)

    var isSuccess: Bool { self == .success }

    var userMessage: String {
        switch self {
        case .success:
            return RemoteConfigService.shared.isInviteOnlyEnabled
                ? "You’re in — you both got +2 weekly speaks."
                : "You both got +2 weekly speaks. Your friend can claim more as people join."
        case .invalidCode:
            return "That code didn’t work. Check it and try again."
        case .selfRedeem:
            return "That’s your own code — share it with a friend instead."
        case .alreadyRedeemed:
            return "You’ve already used a referral code on this account."
        case .notFound:
            return "That code didn’t work. Check with your friend and try again."
        case .notSignedIn:
            return "Sign in first, then enter the code."
        case .failed(let message):
            return message
        }
    }
}

/// Invite-only unlock + referral codes + milestone reward state.
@MainActor
@Observable
final class InviteService {
    static let shared = InviteService()

    private let unlockedKey = "invite.unlocked"
    private let redeemedCodeKey = "invite.redeemedCode"
    private let pendingAttributionKey = "invite.pendingAttribution"
    private let cachedCodeKey = "invite.myReferralCode"

    private(set) var redeemedCode: String?
    private(set) var rewardState = ReferralRewardState.empty
    private(set) var isLoadingRewards = false
    private(set) var lastErrorMessage: String?
    private var boundUserId: UUID?

    private init() {
        redeemedCode = UserDefaults.standard.string(forKey: redeemedCodeKey)
        bind(to: AuthService.shared.userId)
    }

    var hasUnlockedInvite: Bool {
        UserDefaults.standard.bool(forKey: unlockedKey)
    }

    /// When remote invite-only is on and this device hasn't redeemed a code.
    var needsInviteGate: Bool {
        guard RemoteConfigService.shared.isInviteOnlyEnabled else { return false }
        if hasUnlockedInvite { return false }
        // Existing onboarded users stay in (persist unlock so the gate stays quiet).
        if AuthService.shared.profile?.onboardingCompleted == true {
            UserDefaults.standard.set(true, forKey: unlockedKey)
            return false
        }
        return true
    }

    var referralCount: Int { rewardState.count }

    /// Stable invite code for this user. Shows immediately from cache / a
    /// deterministic seed, then `refreshRewardState` writes that same code to
    /// Supabase so friends can actually redeem it.
    func referralCode(for userId: UUID?) -> String {
        if let confirmed = confirmedCode(for: userId) {
            return confirmed
        }

        if AppConfig.useMockBackend {
            let code = MockStore.shared.ensureReferralCode()
            cacheCode(code, for: userId)
            return code
        }

        guard let userId else { return "" }
        let code = Self.makeCode(from: userId.uuidString)
        cacheCode(code, for: userId)
        return code
    }

    /// After login / account switch: load this user's cache, persist any local
    /// code, and attribute a code entered before auth.
    func syncAfterAuthChange() async {
        bind(to: AuthService.shared.userId)
        await refreshRewardState()
        await retryPendingAttributionIfNeeded()
    }

    func resetSessionState() {
        boundUserId = nil
        rewardState = .empty
        lastErrorMessage = nil
        isLoadingRewards = false
    }

    func refreshRewardState() async {
        isLoadingRewards = true
        defer { isLoadingRewards = false }

        if AppConfig.useMockBackend {
            let state = MockStore.shared.referralRewardState()
            apply(state)
            SubscriptionService.shared.applyReferralGrants(
                bonusSessions: state.bonusSessions,
                proExpiresAt: state.proExpiresAt
            )
            return
        }

        guard let userId = AuthService.shared.userId else {
            rewardState = ReferralRewardState.empty
            return
        }

        bind(to: userId)
        _ = referralCode(for: userId)
        if let persisted = await persistPreferredCodeIfNeeded(for: userId) {
            cacheCode(persisted, for: userId)
        }

        do {
            let row = try await fetchRewardStateRow()

            let catalog = (row.milestones?.isEmpty == false)
                ? (row.milestones ?? [])
                : ReferralMilestoneCatalog.fallback

            let code = row.referralCode.isEmpty
                ? (rewardState.referralCode)
                : row.referralCode

            let state = ReferralRewardState(
                count: row.count,
                bonusSessions: row.bonusSessions,
                proExpiresAt: row.proExpiresAt,
                claimedMilestones: Set(row.claimedMilestones),
                referralCode: code,
                milestones: catalog
            )
            apply(state)
            SubscriptionService.shared.applyReferralGrants(
                bonusSessions: state.bonusSessions,
                proExpiresAt: state.proExpiresAt
            )
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func redeem(_ raw: String) async -> InviteRedeemResult {
        let code = Self.normalize(raw)
        guard code.count >= 6, code.count <= 10 else {
            AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "invalid_code"])
            return .invalidCode
        }

        // Only treat as self-redeem when we know *this* user's persisted code.
        // A device-wide leftover from another account used to block a real friend code.
        if let mine = confirmedCode(for: AuthService.shared.userId), code == mine {
            AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "self_redeem"])
            return .selfRedeem
        }

        if AppConfig.useMockBackend {
            do {
                try MockStore.shared.redeemReferralCode(code)
                markLocalUnlock(code)
                await AuthService.shared.fetchProfile()
                await refreshRewardState()
                AnalyticsService.shared.track(.inviteRedeemed, ["backend": "mock"])
                return .success
            } catch MockStore.MockRedeemError.selfRedeem {
                AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "self_redeem"])
                return .selfRedeem
            } catch MockStore.MockRedeemError.alreadyRedeemed {
                // Still unlock locally if they already attributed.
                markLocalUnlock(code)
                AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "already_redeemed"])
                return .alreadyRedeemed
            } catch MockStore.MockRedeemError.invalidCode {
                AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "invalid_code"])
                return .invalidCode
            } catch {
                AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "not_found"])
                return .notFound
            }
        }

        guard AuthService.shared.userId != nil else {
            // Invite-only gate may run before auth; unlock device locally and retry attribution later.
            markLocalUnlock(code)
            UserDefaults.standard.set(code, forKey: pendingAttributionKey)
            AnalyticsService.shared.track(.inviteRedeemed, ["deferred": "true"])
            return .success
        }

        do {
            struct Response: Decodable {
                let ok: Bool
                let error: String?
                let bonusSessions: Int?

                enum CodingKeys: String, CodingKey {
                    case ok
                    case error
                    case bonusSessions = "bonus_sessions"
                }
            }

            let response: Response = try await SupabaseManager.shared.client
                .rpc("redeem_referral_code", params: ["raw_code": code])
                .execute()
                .value

            guard response.ok else {
                let reason = response.error ?? "unknown"
                AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": reason])
                switch response.error {
                case "self_redeem": return .selfRedeem
                case "already_redeemed":
                    markLocalUnlock(code)
                    return .alreadyRedeemed
                case "invalid_code": return .invalidCode
                case "not_found": return .notFound
                default: return .failed(response.error ?? "Couldn’t redeem that code.")
                }
            }

            markLocalUnlock(code)
            UserDefaults.standard.removeObject(forKey: pendingAttributionKey)
            if let bonus = response.bonusSessions {
                SubscriptionService.shared.applyReferralGrants(
                    bonusSessions: bonus,
                    proExpiresAt: AuthService.shared.profile?.referralProExpiresAt
                )
            }
            await AuthService.shared.fetchProfile()
            await refreshRewardState()
            AnalyticsService.shared.track(.inviteRedeemed, ["code_len": String(code.count)])
            return .success
        } catch {
            AnalyticsService.shared.track(.inviteRedeemFailed, ["reason": "network"])
            return .failed(error.localizedDescription)
        }
    }

    @discardableResult
    func claimMilestone(_ milestone: ReferralMilestoneOffer) async -> Bool {
        if AppConfig.useMockBackend {
            do {
                let state = try MockStore.shared.claimReferralMilestone(milestone)
                apply(state)
                SubscriptionService.shared.applyReferralGrants(
                    bonusSessions: state.bonusSessions,
                    proExpiresAt: state.proExpiresAt
                )
                await AuthService.shared.fetchProfile()
                lastErrorMessage = nil
                AnalyticsService.shared.track(.referralMilestoneClaimed, [
                    "friends_required": String(milestone.friendsRequired),
                    "backend": "mock"
                ])
                return true
            } catch {
                lastErrorMessage = "Couldn’t claim that reward yet."
                AnalyticsService.shared.track(.referralMilestoneFailed, [
                    "friends_required": String(milestone.friendsRequired)
                ])
                return false
            }
        }

        guard AuthService.shared.userId != nil else {
            lastErrorMessage = "Sign in to claim rewards."
            AnalyticsService.shared.track(.referralMilestoneFailed, [
                "friends_required": String(milestone.friendsRequired),
                "reason": "not_signed_in"
            ])
            return false
        }

        do {
            struct Response: Decodable {
                let ok: Bool
                let error: String?
                let bonusSessions: Int?
                let proExpiresAt: Date?

                enum CodingKeys: String, CodingKey {
                    case ok
                    case error
                    case bonusSessions = "bonus_sessions"
                    case proExpiresAt = "pro_expires_at"
                }
            }

            let response: Response = try await SupabaseManager.shared.client
                .rpc("claim_referral_milestone", params: ["p_milestone": milestone.friendsRequired])
                .execute()
                .value

            guard response.ok else {
                lastErrorMessage = response.error ?? "Couldn’t claim that reward."
                AnalyticsService.shared.track(.referralMilestoneFailed, [
                    "friends_required": String(milestone.friendsRequired),
                    "reason": response.error ?? "unknown"
                ])
                return false
            }

            await AuthService.shared.fetchProfile()
            await refreshRewardState()
            AnalyticsService.shared.track(.referralMilestoneClaimed, [
                "friends_required": String(milestone.friendsRequired)
            ])
            return true
        } catch {
            lastErrorMessage = error.localizedDescription
            AnalyticsService.shared.track(.referralMilestoneFailed, [
                "friends_required": String(milestone.friendsRequired),
                "reason": "network"
            ])
            return false
        }
    }

    func clearUnlockForDebug() {
        UserDefaults.standard.removeObject(forKey: unlockedKey)
        UserDefaults.standard.removeObject(forKey: redeemedCodeKey)
        redeemedCode = nil
    }

    func shareMessage(inviterName: String, code: String, inviteOnly: Bool) -> String {
        if inviteOnly {
            return "You’re invited to Oracy by \(inviterName). Use invite code \(code) to get in — you both get +2 weekly speaks."
        }
        return "Join me on Oracy with code \(code). We both get +2 weekly speaks when you enter it."
    }

    /// Back-compat for existing call sites.
    func shareMessage(inviterName: String, code: String) -> String {
        shareMessage(
            inviterName: inviterName,
            code: code,
            inviteOnly: RemoteConfigService.shared.isInviteOnlyEnabled
        )
    }

    // MARK: - Private

    private func apply(_ state: ReferralRewardState) {
        rewardState = state
        if !state.referralCode.isEmpty {
            cacheCode(state.referralCode, for: AuthService.shared.userId)
        }
    }

    private func bind(to userId: UUID?) {
        if boundUserId != userId {
            boundUserId = userId
            rewardState = .empty
        }
        hydrateCachedCode(for: userId)
    }

    private func confirmedCode(for userId: UUID?) -> String? {
        if let userId,
           boundUserId == userId,
           AuthService.shared.userId == userId,
           !rewardState.referralCode.isEmpty,
           rewardState.referralCode.count >= 6 {
            return Self.normalize(rewardState.referralCode)
        }
        if let cached = scopedCachedCode(for: userId), cached.count >= 6 {
            return cached
        }
        if let userId,
           AuthService.shared.userId == userId,
           let fromProfile = AuthService.shared.profile?.referralCode,
           fromProfile.count >= 6 {
            return Self.normalize(fromProfile)
        }
        return nil
    }

    private func scopedCachedCode(for userId: UUID?) -> String? {
        guard let userId else { return nil }
        guard let cached = UserDefaults.standard.string(forKey: cacheKey(for: userId)),
              cached.count >= 6 else { return nil }
        return Self.normalize(cached)
    }

    private func cacheKey(for userId: UUID) -> String {
        "\(cachedCodeKey).\(userId.uuidString)"
    }

    private func hydrateCachedCode(for userId: UUID?) {
        guard let cached = scopedCachedCode(for: userId) else { return }
        if rewardState.referralCode != cached {
            rewardState.referralCode = cached
        }
    }

    private func cacheCode(_ code: String, for userId: UUID?) {
        let normalized = Self.normalize(code)
        guard (6...10).contains(normalized.count) else { return }
        if let userId {
            UserDefaults.standard.set(normalized, forKey: cacheKey(for: userId))
        }
        UserDefaults.standard.removeObject(forKey: cachedCodeKey)
        if rewardState.referralCode != normalized {
            rewardState.referralCode = normalized
        }
    }

    /// Allocate / persist this user's code. Prefers the code already shown in the UI
    /// so a friend can redeem what they were given.
    @discardableResult
    private func persistPreferredCodeIfNeeded(for userId: UUID) async -> String? {
        let preferred = scopedCachedCode(for: userId)
            ?? UserDefaults.standard.string(forKey: cachedCodeKey).map(Self.normalize)
        let generatedHere = Self.makeCode(from: userId.uuidString)
        let matchesProfile = AuthService.shared.profile?.referralCode.map(Self.normalize) == preferred
        let adopt = preferred.flatMap { code -> String? in
            guard (6...10).contains(code.count), code == generatedHere || matchesProfile else {
                return nil
            }
            return code
        }

        do {
            let code: String
            if let adopt {
                code = try await fetchEnsuredCode(preferred: adopt)
            } else {
                code = try await fetchEnsuredCode(preferred: nil)
            }
            UserDefaults.standard.removeObject(forKey: cachedCodeKey)
            let cleaned = Self.normalize(code)
            return (6...10).contains(cleaned.count) ? cleaned : nil
        } catch {
            UserDefaults.standard.removeObject(forKey: cachedCodeKey)
            return nil
        }
    }

    private func fetchEnsuredCode(preferred: String?) async throws -> String {
        if let preferred {
            return try await decodeRPCText(
                SupabaseManager.shared.client
                    .rpc("ensure_my_referral_code", params: ["preferred": preferred])
                    .execute()
                    .data
            )
        }
        return try await decodeRPCText(
            SupabaseManager.shared.client
                .rpc("ensure_my_referral_code")
                .execute()
                .data
        )
    }

    private func decodeRPCText(_ data: Data) throws -> String {
        if let text = try? JSONDecoder().decode(String.self, from: data) {
            return text
        }
        if let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n"))
            .replacingOccurrences(of: "\"", with: ""),
           !text.isEmpty {
            return text
        }
        throw InviteRPCError.unreadable
    }

    private func fetchRewardStateRow() async throws -> RewardStateRow {
        let data = try await SupabaseManager.shared.client
            .rpc("get_referral_reward_state")
            .execute()
            .data
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let row = try? decoder.decode(RewardStateRow.self, from: data) {
            return row
        }
        if let wrapped = try? decoder.decode(String.self, from: data),
           let inner = wrapped.data(using: .utf8),
           let row = try? decoder.decode(RewardStateRow.self, from: inner) {
            return row
        }
        return try decoder.decode(RewardStateRow.self, from: data)
    }

    private func retryPendingAttributionIfNeeded() async {
        guard !AppConfig.useMockBackend else { return }
        guard AuthService.shared.userId != nil else { return }
        let pending = UserDefaults.standard.string(forKey: pendingAttributionKey)
            ?? (redeemedCode.flatMap { AuthService.shared.profile?.referredBy == nil ? $0 : nil })
        guard let pending, pending.count >= 6 else { return }
        if let mine = confirmedCode(for: AuthService.shared.userId), mine == Self.normalize(pending) {
            UserDefaults.standard.removeObject(forKey: pendingAttributionKey)
            return
        }
        let result = await redeem(pending)
        if result == .success || result == .alreadyRedeemed || result == .selfRedeem {
            UserDefaults.standard.removeObject(forKey: pendingAttributionKey)
        }
    }

    private func markLocalUnlock(_ code: String) {
        UserDefaults.standard.set(true, forKey: unlockedKey)
        UserDefaults.standard.set(code, forKey: redeemedCodeKey)
        redeemedCode = code
    }

    /// Pulls an invite code out of a typed field or a share message.
    nonisolated static func parseReferralCode(_ raw: String) -> String {
        parseReferralCodeImpl(raw)
    }

    private static func normalize(_ raw: String) -> String {
        parseReferralCodeImpl(raw)
    }

    /// Prefer `code ABCDEFGH` from a share message over the first 10 letters
    /// of "Join me on Oracy…", which used to become `JOINMEONOR`.
    private nonisolated static func parseReferralCodeImpl(_ raw: String) -> String {
        let upper = raw.uppercased()
        let ns = upper as NSString
        if let regex = try? NSRegularExpression(
            pattern: #"(?:INVITE\s+)?CODE\s+([A-Z0-9]{6,10})"#,
            options: []
        ),
           let match = regex.firstMatch(in: upper, options: [], range: NSRange(location: 0, length: ns.length)),
           match.numberOfRanges > 1 {
            return ns.substring(with: match.range(at: 1))
        }

        let alphabet = Set("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")
        let tokens = upper.split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let candidates = tokens.filter { (6...10).contains($0.count) && Set($0).isSubset(of: alphabet) }
        if let eight = candidates.first(where: { $0.count == 8 }) {
            return eight
        }
        if let any = candidates.first {
            return any
        }

        let compact = upper.filter { $0.isLetter || $0.isNumber }
        if (6...10).contains(compact.count) {
            return compact
        }
        return compact
    }

    /// Short, readable code from a stable seed (no ambiguous 0/O/1/I).
    private static func makeCode(from seed: String) -> String {
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
}

private enum InviteRPCError: Error {
    case unreadable
}

private struct RewardStateRow: Decodable {
    var count: Int
    var bonusSessions: Int
    var proExpiresAt: Date?
    var claimedMilestones: [Int]
    var referralCode: String
    var milestones: [ReferralMilestoneOffer]?

    enum CodingKeys: String, CodingKey {
        case count
        case bonusSessions = "bonus_sessions"
        case proExpiresAt = "pro_expires_at"
        case claimedMilestones = "claimed_milestones"
        case referralCode = "referral_code"
        case milestones
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        count = (try? c.decode(Int.self, forKey: .count)) ?? 0
        bonusSessions = (try? c.decode(Int.self, forKey: .bonusSessions)) ?? 0
        proExpiresAt = try? c.decode(Date.self, forKey: .proExpiresAt)
        if let ints = try? c.decode([Int].self, forKey: .claimedMilestones) {
            claimedMilestones = ints
        } else {
            claimedMilestones = []
        }
        referralCode = (try? c.decode(String.self, forKey: .referralCode)) ?? ""
        milestones = try? c.decode([ReferralMilestoneOffer].self, forKey: .milestones)
    }
}
