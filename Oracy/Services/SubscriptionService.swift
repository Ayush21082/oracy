import Foundation
import SwiftUI
import RevenueCat
import Supabase

/// Membership state for UI (avatar ring, profile chip, paywall).
enum MembershipStatus: Equatable {
    case free
    case trial(endsAt: Date?)
    case pro

    var isEntitled: Bool {
        switch self {
        case .free: return false
        case .trial, .pro: return true
        }
    }
}

@MainActor
@Observable
final class SubscriptionService {
    static let shared = SubscriptionService()

    private(set) var membership: MembershipStatus = .free
    private(set) var customerInfo: CustomerInfo?
    private(set) var currentOffering: Offering?
    private(set) var monthlyPackage: Package?
    private(set) var annualPackage: Package?
    private(set) var isEligibleForTrial = true
    private(set) var weeklyCompletedSessions = 0
    private(set) var isLoadingOfferings = false
    private(set) var isPurchasing = false
    /// Permanent weekly speak bonus from referral milestones.
    private(set) var referralBonusWeeklySessions = 0
    /// App-local Pro window from referral claims (independent of RevenueCat).
    private(set) var referralProExpiresAt: Date?
    var lastErrorMessage: String?

    private var configured = false
    private var customerInfoTask: Task<Void, Never>?

    /// After account deletion, ignore App Store receipt entitlements for guests until they
    /// purchase again, restore explicitly, or link Apple/Google.
    private var blockReceiptEntitlements: Bool {
        get { UserDefaults.standard.bool(forKey: "subscriptions.blockReceiptEntitlements") }
        set { UserDefaults.standard.set(newValue, forKey: "subscriptions.blockReceiptEntitlements") }
    }

    private var debugForcePro: Bool {
        get { UserDefaults.standard.bool(forKey: "debug.forcePro") }
        set { UserDefaults.standard.set(newValue, forKey: "debug.forcePro") }
    }

    private var debugForceTrial: Bool {
        get { UserDefaults.standard.bool(forKey: "debug.forceTrial") }
        set { UserDefaults.standard.set(newValue, forKey: "debug.forceTrial") }
    }

    var isPro: Bool {
        membership.isEntitled || hasActiveReferralPro
    }

    /// Pro entitlement only when remote config enables membership plans.
    var isProActive: Bool {
        RemoteConfigService.shared.isMembershipPlanEnabled && isPro
    }

    var isMembershipPlanEnabled: Bool {
        RemoteConfigService.shared.isMembershipPlanEnabled
    }

    /// Membership is on and the user still needs Pro (free tier / soft gate).
    var needsPro: Bool {
        isMembershipPlanEnabled && !isProActive
    }

    var isInTrial: Bool {
        if case .trial = membership { return true }
        return false
    }

    var hasActiveReferralPro: Bool {
        guard let referralProExpiresAt else { return false }
        return referralProExpiresAt > Date()
    }

    var weeklySessionLimit: Int {
        AppConfig.freeWeeklySessionLimit + max(0, referralBonusWeeklySessions)
    }

    var weeklyFreeRemaining: Int {
        max(0, weeklySessionLimit - weeklyCompletedSessions)
    }

    var canStartSpeaking: Bool {
        guard RemoteConfigService.shared.isMembershipPlanEnabled else { return true }
        return isPro || weeklyFreeRemaining > 0
    }

    /// Active `oracy_pro` entitlement from the latest CustomerInfo, if any.
    var proEntitlement: EntitlementInfo? {
        customerInfo?.entitlements[AppConfig.proEntitlementID]
    }

    /// Sync referral grants from profile / InviteService into speak limits and Pro overlay.
    func applyReferralGrants(bonusSessions: Int, proExpiresAt: Date?) {
        referralBonusWeeklySessions = max(0, bonusSessions)
        referralProExpiresAt = proExpiresAt
        // Re-evaluate free→trial overlay when RC Pro is inactive but referral Pro is live.
        if !membership.isEntitled, hasActiveReferralPro {
            membership = .trial(endsAt: proExpiresAt)
        }
    }

    func applyReferralGrants(from profile: Profile?) {
        guard let profile else { return }
        applyReferralGrants(
            bonusSessions: profile.referralBonusWeeklySessions,
            proExpiresAt: profile.referralProExpiresAt
        )
    }

    private init() {}

    func configure() {
        guard !configured else { return }
        configured = true

        guard AppConfig.isRevenueCatConfigured else {
            refreshDebugMembership()
            return
        }

        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: AppConfig.revenueCatAPIKey)
        Purchases.shared.delegate = PurchasesDelegateBridge.shared

        customerInfoTask?.cancel()
        customerInfoTask = Task { [weak self] in
            for await info in Purchases.shared.customerInfoStream {
                guard let self, !Task.isCancelled else { return }
                self.apply(customerInfo: info)
            }
        }

        Task {
            await identifyWithAuthUserIfNeeded()
            await refresh()
        }
    }

    /// Alias RevenueCat app user id to the signed-in Oracy user (Supabase / mock UUID).
    /// Does **not** restore the App Store receipt — that only happens after linked login / purchase / Restore.
    func identifyWithAuthUserIfNeeded() async {
        guard AppConfig.isRevenueCatConfigured,
              let userId = AuthService.shared.userId else { return }

        let appUserID = userId.uuidString
        guard Purchases.shared.appUserID != appUserID else { return }

        do {
            let result = try await Purchases.shared.logIn(appUserID)
            apply(customerInfo: result.customerInfo)
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    /// Call after Apple/Google link so Pro bought as a guest attaches to the logged-in account.
    func refreshEntitlementsAfterLogin() async {
        guard AppConfig.isRevenueCatConfigured else {
            await refresh()
            return
        }
        // Linked account may reclaim a prior Apple purchase.
        blockReceiptEntitlements = false
        await identifyWithAuthUserIfNeeded()
        await syncPurchasesFromStore()
        await refreshWeeklyUsage()
        await loadOfferings()
    }

    /// Clears Pro locally and resets RevenueCat after the Oracy account is deleted.
    func resetAfterAccountDeletion() async {
        blockReceiptEntitlements = true
        membership = .free
        customerInfo = nil
        weeklyCompletedSessions = 0
        referralBonusWeeklySessions = 0
        referralProExpiresAt = nil
        lastErrorMessage = nil
        #if DEBUG
        debugForcePro = false
        debugForceTrial = false
        #endif

        guard AppConfig.isRevenueCatConfigured else { return }

        do {
            _ = try await Purchases.shared.logOut()
        } catch {
            // Already anonymous in RevenueCat — fine.
        }
        // Keep UI free even if the store receipt would still entitle an anonymous RC user.
        membership = .free
        customerInfo = nil
    }

    /// Attaches the current App Store receipt to the active RevenueCat app user.
    @discardableResult
    func syncPurchasesFromStore() async -> Bool {
        guard AppConfig.isRevenueCatConfigured else { return membership.isEntitled }
        do {
            let synced = try await Purchases.shared.syncPurchases()
            apply(customerInfo: synced)
            if membership.isEntitled { return true }

            let restored = try await Purchases.shared.restorePurchases()
            apply(customerInfo: restored)
            return membership.isEntitled
        } catch {
            lastErrorMessage = friendlyMessage(for: error)
            return false
        }
    }

    func refresh() async {
        await RemoteConfigService.shared.refresh()
        await refreshWeeklyUsage()

        guard RemoteConfigService.shared.isMembershipPlanEnabled else {
            return
        }

        guard AppConfig.isRevenueCatConfigured else {
            refreshDebugMembership()
            return
        }

        await identifyWithAuthUserIfNeeded()

        do {
            let info = try await Purchases.shared.customerInfo()
            apply(customerInfo: info)
        } catch {
            lastErrorMessage = friendlyMessage(for: error)
            refreshDebugMembership()
        }

        await loadOfferings()
    }

    func refreshWeeklyUsage() async {
        weeklyCompletedSessions = await Self.completedSessionsThisCalendarWeek()
    }

    func loadOfferings() async {
        guard AppConfig.isRevenueCatConfigured else { return }
        isLoadingOfferings = true
        defer { isLoadingOfferings = false }

        do {
            try await fetchAndApplyOfferings()
        } catch {
            // RC can briefly 404 during identity / cold start; one retry usually lands.
            do {
                try await Task.sleep(for: .milliseconds(500))
                try await fetchAndApplyOfferings()
            } catch {
                lastErrorMessage = friendlyMessage(for: error)
            }
        }
    }

    private func fetchAndApplyOfferings() async throws {
        let offerings = try await Purchases.shared.offerings()
        let current = offerings.current
        currentOffering = current
        monthlyPackage = current?.monthly ?? current?.availablePackages.first {
            $0.packageType == .monthly
        }
        annualPackage = current?.annual ?? current?.availablePackages.first {
            $0.packageType == .annual
        }
        // Clear stale errors from an earlier failed attempt once products are available.
        lastErrorMessage = nil

        var productIDs: [String] = []
        if let monthlyPackage { productIDs.append(monthlyPackage.storeProduct.productIdentifier) }
        if let annualPackage { productIDs.append(annualPackage.storeProduct.productIdentifier) }

        if !productIDs.isEmpty {
            let eligibility = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: productIDs)
            isEligibleForTrial = productIDs.contains { id in
                eligibility[id]?.status == .eligible
            }
        }
    }

    /// Apply CustomerInfo from Paywall / Customer Center / purchases.
    func applyCustomerInfo(_ info: CustomerInfo) {
        apply(customerInfo: info)
    }

    @discardableResult
    func purchase(_ package: Package?) async -> Bool {
        #if DEBUG
        if !AppConfig.isRevenueCatConfigured {
            membership = isEligibleForTrial
                ? .trial(endsAt: Calendar.current.date(byAdding: .day, value: 7, to: Date()))
                : .pro
            debugForcePro = true
            debugForceTrial = isEligibleForTrial
            Haptics.success()
            return true
        }
        #else
        guard AppConfig.isRevenueCatConfigured else {
            lastErrorMessage = "Subscriptions aren’t configured yet."
            return false
        }
        #endif

        guard let package else {
            lastErrorMessage = "No subscription package available. Check your RevenueCat offering."
            return false
        }

        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }

        AnalyticsService.shared.track(.purchaseStarted, [
            "product_id": package.storeProduct.productIdentifier
        ])

        do {
            let result = try await Purchases.shared.purchase(package: package)
            if result.userCancelled {
                AnalyticsService.shared.track(.purchaseCancelled, [
                    "product_id": package.storeProduct.productIdentifier
                ])
                return false
            }
            blockReceiptEntitlements = false
            apply(customerInfo: result.customerInfo)
            Haptics.success()
            let entitled = membership.isEntitled
            AnalyticsService.shared.track(
                entitled ? .purchaseSucceeded : .purchaseFailed,
                [
                    "product_id": package.storeProduct.productIdentifier,
                    "entitled": entitled ? "true" : "false"
                ]
            )
            return entitled
        } catch {
            lastErrorMessage = friendlyMessage(for: error)
            Haptics.warning()
            AnalyticsService.shared.track(.purchaseFailed, [
                "product_id": package.storeProduct.productIdentifier,
                "reason": String(error.localizedDescription.prefix(120))
            ])
            return false
        }
    }

    @discardableResult
    func purchaseSelectedPlan(isAnnual: Bool) async -> Bool {
        let package = isAnnual ? annualPackage : monthlyPackage
        return await purchase(package)
    }

    @discardableResult
    func restore() async -> Bool {
        guard AppConfig.isRevenueCatConfigured else {
            #if DEBUG
            refreshDebugMembership()
            return isPro
            #else
            lastErrorMessage = "Subscriptions aren’t configured yet."
            return false
            #endif
        }

        isPurchasing = true
        lastErrorMessage = nil
        defer { isPurchasing = false }

        do {
            blockReceiptEntitlements = false
            let info = try await Purchases.shared.restorePurchases()
            apply(customerInfo: info)
            if membership.isEntitled {
                Haptics.success()
                AnalyticsService.shared.track(.restoreSucceeded)
            } else {
                lastErrorMessage = "No active Oracy Pro subscription found for this Apple ID."
                AnalyticsService.shared.track(.restoreFailed, ["reason": "none_found"])
            }
            return membership.isEntitled
        } catch {
            lastErrorMessage = friendlyMessage(for: error)
            Haptics.warning()
            AnalyticsService.shared.track(.restoreFailed, [
                "reason": String(error.localizedDescription.prefix(120))
            ])
            return false
        }
    }

    func manageSubscriptionsURL() -> URL? {
        URL(string: "https://apps.apple.com/account/subscriptions")
    }

    #if DEBUG
    func setDebugForcePro(_ on: Bool) {
        debugForcePro = on
        if on { debugForceTrial = false }
        refreshDebugMembership()
    }

    func setDebugForceTrial(_ on: Bool) {
        debugForceTrial = on
        if on { debugForcePro = false }
        refreshDebugMembership()
    }

    var debugForceProEnabled: Bool { debugForcePro }
    var debugForceTrialEnabled: Bool { debugForceTrial }
    #endif

    // MARK: - Private

    private func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let entitlement = customerInfo.entitlements[AppConfig.proEntitlementID]
        guard let entitlement, entitlement.isActive else {
            if hasActiveReferralPro {
                membership = .trial(endsAt: referralProExpiresAt)
            } else {
                membership = .free
                refreshDebugMembership()
            }
            return
        }

        // After delete-account, keep guests free even if the Apple receipt is still active.
        // Linked accounts, new purchases, and explicit Restore clear the block.
        if blockReceiptEntitlements && !AuthService.shared.isLoggedIn {
            if hasActiveReferralPro {
                membership = .trial(endsAt: referralProExpiresAt)
            } else {
                membership = .free
            }
            return
        }

        if entitlement.periodType == .trial {
            membership = .trial(endsAt: entitlement.expirationDate)
        } else {
            membership = .pro
        }
    }

    private func refreshDebugMembership() {
        #if DEBUG
        if debugForceTrial {
            membership = .trial(endsAt: Calendar.current.date(byAdding: .day, value: 5, to: Date()))
            return
        }
        if debugForcePro {
            membership = .pro
            return
        }
        #endif
        if hasActiveReferralPro {
            membership = .trial(endsAt: referralProExpiresAt)
            return
        }
        if !AppConfig.isRevenueCatConfigured {
            membership = .free
        }
    }

    private func friendlyMessage(for error: Error) -> String {
        if let rcError = error as? RevenueCat.ErrorCode {
            switch rcError {
            case .purchaseCancelledError:
                return "Purchase canceled."
            case .networkError:
                return "Network issue. Check your connection and try again."
            case .storeProblemError:
                return "App Store had a problem. Please try again in a moment."
            case .purchaseNotAllowedError:
                return "Purchases aren’t allowed on this device."
            case .productNotAvailableForPurchaseError:
                return "This product isn’t available right now."
            default:
                break
            }
        }
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("404")
            || raw.localizedCaseInsensitiveContains("not found") {
            return "Couldn’t load plans right now. Please try again."
        }
        return raw
    }

    private static func completedSessionsThisCalendarWeek() async -> Int {
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: Date())?.start
            ?? calendar.startOfDay(for: Date())

        if AppConfig.useMockBackend {
            return MockStore.shared.sessions.filter { session in
                guard session.status == "completed",
                      let created = session.createdAt else { return false }
                return created >= weekStart
            }.count
        }

        guard let userId = AuthService.shared.userId else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        struct Row: Decodable {
            let createdAt: Date?
            enum CodingKeys: String, CodingKey { case createdAt = "created_at" }
        }

        do {
            let rows: [Row] = try await SupabaseManager.shared.client
                .from("sessions")
                .select("created_at")
                .eq("user_id", value: userId)
                .eq("status", value: "completed")
                .gte("created_at", value: formatter.string(from: weekStart))
                .execute()
                .value
            return rows.count
        } catch {
            return 0
        }
    }
}

/// Bridges PurchasesDelegate updates onto the main actor service.
private final class PurchasesDelegateBridge: NSObject, PurchasesDelegate {
    static let shared = PurchasesDelegateBridge()

    func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            SubscriptionService.shared.applyCustomerInfo(customerInfo)
        }
    }
}
