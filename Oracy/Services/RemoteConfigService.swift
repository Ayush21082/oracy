import Foundation
import Supabase

/// Fetches feature flags from Supabase `remote_config`. Defaults keep membership OFF.
@MainActor
@Observable
final class RemoteConfigService {
    static let shared = RemoteConfigService()

    static let membershipPlanKey = "membership_plan_enabled"
    static let inviteOnlyKey = "invite_only_enabled"
    /// When true, show RevenueCat dashboard `PaywallView`. When false (default), use Oracy branded UI + offerings.
    static let useRevenueCatPaywallKey = "use_revenuecat_paywall"
    /// When true, show referral rewards (Profile, Settings redeem, onboarding optional code).
    static let referralRewardsKey = "referral_rewards_enabled"
    /// When true, onboarding offers phone OTP login.
    static let phoneAuthKey = "phone_auth_enabled"
    /// When true, onboarding offers Google Sign-In.
    static let googleAuthKey = "google_auth_enabled"

    /// Master switch for Oracy Pro / RevenueCat. Default: disabled.
    private(set) var isMembershipPlanEnabled = false
    /// When true, devices must redeem an invite code before using the app.
    private(set) var isInviteOnlyEnabled = false
    /// Prefer RevenueCat visual Paywall over in-app branded paywall.
    private(set) var useRevenueCatPaywall = false
    /// Show referral reward system + optional onboarding code step. Default: enabled.
    private(set) var isReferralRewardsEnabled = true
    /// Show phone number OTP in onboarding. Default: enabled.
    private(set) var isPhoneAuthEnabled = true
    /// Show Google Sign-In in onboarding. Default: hidden (matches remote_config seed).
    private(set) var isGoogleAuthEnabled = false
    private(set) var lastFetchedAt: Date?
    private(set) var isLoading = false

    private init() {}

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        var membership = false
        var inviteOnly = false
        var rcPaywall = false
        // Rewards on by default so mock / missing row still shows the system.
        var referralRewards = true
        var phoneAuth = true
        var googleAuth = false

        if AppConfig.useMockBackend {
            membership = false
            inviteOnly = false
            rcPaywall = false
            referralRewards = true
            phoneAuth = true
            googleAuth = true
        } else {
            do {
                struct Row: Decodable {
                    let key: String
                    let value: FlexibleBool
                }

                struct FlexibleBool: Decodable {
                    let value: Bool

                    init(from decoder: Decoder) throws {
                        let container = try decoder.singleValueContainer()
                        if let b = try? container.decode(Bool.self) {
                            value = b
                            return
                        }
                        if let s = try? container.decode(String.self) {
                            value = ["true", "1", "yes"].contains(s.lowercased())
                            return
                        }
                        if let i = try? container.decode(Int.self) {
                            value = i != 0
                            return
                        }
                        value = false
                    }
                }

                let keys = [
                    Self.membershipPlanKey,
                    Self.inviteOnlyKey,
                    Self.useRevenueCatPaywallKey,
                    Self.referralRewardsKey,
                    Self.phoneAuthKey,
                    Self.googleAuthKey
                ]
                let rows: [Row] = try await SupabaseManager.shared.client
                    .from("remote_config")
                    .select("key, value")
                    .in("key", values: keys)
                    .execute()
                    .value

                let map = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value.value) })
                membership = map[Self.membershipPlanKey] ?? false
                inviteOnly = map[Self.inviteOnlyKey] ?? false
                rcPaywall = map[Self.useRevenueCatPaywallKey] ?? false
                referralRewards = map[Self.referralRewardsKey] ?? true
                phoneAuth = map[Self.phoneAuthKey] ?? true
                googleAuth = map[Self.googleAuthKey] ?? false
            } catch {
                membership = false
                inviteOnly = false
                rcPaywall = false
                referralRewards = true
                phoneAuth = true
                googleAuth = false
            }
        }

        #if DEBUG
        if let forced = debugForceMembershipPlan {
            membership = forced
        }
        if let forced = debugForceInviteOnly {
            inviteOnly = forced
        }
        if let forced = debugForceRevenueCatPaywall {
            rcPaywall = forced
        }
        if let forced = debugForceReferralRewards {
            referralRewards = forced
        }
        if let forced = debugForcePhoneAuth {
            phoneAuth = forced
        }
        if let forced = debugForceGoogleAuth {
            googleAuth = forced
        }
        #endif

        isMembershipPlanEnabled = membership
        isInviteOnlyEnabled = inviteOnly
        useRevenueCatPaywall = rcPaywall
        isReferralRewardsEnabled = referralRewards
        isPhoneAuthEnabled = phoneAuth
        isGoogleAuthEnabled = googleAuth
        lastFetchedAt = Date()
    }

    #if DEBUG
    /// `nil` clears override and re-fetches from backend.
    func setDebugForceMembershipPlan(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: "debug.forceMembershipPlan")
            isMembershipPlanEnabled = enabled
        } else {
            UserDefaults.standard.removeObject(forKey: "debug.forceMembershipPlan")
            Task { await refresh() }
        }
    }

    func setDebugForceInviteOnly(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: "debug.forceInviteOnly")
            isInviteOnlyEnabled = enabled
        } else {
            UserDefaults.standard.removeObject(forKey: "debug.forceInviteOnly")
            Task { await refresh() }
        }
    }

    func setDebugForceRevenueCatPaywall(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: "debug.forceRevenueCatPaywall")
            useRevenueCatPaywall = enabled
        } else {
            UserDefaults.standard.removeObject(forKey: "debug.forceRevenueCatPaywall")
            Task { await refresh() }
        }
    }

    func setDebugForceReferralRewards(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: "debug.forceReferralRewards")
            isReferralRewardsEnabled = enabled
        } else {
            UserDefaults.standard.removeObject(forKey: "debug.forceReferralRewards")
            Task { await refresh() }
        }
    }

    func setDebugForcePhoneAuth(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: "debug.forcePhoneAuth")
            isPhoneAuthEnabled = enabled
        } else {
            UserDefaults.standard.removeObject(forKey: "debug.forcePhoneAuth")
            Task { await refresh() }
        }
    }

    func setDebugForceGoogleAuth(_ enabled: Bool?) {
        if let enabled {
            UserDefaults.standard.set(enabled, forKey: "debug.forceGoogleAuth")
            isGoogleAuthEnabled = enabled
        } else {
            UserDefaults.standard.removeObject(forKey: "debug.forceGoogleAuth")
            Task { await refresh() }
        }
    }

    var debugForceMembershipPlan: Bool? {
        guard UserDefaults.standard.object(forKey: "debug.forceMembershipPlan") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.forceMembershipPlan")
    }

    var debugForceInviteOnly: Bool? {
        guard UserDefaults.standard.object(forKey: "debug.forceInviteOnly") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.forceInviteOnly")
    }

    var debugForceRevenueCatPaywall: Bool? {
        guard UserDefaults.standard.object(forKey: "debug.forceRevenueCatPaywall") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.forceRevenueCatPaywall")
    }

    var debugForceReferralRewards: Bool? {
        guard UserDefaults.standard.object(forKey: "debug.forceReferralRewards") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.forceReferralRewards")
    }

    var debugForcePhoneAuth: Bool? {
        guard UserDefaults.standard.object(forKey: "debug.forcePhoneAuth") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.forcePhoneAuth")
    }

    var debugForceGoogleAuth: Bool? {
        guard UserDefaults.standard.object(forKey: "debug.forceGoogleAuth") != nil else { return nil }
        return UserDefaults.standard.bool(forKey: "debug.forceGoogleAuth")
    }
    #endif
}
