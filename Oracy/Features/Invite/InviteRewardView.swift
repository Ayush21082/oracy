import SwiftUI
import UIKit

/// Guest Pass reward + referral share screen (opened from Profile).
struct InviteRewardView: View {
    var inviterName: String
    var referralCode: String

    @State private var invites = InviteService.shared
    @State private var remoteConfig = RemoteConfigService.shared
    @State private var showShare = false
    @State private var claimingMilestone: Int?
    @State private var showClaimConfetti = false
    @State private var claimBanner: String?
    @State private var isScrolling = false

    private var inviteOnly: Bool { remoteConfig.isInviteOnlyEnabled }
    private var code: String {
        let live = invites.rewardState.referralCode
        if !live.isEmpty { return live }
        if !referralCode.isEmpty { return referralCode }
        return invites.referralCode(for: AuthService.shared.userId)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                GuestPassMetalCard(inviterName: inviterName, allowsMotion: !isScrolling)

                VStack(alignment: .leading, spacing: 8) {
                    Text(inviteOnly ? "Your invite opens the door" : "Share Oracy. Unlock rewards.")
                        .font(Theme.fraunces(24, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(inviteOnly
                         ? "Friends use your code to get in and +2 weekly speaks. You unlock more rewards as they join — claim them as you go."
                         : "Friends who enter your code get +2 weekly speaks too. You unlock more weekly speaks or Pro as they join — claim them as you go.")
                        .font(Theme.grotesk(15))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                progressHero

                VStack(alignment: .leading, spacing: 14) {
                    Text("Your referral code")
                        .font(Theme.grotesk(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .textCase(.uppercase)
                        .tracking(0.6)

                    Text(inviteOnly
                         ? "Tap the code to copy, then share so someone can redeem their invite."
                         : "Tap the code to copy, then share so friends can join and count toward your rewards.")
                        .font(Theme.grotesk(14))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if code.isEmpty {
                        ReferralCodeGlassRow(code: "········")
                            .padding(.top, 4)
                            .redacted(reason: .placeholder)
                            .allowsHitTesting(false)

                        if invites.lastErrorMessage != nil {
                            Button("Try again") {
                                Task { await invites.refreshRewardState() }
                            }
                            .font(Theme.grotesk(14, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        }
                    } else {
                        ReferralCodeGlassRow(code: code)
                            .padding(.top, 4)
                    }
                }

                Button {
                    showShare = true
                } label: {
                    Text(inviteOnly ? "Share invite" : "Share & earn")
                }
                .buttonStyle(SecondaryButtonStyle())

                milestoneTrack
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .onScrollPhaseChange { _, phase in
            let scrolling = phase != .idle
            if scrolling != isScrolling { isScrolling = scrolling }
        }
        .themeBackground()
        .navigationTitle("Reward")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if showClaimConfetti {
                ConfettiCannonView()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .sheet(isPresented: $showShare) {
            InviteShareSheet(
                items: [
                    invites.shareMessage(
                        inviterName: inviterName,
                        code: code,
                        inviteOnly: inviteOnly
                    )
                ]
            )
        }
        .task {
            _ = invites.referralCode(for: AuthService.shared.userId)
            await invites.refreshRewardState()
        }
    }

    private var progressHero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(invites.rewardState.count)")
                    .font(Theme.fraunces(40, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())

                Text(invites.rewardState.count == 1 ? "friend joined" : "friends joined")
                    .font(Theme.grotesk(16, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            if let teaser = invites.rewardState.nextTeaser {
                Text(teaser)
                    .font(Theme.grotesk(14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let claimBanner {
                Text(claimBanner)
                    .font(Theme.grotesk(14, weight: .semibold))
                    .foregroundStyle(Theme.success)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if invites.rewardState.bonusSessions > 0 || invites.rewardState.hasActiveReferralPro {
                HStack(spacing: 10) {
                    if invites.rewardState.bonusSessions > 0 {
                        grantChip(text: "+\(invites.rewardState.bonusSessions) weekly speaks")
                    }
                    if invites.rewardState.hasActiveReferralPro {
                        grantChip(text: "Pro active")
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.cardBackground.opacity(0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.white.opacity(0.35), lineWidth: 1)
        }
    }

    private func grantChip(text: String) -> some View {
        Text(text)
            .font(Theme.grotesk(12, weight: .semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                Capsule().fill(Theme.accent.opacity(0.16))
            }
    }

    private var milestoneTrack: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Milestones")
                .font(Theme.fraunces(20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("Claim each reward as friends join — stacked speaks and Pro time.")
                .font(Theme.grotesk(14))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                ForEach(invites.rewardState.milestones) { milestone in
                    MilestoneRow(
                        milestone: milestone,
                        status: invites.rewardState.status(for: milestone),
                        isClaiming: claimingMilestone == milestone.friendsRequired
                    ) {
                        Task { await claim(milestone) }
                    }
                }
            }
        }
    }

    private func claim(_ milestone: ReferralMilestoneOffer) async {
        claimingMilestone = milestone.friendsRequired
        defer { claimingMilestone = nil }

        let ok = await invites.claimMilestone(milestone)
        if ok {
            Haptics.success()
            withAnimation(.easeOut(duration: 0.25)) {
                claimBanner = "Claimed: \(milestone.title)"
                showClaimConfetti = true
            }
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.3)) {
                showClaimConfetti = false
            }
        } else {
            Haptics.warning()
            withAnimation {
                claimBanner = invites.lastErrorMessage ?? "Couldn’t claim that yet."
            }
        }
    }
}

// MARK: - Milestone row

private struct MilestoneRow: View {
    let milestone: ReferralMilestoneOffer
    let status: ReferralMilestoneStatus
    let isClaiming: Bool
    let onClaim: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(iconBackground)
                    .frame(width: 44, height: 44)
                Text("\(milestone.friendsRequired)")
                    .font(Theme.grotesk(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(milestone.title)
                    .font(Theme.grotesk(16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(statusSubtitle)
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            trailingControl
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground.opacity(status == .claimed ? 0.45 : 0.72))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        }
        .opacity(statusOpacity)
    }

    private var statusSubtitle: String {
        switch status {
        case .locked(let remaining):
            let word = remaining == 1 ? "friend" : "friends"
            return "\(milestone.hook) · \(remaining) \(word) to go"
        case .claimable:
            return milestone.hook
        case .claimed:
            return "Claimed · \(milestone.hook)"
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        switch status {
        case .locked:
            Image(systemName: "lock.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary.opacity(0.7))
        case .claimable:
            Button(action: onClaim) {
                if isClaiming {
                    ProgressView()
                        .tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                        .frame(width: 72, height: 34)
                } else {
                    Text("Claim")
                        .font(Theme.grotesk(14, weight: .semibold))
                        .foregroundStyle(Color(red: 0.98, green: 0.97, blue: 0.96))
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(Theme.accent))
                }
            }
            .buttonStyle(.plain)
            .disabled(isClaiming)
        case .claimed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Theme.success)
        }
    }

    private var iconBackground: Color {
        switch status {
        case .claimed: return Theme.success.opacity(0.18)
        case .claimable: return Theme.accent.opacity(0.2)
        case .locked: return Color.black.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch status {
        case .claimable: return Theme.accent.opacity(0.45)
        case .claimed: return Theme.success.opacity(0.25)
        case .locked: return Color.white.opacity(0.28)
        }
    }

    private var statusOpacity: Double {
        if case .locked = status { return 0.78 }
        return 1
    }
}

// MARK: - Letter glass boxes

struct ReferralCodeGlassRow: View {
    var code: String

    @State private var showCopied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                copyCode()
            } label: {
                HStack(spacing: 7) {
                    ForEach(Array(code.enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 48)
                            .background {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Theme.cardBackground.opacity(0.92))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(Color.white.opacity(0.45), lineWidth: 1)
                            }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Referral code \(code)")
            .accessibilityHint("Copies the full code")
            .accessibilityAddTraits(.isButton)

            Text(showCopied ? "Copied to clipboard" : "Tap to copy")
                .font(Theme.grotesk(13, weight: .medium))
                .foregroundStyle(showCopied ? Theme.success : Theme.textSecondary.opacity(0.85))
                .animation(.easeOut(duration: 0.2), value: showCopied)
                .accessibilityHidden(true)
        }
    }

    private func copyCode() {
        guard !code.isEmpty else { return }
        UIPasteboard.general.string = code
        Haptics.success()
        withAnimation(.easeOut(duration: 0.2)) {
            showCopied = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_800_000_000)
            withAnimation(.easeOut(duration: 0.25)) {
                showCopied = false
            }
        }
    }
}

/// Shared paste helper for invite / onboarding referral fields.
enum ReferralCodePaste {
    static func cleanedClipboardCode() -> String? {
        guard let raw = UIPasteboard.general.string else { return nil }
        let parsed = InviteService.parseReferralCode(raw)
        guard (6...10).contains(parsed.count) else { return nil }
        return parsed
    }
}

struct ReferralCodePasteButton: View {
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.soft()
            action()
        } label: {
            Label("Paste", systemImage: "doc.on.clipboard")
                .font(Theme.grotesk(14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule()
                        .fill(Theme.accent.opacity(0.12))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Paste referral code")
    }
}

// MARK: - Invite gate (app unlock)

struct InviteGateView: View {
    var onUnlocked: () -> Void

    @State private var code = ""
    @State private var errorMessage: String?
    @State private var isWorking = false

    var body: some View {
        ZStack {
            ThemeBackground()

            VStack(spacing: 28) {
                Spacer(minLength: 24)

                AppLogoMark(size: 88, showsWordmark: true)

                VStack(spacing: 10) {
                    Text("Invite only")
                        .font(Theme.fraunces(30, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)

                    Text("Oracy is opening with invites first. Enter a friend’s Guest Pass — you both get +2 weekly speaks.")
                        .font(Theme.grotesk(16))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 28)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Invite code")
                            .font(Theme.grotesk(13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.6)

                        Spacer()

                        ReferralCodePasteButton {
                            pasteCode()
                        }
                    }

                    TextField("ABCDEFGH", text: $code)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(Theme.cardBackground.opacity(0.72))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(Theme.grotesk(13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.horizontal, 28)

                Button {
                    Task { await redeem() }
                } label: {
                    if isWorking {
                        ProgressView().tint(Color(red: 0.98, green: 0.97, blue: 0.96))
                    } else {
                        Text("Continue")
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(isWorking || code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .padding(.horizontal, 28)

                Spacer()
            }
        }
        .appErrorOverlay()
    }

    private func pasteCode() {
        guard let pasted = ReferralCodePaste.cleanedClipboardCode() else {
            errorMessage = "No invite code found on the clipboard."
            Haptics.warning()
            return
        }
        code = pasted
        errorMessage = nil
        Haptics.success()
    }

    private func redeem() async {
        isWorking = true
        defer { isWorking = false }
        let result = await InviteService.shared.redeem(code)
        switch result {
        case .success, .alreadyRedeemed:
            Haptics.success()
            errorMessage = nil
            onUnlocked()
        default:
            Haptics.warning()
            errorMessage = result.userMessage
        }
    }
}

private struct InviteShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
