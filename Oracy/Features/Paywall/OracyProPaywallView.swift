import SwiftUI
import RevenueCat
import RevenueCatUI

/// Routes to either Oracy’s branded paywall (offerings API) or RevenueCat’s dashboard Paywall.
struct OracyProPaywallView: View {
    var onUnlocked: (() -> Void)? = nil

    @State private var remoteConfig = RemoteConfigService.shared

    var body: some View {
        Group {
            if remoteConfig.useRevenueCatPaywall {
                RevenueCatDashboardPaywallView(onUnlocked: onUnlocked)
            } else {
                OracyBrandedPaywallView(onUnlocked: onUnlocked)
            }
        }
        .task {
            await remoteConfig.refresh()
            await SubscriptionService.shared.loadOfferings()
        }
    }
}

// MARK: - App design (Purchases.offerings → packages)

/// Custom Oracy paywall. Prices/products come from RevenueCat offerings — no dashboard Paywall required.
struct OracyBrandedPaywallView: View {
    var onUnlocked: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var subscriptions = SubscriptionService.shared
    @State private var selectedAnnual = true
    @State private var appeared = false
    @State private var showPrivacy = false
    @State private var showAuth = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    hero
                    if subscriptions.isLoadingOfferings {
                        ProgressView()
                            .tint(Theme.accent)
                            .padding(.vertical, 12)
                    }
                    planPicker
                    perks
                    ctaBlock
                    legalFooter
                }
                .padding(.horizontal, 28)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .themeBackground()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.light()
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
        .task {
            withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .themeBounce) {
                appeared = true
            }
            await subscriptions.loadOfferings()
            if subscriptions.annualPackage == nil, subscriptions.monthlyPackage != nil {
                selectedAnnual = false
            }
        }
        .sheet(isPresented: $showPrivacy) {
            PrivacyView()
        }
        .sheet(isPresented: $showAuth, onDismiss: {
            dismiss()
        }) {
            AuthSheet(
                showsSkip: true,
                title: "Save your Pro",
                message: "Link Apple or Google so Oracy Pro follows you across devices."
            )
        }
        .interactiveDismissDisabled(subscriptions.isPurchasing)
    }

    private var hero: some View {
        VStack(spacing: 14) {
            AppLogoMark(size: 88)
                .scaleEffect(appeared ? 1 : 0.88)
                .opacity(appeared ? 1 : 0)

            if subscriptions.isEligibleForTrial {
                Text("7 days free")
                    .font(Theme.grotesk(14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .opacity(appeared ? 1 : 0)
            }

            Text("Speak with\nno limits.")
                .font(Theme.fraunces(34, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Text("Unlimited one-minute practice, full AI feedback, and a Pro mark on your profile.")
                .font(Theme.grotesk(16))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .opacity(appeared ? 1 : 0)
        }
    }

    private var planPicker: some View {
        VStack(spacing: 10) {
            if subscriptions.annualPackage != nil || !AppConfig.isRevenueCatConfigured {
                planRow(
                    title: "Yearly",
                    subtitle: annualSubtitle,
                    badge: "Best value",
                    selected: selectedAnnual
                ) {
                    selectedAnnual = true
                }
            }

            if subscriptions.monthlyPackage != nil || !AppConfig.isRevenueCatConfigured {
                planRow(
                    title: "Monthly",
                    subtitle: monthlySubtitle,
                    badge: nil,
                    selected: !selectedAnnual
                ) {
                    selectedAnnual = false
                }
            }

            if AppConfig.isRevenueCatConfigured,
               subscriptions.annualPackage == nil,
               subscriptions.monthlyPackage == nil,
               !subscriptions.isLoadingOfferings {
                Text("Products aren’t available yet. Check your RevenueCat offering has Monthly and Annual packages.")
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }
        }
        .opacity(appeared ? 1 : 0)
    }

    private var annualSubtitle: String {
        if let package = subscriptions.annualPackage {
            let price = package.storeProduct.localizedPriceString
            if subscriptions.isEligibleForTrial {
                return "7 days free, then \(price)/year"
            }
            return "\(price)/year"
        }
        return subscriptions.isEligibleForTrial ? "7 days free, then billed yearly" : "Billed yearly"
    }

    private var monthlySubtitle: String {
        if let package = subscriptions.monthlyPackage {
            let price = package.storeProduct.localizedPriceString
            if subscriptions.isEligibleForTrial {
                return "7 days free, then \(price)/month"
            }
            return "\(price)/month"
        }
        return subscriptions.isEligibleForTrial ? "7 days free, then billed monthly" : "Billed monthly"
    }

    private func planRow(
        title: String,
        subtitle: String,
        badge: String?,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            Haptics.selectionChanged()
            action()
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(Theme.grotesk(17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        if let badge {
                            Text(badge)
                                .font(Theme.grotesk(11, weight: .semibold))
                                .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Theme.accent)
                                .clipShape(Capsule())
                        }
                    }
                    Text(subtitle)
                        .font(Theme.grotesk(13))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary.opacity(0.45))
            }
            .padding(16)
            .background(Theme.cardBackground.opacity(selected ? 0.95 : 0.72))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(selected ? Theme.accent.opacity(0.55) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private var perks: some View {
        VStack(alignment: .leading, spacing: 12) {
            perkRow("Unlimited practice analyses")
            perkRow("Full AI feedback every session")
            perkRow("Pro mark on your avatar")
            perkRow("\(AppConfig.freeWeeklySessionLimit) free sessions each week without Pro")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(appeared ? 1 : 0)
    }

    private func perkRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Theme.success)
            Text(text)
                .font(Theme.grotesk(15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ctaBlock: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchase() }
            } label: {
                if subscriptions.isPurchasing {
                    ProgressView()
                        .tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                } else {
                    HStack(spacing: 8) {
                        Text(primaryCTATitle)
                        ProTag(surface: .onAccent)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(subscriptions.isPurchasing || (AppConfig.isRevenueCatConfigured && selectedPackage == nil))

            Button("Restore purchases") {
                Task { await restore() }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(subscriptions.isPurchasing)

            if let error = subscriptions.lastErrorMessage, !error.isEmpty {
                Text(error)
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.accent)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var selectedPackage: Package? {
        selectedAnnual ? subscriptions.annualPackage : subscriptions.monthlyPackage
    }

    private var primaryCTATitle: String {
        subscriptions.isEligibleForTrial ? "Start 7-day free trial" : "Continue with Oracy Pro"
    }

    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text(legalText)
                .font(Theme.grotesk(11))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button("Privacy & Data") {
                showPrivacy = true
            }
            .font(Theme.grotesk(12, weight: .medium))
            .foregroundStyle(Theme.accent)

            if let url = URL(string: "https://www.revenuecat.com") {
                Link(destination: url) {
                    Text("Powered by RevenueCat")
                        .font(Theme.grotesk(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary.opacity(0.7))
                }
                .padding(.top, 6)
                .accessibilityLabel("Powered by RevenueCat")
            }
        }
        .padding(.top, 4)
    }

    private var legalText: String {
        if subscriptions.isEligibleForTrial {
            return "Free for 7 days, then auto-renews unless canceled at least 24 hours before the trial ends. Manage in Account Settings."
        }
        return "Payment will be charged to your Apple ID. Subscription auto-renews unless canceled at least 24 hours before the period ends."
    }

    private func purchase() async {
        let ok = await subscriptions.purchaseSelectedPlan(isAnnual: selectedAnnual)
        guard ok else { return }
        await finishUnlocked()
    }

    private func restore() async {
        let ok = await subscriptions.restore()
        guard ok, subscriptions.isProActive else { return }
        await finishUnlocked()
    }

    /// After Pro unlocks, prompt guests to link so entitlement can follow their account.
    private func finishUnlocked() async {
        onUnlocked?()
        if AuthService.shared.isLoggedIn {
            dismiss()
        } else {
            showAuth = true
        }
    }
}

// MARK: - RevenueCat dashboard Paywall (optional)

/// Requires a Paywall designed & attached to the current offering in the RevenueCat dashboard.
struct RevenueCatDashboardPaywallView: View {
    var onUnlocked: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var subscriptions = SubscriptionService.shared
    @State private var showAuth = false

    var body: some View {
        Group {
            if AppConfig.isRevenueCatConfigured {
                PaywallView(displayCloseButton: true)
                    .onPurchaseCompleted { customerInfo in
                        subscriptions.applyCustomerInfo(customerInfo)
                        finishIfEntitled()
                    }
                    .onPurchaseFailure { error in
                        subscriptions.lastErrorMessage = error.localizedDescription
                        Haptics.warning()
                    }
                    .onRestoreCompleted { customerInfo in
                        subscriptions.applyCustomerInfo(customerInfo)
                        finishIfEntitled()
                    }
                    .onRestoreFailure { error in
                        subscriptions.lastErrorMessage = error.localizedDescription
                        Haptics.warning()
                    }
                    .onRequestedDismissal {
                        dismiss()
                    }
            } else {
                ZStack {
                    ThemeBackground()
                    VStack(spacing: 16) {
                        Text("Subscriptions unavailable")
                            .font(Theme.fraunces(24, weight: .bold))
                        Button("Close") { dismiss() }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(28)
                }
            }
        }
        .sheet(isPresented: $showAuth, onDismiss: {
            dismiss()
        }) {
            AuthSheet(
                showsSkip: true,
                title: "Save your Pro",
                message: "Link Apple or Google so Oracy Pro follows you across devices."
            )
        }
    }

    private func finishIfEntitled() {
        guard subscriptions.isPro else { return }
        Haptics.success()
        onUnlocked?()
        if AuthService.shared.isLoggedIn {
            dismiss()
        } else {
            showAuth = true
        }
    }
}

/// RevenueCat Customer Center — manage / cancel / restore for Pro members.
struct OracyCustomerCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptions = SubscriptionService.shared

    var body: some View {
        Group {
            if AppConfig.isRevenueCatConfigured {
                CustomerCenterView()
                    .onCustomerCenterRestoreCompleted { customerInfo in
                        subscriptions.applyCustomerInfo(customerInfo)
                    }
            } else {
                NavigationStack {
                    VStack(spacing: 16) {
                        Text("Manage subscription")
                            .font(Theme.fraunces(24, weight: .bold))
                        Text("Open Apple subscription settings to manage Oracy Pro.")
                            .font(Theme.grotesk(15))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                        if let url = subscriptions.manageSubscriptionsURL() {
                            Button("Open Subscriptions") {
                                UIApplication.shared.open(url)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding(28)
                    .themeBackground()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { dismiss() }
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Branded") {
    OracyBrandedPaywallView()
}
#endif
