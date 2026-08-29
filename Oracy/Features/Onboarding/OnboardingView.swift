import SwiftUI

enum OnboardingPhase: Equatable {
    case form
    case creating
    case microphone
    case notifications
    case finale
}

/// Where we are inside the active beat.
private enum BeatPhase: Equatable {
    case prompting
    case controls
    case answering // controls gone, answer visible, ack typing
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @AppStorage("profile.occupation") private var occupationStorage = ""
    @AppStorage("profile.age") private var ageStorage = ""
    @AppStorage("profile.priorities") private var prioritiesStorage = ""

    @State private var answers = OnboardingAnswers()
    @State private var phase: OnboardingPhase = .form
    @State private var beat: ConversationBeat = .greeting
    @State private var beatPhase: BeatPhase = .prompting
    /// Append-only rows — greeting is first and stays as history above auth.
    @State private var entries: [ConversationEntry] = [ConversationEntry(beat: .greeting)]
    @State private var pendingAnswer: [String] = []
    @State private var pendingAck: [String] = []
    @State private var showMoreAuth = false
    @State private var controlsAppeared = false
    @State private var didPersistDraft = false
    @State private var didFinish = false
    @State private var referralError: String?
    @State private var isRedeemingReferral = false

    /// Top inset for the conversation thread (same for greeting and later beats).
    @State private var conversationTopPad: CGFloat = 20
    @State private var viewportHeight: CGFloat = 0
    /// Coalesces stacked reveal requests into a single scroll.
    @State private var revealToken = 0
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var referralFieldFocused: Bool

    private var scrollAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.25)
            : .easeOut(duration: 0.4)
    }

    var body: some View {
        ZStack {
            ThemeBackground(ambientMotion: true)

            switch phase {
            case .form:
                conversationScroll
                    .transition(.opacity)
            case .creating:
                OnboardingCreatingStep {
                    Task { await persistDraftThenContinue() }
                }
                .transition(.opacity)
            case .microphone:
                OnboardingMicStep { go(to: .notifications) }
                    .transition(.opacity)
            case .notifications:
                OnboardingNotificationsStep { go(to: .finale) }
                    .transition(.opacity)
            case .finale:
                OnboardingFinaleStep {
                    Task { await finishOnboarding() }
                }
                .transition(.opacity)
            }
        }
        // Soft phase fades — bounce fought the creating/status copy
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .easeInOut(duration: 0.45), value: phase)
        .animation(reduceMotion ? .easeOut(duration: 0.25) : .easeOut(duration: 0.4), value: controlsAppeared)
    }

    // MARK: - Scroll

    private var conversationScroll: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 36) {
                        Color.clear
                            .frame(height: conversationTopPad)
                            .id("top")

                        // Append-only entries — greeting remains as history above auth
                        ForEach(entries) { entry in
                            entryRow(entry)
                                .id(entryScrollId(entry))
                        }

                        Color.clear
                            // Slack below so scrollTo(.center) can park the active row mid-screen
                            .frame(height: max(200, viewportHeight * 0.5))
                            .id("bottom")
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onAppear {
                    viewportHeight = geo.size.height
                }
                .onChange(of: geo.size.height) { _, height in
                    viewportHeight = height
                }
                .onChange(of: entries.count) { _, _ in
                    // One scroll per turn: prompting already reserves control height, so
                    // centering matches the controls layout (no second scroll on controls).
                    scheduleRevealLatest(using: proxy)
                }
            }
        }
    }

    private func entryScrollId(_ entry: ConversationEntry) -> String {
        "entry-\(entry.id.uuidString)"
    }

    /// Coalesce stacked triggers into one scroll after layout.
    private func scheduleRevealLatest(using proxy: ScrollViewProxy) {
        revealToken += 1
        let token = revealToken
        DispatchQueue.main.async {
            guard token == revealToken else { return }
            revealLatestIfNeeded(using: proxy)
        }
    }

    private func revealLatestIfNeeded(using proxy: ScrollViewProxy) {
        guard let latest = entries.last else { return }
        withAnimation(scrollAnimation) {
            proxy.scrollTo(entryScrollId(latest), anchor: .center)
        }
    }

    /// One append-only row: prompt stays mounted; complete only dims + swaps controls for static answers.
    @ViewBuilder
    private func entryRow(_ entry: ConversationEntry) -> some View {
        let isActive = !entry.isComplete
        let centered = entry.beat.isCentered

        VStack(alignment: centered ? .center : .leading, spacing: 18) {
            ConversationPrompt(
                title: entry.beat.title,
                subtitle: entry.beat.subtitle,
                centered: centered
            ) {
                if isActive { handlePromptFinished() }
            }
            // Scroll identity lives on the outer entry row so prompt + controls center together
            .opacity(entry.isComplete ? 0.58 : 1)

            if entry.isComplete {
                if !entry.answerLines.isEmpty || !entry.acknowledgment.isEmpty {
                    ConversationEntryAnswers(
                        answerLines: entry.answerLines,
                        acknowledgment: entry.acknowledgment,
                        centered: centered,
                        dimmed: true
                    )
                }
            } else if beatPhase == .prompting || beatPhase == .controls {
                // Reserve height only while waiting for / showing controls — not during answering
                ZStack(alignment: .topLeading) {
                    Color.clear
                        .frame(height: reservedControlsHeight)

                    if beatPhase == .controls {
                        controls
                            .onboardingReveal(controlsAppeared)
                    }
                }
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            } else if beatPhase == .answering {
                VStack(alignment: centered ? .center : .leading, spacing: 12) {
                    ForEach(Array(pendingAnswer.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(Theme.grotesk(16, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                            .multilineTextAlignment(centered ? .center : .leading)
                            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
                    }

                    ConversationAck(
                        lines: pendingAck,
                        centered: centered
                    ) {
                        finalizeTurnAndAdvance()
                    }
                }
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
    }

    // MARK: - Controls (only current beat)

    @ViewBuilder
    private var controls: some View {
        switch beat {
        case .greeting:
            EmptyView()
        case .name:
            nameControls
        case .auth:
            authControls
        case .priorities:
            multiSelectControls(
                options: OnboardingPriority.allCases.map { ($0, $0.displayName) },
                selected: answers.priorities,
                canContinue: !answers.priorities.isEmpty,
                toggle: { toggle(&answers.priorities, $0) }
            )
        case .age:
            VStack(spacing: 22) {
                AgeSelector(age: $answers.age)
                OnboardingPrimaryButton(title: "Continue") {
                    submitCurrent()
                }
            }
        case .personality:
            multiSelectControls(
                options: OnboardingPersonalityTag.allCases.map { ($0, $0.displayName) },
                selected: answers.personality,
                canContinue: !answers.personality.isEmpty,
                toggle: { toggle(&answers.personality, $0) }
            )
        case .goals:
            multiSelectControls(
                options: UserGoal.allCases.map { ($0, $0.displayName) },
                selected: answers.goals,
                canContinue: !answers.goals.isEmpty,
                toggle: { toggle(&answers.goals, $0) }
            )
        case .level:
            VStack(spacing: 12) {
                ForEach(Array(ExperienceLevel.allCases.filter { $0 != .expert }.enumerated()), id: \.element.id) { index, item in
                    OnboardingGlassCard(
                        title: item.displayName,
                        isSelected: answers.level == item
                    ) {
                        answers.level = item
                    }
                    .opacity(controlsAppeared ? 1 : 0)
                    .offset(y: controlsAppeared ? 0 : 8)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.2) : .themeBounce.delay(Double(index) * 0.05),
                        value: controlsAppeared
                    )
                }
                OnboardingPrimaryButton(title: "Continue") {
                    submitCurrent()
                }
                .padding(.top, 6)
            }
        case .review:
            OnboardingPrimaryButton(title: "Start setup") {
                submitCurrent()
            }
        case .referral:
            referralControls
        }
    }

    private var referralControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Referral code")
                    .font(Theme.grotesk(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer()

                ReferralCodePasteButton {
                    pasteOnboardingReferralCode()
                }
            }

            TextField("ABCDEFGH", text: $answers.referralCode)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($referralFieldFocused)
                .submitLabel(.continue)
                .onSubmit {
                    Task { await submitReferralCode() }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.cardBackground.opacity(0.72))
                }
                .onChange(of: answers.referralCode) { _, _ in
                    referralError = nil
                }

            if let referralError {
                Text(referralError)
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            OnboardingPrimaryButton(
                title: "Continue",
                isEnabled: !isRedeemingReferral,
                isLoading: isRedeemingReferral
            ) {
                Task { await submitReferralCode() }
            }

            Button {
                skipReferralCode()
            } label: {
                Text("Skip for now")
                    .font(Theme.grotesk(16, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isRedeemingReferral)
        }
    }

    private func pasteOnboardingReferralCode() {
        guard let pasted = ReferralCodePaste.cleanedClipboardCode() else {
            referralError = "No invite code found on the clipboard."
            Haptics.warning()
            return
        }
        answers.referralCode = pasted
        referralError = nil
        Haptics.success()
    }

    private var nameControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("Your name", text: $answers.displayName)
                .font(Theme.grotesk(18, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.continue)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .background {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                        .opacity(0.7)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.28), lineWidth: 0.8)
                }
                .focused($nameFieldFocused)
                .onSubmit {
                    guard !answers.trimmedDisplayName.isEmpty else { return }
                    submitCurrent()
                }

            OnboardingPrimaryButton(
                title: "Continue",
                isEnabled: !answers.trimmedDisplayName.isEmpty
            ) {
                nameFieldFocused = false
                submitCurrent()
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.25)) {
                nameFieldFocused = true
            }
        }
    }

    private var authControls: some View {
        OnboardingAuthInline(
            showMore: $showMoreAuth,
            preferredName: answers.trimmedDisplayName,
            onAuthenticated: { choice in
                answers.authChoice = choice
                // Prefill name from Apple/Google profile when auth comes before the name beat.
                if answers.trimmedDisplayName.isEmpty {
                    if let profileName = AuthService.shared.profile?.displayName?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !profileName.isEmpty {
                        answers.displayName = profileName
                    } else if let cached = LastSignedInIdentity.displayName {
                        answers.displayName = cached
                    }
                }
                submitCurrent()
            }
        )
    }

    private func multiSelectControls<T: Hashable>(
        options: [(T, String)],
        selected: Set<T>,
        canContinue: Bool,
        toggle: @escaping (T) -> Void
    ) -> some View {
        VStack(alignment: beat.isCentered ? .center : .leading, spacing: 14) {
            FlowLayout(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    OnboardingGlassChip(
                        title: option.1,
                        isSelected: selected.contains(option.0)
                    ) {
                        toggle(option.0)
                    }
                    .opacity(controlsAppeared ? 1 : 0)
                    .scaleEffect(controlsAppeared ? 1 : 0.96)
                    .animation(
                        reduceMotion ? .easeOut(duration: 0.2) : .themeBounce.delay(Double(index) * 0.04),
                        value: controlsAppeared
                    )
                }
            }

            OnboardingPrimaryButton(title: "Continue", isEnabled: canContinue) {
                submitCurrent()
            }
            .padding(.top, 4)
        }
    }

    // MARK: - Flow

    private func handlePromptFinished() {
        if beat == .greeting {
            // Keep "Hey" in the thread, then append the next beat beneath it
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                if let idx = entries.indices.last {
                    entries[idx].isComplete = true
                }
                if let next = beat.next {
                    entries.append(ConversationEntry(beat: next))
                    beat = next
                    beatPhase = .prompting
                    controlsAppeared = false
                }
            }
            return
        }

        // Keep the same ConversationPrompt mounted — only fade controls in
        beatPhase = .controls
        controlsAppeared = false

        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.12)) {
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.45)) {
                controlsAppeared = true
            }
        }
    }

    /// Approximate height of the upcoming control cluster so layout stays stable.
    private var reservedControlsHeight: CGFloat {
        switch beat {
        case .name: return 140
        case .auth: return 280
        case .age: return 160
        case .level: return 220
        case .review: return 64
        case .referral: return 200
        case .priorities, .personality, .goals: return 160
        case .greeting: return 0
        }
    }

    private func submitCurrent() {
        let answer = ConversationCopy.answerSummary(for: beat, answers: answers)
        var ack = ConversationCopy.acknowledgment(for: beat, answers: answers)
        if ack.isEmpty { ack = ["Okay."] }

        // Fade controls out first while keeping reserved height, then show answer/ack
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.3)) {
            controlsAppeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + (reduceMotion ? 0.05 : 0.18)) {
            pendingAnswer = answer
            pendingAck = ack
            beatPhase = .answering
        }
    }

    private func skipReferralCode() {
        answers.didSkipReferralCode = true
        answers.referralCode = ""
        referralError = nil
        referralFieldFocused = false
        submitCurrent()
    }

    private func submitReferralCode() async {
        let code = answers.trimmedReferralCode
        if code.isEmpty {
            skipReferralCode()
            return
        }

        isRedeemingReferral = true
        referralError = nil
        defer { isRedeemingReferral = false }

        let result = await InviteService.shared.redeem(code)
        switch result {
        case .success, .alreadyRedeemed:
            answers.didSkipReferralCode = false
            referralFieldFocused = false
            Haptics.success()
            submitCurrent()
        default:
            Haptics.warning()
            referralError = result.userMessage
        }
    }

    private func finalizeTurnAndAdvance() {
        let ackLines = pendingAck.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        if beat == .referral {
            completeCurrentEntry(ackLines: ackLines)
            go(to: .creating)
            return
        }

        if beat == .review {
            completeCurrentEntry(ackLines: ackLines)
            if RemoteConfigService.shared.isReferralRewardsEnabled {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    entries.append(ConversationEntry(beat: .referral))
                    beat = .referral
                    beatPhase = .prompting
                    controlsAppeared = false
                    showMoreAuth = false
                    referralError = nil
                }
            } else {
                go(to: .creating)
            }
            return
        }

        // Complete current entry in place (same id) then append next
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let idx = entries.indices.last {
                entries[idx].answerLines = pendingAnswer
                entries[idx].acknowledgment = ackLines
                entries[idx].isComplete = true
            }
            pendingAnswer = []
            pendingAck = []
            if let next = beat.next, next != .referral {
                // `.referral` is inserted only from review when RC allows it.
                entries.append(ConversationEntry(beat: next))
                beat = next
                beatPhase = .prompting
                controlsAppeared = false
                showMoreAuth = false
            }
        }
    }

    private func completeCurrentEntry(ackLines: [String]) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            if let idx = entries.indices.last {
                entries[idx].answerLines = pendingAnswer
                entries[idx].acknowledgment = ackLines
                entries[idx].isComplete = true
            }
            pendingAnswer = []
            pendingAck = []
        }
    }

    private func toggle<T: Hashable>(_ set: inout Set<T>, _ value: T) {
        if set.contains(value) {
            set.remove(value)
        } else {
            set.insert(value)
        }
    }

    private func go(to next: OnboardingPhase) {
        withAnimation(reduceMotion ? .easeOut(duration: 0.25) : .themeBounce) {
            phase = next
        }
    }

    @MainActor
    private func persistDraftThenContinue() async {
        if !didPersistDraft {
            didPersistDraft = true

            let update = ProfileUpdate(
                displayName: AuthService.isRealDisplayName(answers.trimmedDisplayName)
                    ? answers.trimmedDisplayName
                    : nil,
                goals: answers.goals.map(\.rawValue),
                experienceLevel: answers.level.rawValue,
                timezone: TimeZone.current.identifier,
                age: answers.age,
                priorities: answers.priorities.map(\.rawValue).sorted(),
                personality: answers.personality.map(\.rawValue).sorted()
            )
            try? await AuthService.shared.updateProfile(update)

            // Keep legacy AppStorage keys warm for any UI still reading them this session.
            prioritiesStorage = answers.prioritiesStorageValue
            ageStorage = answers.ageStorageValue
            occupationStorage = answers.occupationStorageValue
        }
        go(to: .microphone)
    }

    @MainActor
    private func finishOnboarding() async {
        guard !didFinish else { return }
        didFinish = true
        do {
            try await AuthService.shared.updateProfile(ProfileUpdate(onboardingCompleted: true))
            Haptics.success()
        } catch {
            Haptics.success()
        }
        onComplete()
    }
}
