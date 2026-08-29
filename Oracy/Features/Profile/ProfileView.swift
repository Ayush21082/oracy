import SwiftUI
import Charts
import CoreMotion
import Combine
import UIKit

// MARK: - Profile

struct ProfileView: View {
    /// Explicit close — more reliable than `dismiss` inside a nested NavigationStack cover.
    var onClose: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var sessionService = SessionService.shared
    @State private var showSettings = false
    @State private var referralCount = 0
    /// Built from cached sessions first — avoids recomputing on every body pass.
    @State private var weekModel = PracticeWeekModel(sessions: SessionService.shared.sessions)
    @State private var activityModel = PracticeActivityModel(
        sessions: SessionService.shared.sessions,
        joinedAt: AuthService.shared.profile?.createdAt
    )
    @State private var totalWords = 0
    /// Heavy card/chart chrome mounts after first frame.
    @State private var showSecondaryChrome = false
    @State private var showHighlightStories = false
    @State private var showExpandedPhoto = false
    /// Blocks the Button tap that fires after a long-press ends.
    @State private var suppressAvatarTap = false
    @AppStorage("debug.forceCelebrate") private var debugForceCelebrate = false
    /// Rubber-band pull distance used to stretch the profile avatar.
    @State private var pullStretch: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var subscriptions = SubscriptionService.shared
    @State private var showInviteReward = false
    @State private var showAuth = false
    @State private var isScrolling = false
    /// Decoded once — never reload JPEG from disk during pull-to-stretch frames.
    @State private var cachedAvatarImage: UIImage?

    private let baseAvatarSize: CGFloat = 108

    /// Grows with pull-down overscroll; capped so it stays playful, not huge.
    private var stretchedAvatarSize: CGFloat {
        guard !reduceMotion else { return baseAvatarSize }
        let extra = min(pullStretch * 0.42, 64)
        return baseAvatarSize + extra
    }

    /// GPU-cheap rubber-band: fixed-size avatar scaled, instead of re-layout/re-raster every frame.
    private var pullScale: CGFloat {
        stretchedAvatarSize / baseAvatarSize
    }

    private var displayName: String {
        let raw = auth.profile?.displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let raw, !raw.isEmpty { return raw }
        return "Speaker"
    }

    private var streak: Int {
        auth.profile?.streakCount ?? 0
    }

    private var isDoingGreat: Bool {
        debugForceCelebrate
            || ProfileCelebration.isDoingGreat(
                streak: streak,
                daysPracticedThisWeek: weekModel.daysPracticed,
                activeDays: activityModel.activeDays
            )
    }

    private var highlightStories: [ProfileHighlightStory] {
        ProfileCelebration.stories(
            displayName: displayName,
            streak: streak,
            totalWords: totalWords,
            totalMinutes: activityModel.totalMinutes,
            daysPracticedThisWeek: weekModel.daysPracticed,
            activeDays: activityModel.activeDays
        )
    }

    private func close() {
        if let onClose {
            onClose()
        } else {
            dismiss()
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 36) {
                        hero
                        statsRow
                        activitySection
                        weekChartSection
                        if RemoteConfigService.shared.isReferralRewardsEnabled {
                            referralSection
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 48)
                }
                .onScrollGeometryChange(for: CGFloat.self) { geometry in
                    -(geometry.contentOffset.y + geometry.contentInsets.top)
                } action: { _, rawPull in
                    // Quantize so tiny scroll jitter doesn’t invalidate the whole profile tree.
                    let next = max(0, (rawPull * 2).rounded() / 2)
                    if abs(next - pullStretch) >= 0.5 {
                        pullStretch = next
                    } else if next == 0, pullStretch != 0 {
                        pullStretch = 0
                    }
                }
                .onScrollPhaseChange { _, phase in
                    let scrolling = phase != .idle
                    if scrolling != isScrolling { isScrolling = scrolling }
                }
                .themeBackground()
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            close()
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Back")
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                    }
                }
                .toolbarTitleDisplayMode(.inline)

                if showExpandedPhoto {
                    ProfilePhotoLightbox(
                        displayName: displayName,
                        isCelebrating: isDoingGreat,
                        uiImage: auth.userId.flatMap(ProfileLocalCache.loadAvatarImage),
                        imageURL: auth.profile?.avatarUrl.flatMap(URL.init(string:)),
                        onClose: { showExpandedPhoto = false },
                        onOpenHighlights: isDoingGreat
                            ? {
                                showExpandedPhoto = false
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                    showHighlightStories = true
                                }
                            }
                            : nil
                    )
                    .zIndex(20)
                }
            }
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showAuth) {
                AuthSheet(
                    showsSkip: false,
                    title: "Sign in for rewards",
                    message: "Link Apple or Google to share your Guest Pass and unlock rewards."
                ) {
                    showInviteReward = true
                }
            }
            .navigationDestination(isPresented: $showInviteReward) {
                InviteRewardView(
                    inviterName: displayName,
                    referralCode: InviteService.shared.referralCode(for: auth.userId)
                )
            }
            .onChange(of: showInviteReward) { _, open in
                guard !open else { return }
                referralCount = InviteService.shared.referralCount
            }
            .task {
                refreshCachedAvatar()
                // Paint with cache immediately, then hydrate.
                refreshDerivedStats(from: sessionService.sessions)
                await Task.yield()
                showSecondaryChrome = true

                async let sessionsRefresh: Void = sessionService.fetchSessions()
                async let profileRefresh: Void = auth.fetchProfile()
                async let subRefresh: Void = subscriptions.refresh()
                async let inviteRefresh: Void = InviteService.shared.refreshRewardState()
                _ = await (sessionsRefresh, profileRefresh, subRefresh, inviteRefresh)
                refreshCachedAvatar()
                referralCount = InviteService.shared.referralCount
                refreshDerivedStats(from: sessionService.sessions)
            }
            .onChange(of: auth.profile?.avatarUrl) { _, _ in
                refreshCachedAvatar()
            }
            .onChange(of: showSettings) { _, open in
                guard !open else { return }
                Task {
                    await auth.fetchProfile()
                    await sessionService.fetchSessions()
                    await subscriptions.refresh()
                    refreshCachedAvatar()
                    refreshDerivedStats(from: sessionService.sessions)
                }
            }
            .fullScreenCover(isPresented: $showHighlightStories) {
                ProfileHighlightStoriesView(
                    stories: highlightStories,
                    displayName: displayName,
                    avatarImage: cachedAvatarImage,
                    avatarURL: cachedAvatarImage == nil
                        ? auth.profile?.avatarUrl.flatMap(URL.init(string:))
                        : nil,
                    onClose: { showHighlightStories = false }
                )
            }
        }
    }

    private func refreshCachedAvatar() {
        guard let userId = auth.userId else {
            cachedAvatarImage = nil
            return
        }
        cachedAvatarImage = ProfileLocalCache.loadAvatarImage(userId: userId)
    }

    private func refreshDerivedStats(from sessions: [SpeakingSession]) {
        totalWords = sessions.compactMap(\.wordCount).reduce(0, +)
        weekModel = PracticeWeekModel(sessions: sessions)
        activityModel = PracticeActivityModel(
            sessions: sessions,
            joinedAt: auth.profile?.createdAt
        )
    }

    // MARK: Hero

    private var hero: some View {
        VStack(spacing: 14) {
            Button {
                if suppressAvatarTap {
                    suppressAvatarTap = false
                    return
                }
                if isDoingGreat {
                    Haptics.soft()
                    showHighlightStories = true
                } else {
                    openExpandedPhoto()
                }
            } label: {
                ZStack {
                    ProfileAvatarView(
                        size: baseAvatarSize,
                        borderWidth: 3,
                        isCelebrating: isDoingGreat,
                        isSubscriber: subscriptions.isProActive,
                        uiImage: cachedAvatarImage,
                        imageURL: cachedAvatarImage == nil
                            ? auth.profile?.avatarUrl.flatMap(URL.init(string:))
                            : nil
                    )

                    AvatarJoinedYearArc(
                        year: joinedYear,
                        avatarSize: baseAvatarSize,
                        isCelebrating: isDoingGreat,
                        showsProMembership: subscriptions.isProActive
                    )
                    .allowsHitTesting(false)
                }
                .scaleEffect(pullScale)
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(showExpandedPhoto)
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.35)
                    .onEnded { _ in
                        guard isDoingGreat, !showExpandedPhoto else { return }
                        suppressAvatarTap = true
                        openExpandedPhoto(haptic: .medium)
                    }
            )
            .accessibilityLabel(
                subscriptions.isProActive
                    ? "Profile photo, joined \(joinedYear), Pro membership"
                    : "Profile photo, joined \(joinedYear)"
            )
            .accessibilityHint(
                isDoingGreat
                    ? "Opens highlights. Long press to expand your photo."
                    : "Expands your photo with a tilt effect"
            )
            .frame(
                width: avatarHeroExtent,
                height: avatarHeroExtent
            )

            VStack(spacing: 4) {
                Text(isDoingGreat ? "You’re on fire" : "Hello")
                    .font(Theme.grotesk(15, weight: .medium))
                    .foregroundStyle(isDoingGreat ? Theme.accent : Theme.textSecondary)

                Text(displayName)
                    .font(Theme.fraunces(32, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                if subscriptions.isMembershipPlanEnabled {
                    Button {
                        Haptics.soft()
                        showSettings = true
                    } label: {
                        membershipChip
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var membershipChip: some View {
        Text(membershipChipTitle)
            .font(Theme.grotesk(13, weight: .semibold))
            .foregroundStyle(subscriptions.isProActive ? Color(red: 0.98, green: 0.97, blue: 0.96) : Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(subscriptions.isProActive ? Theme.accent : Theme.accentMuted)
            .clipShape(Capsule())
            .padding(.top, 6)
            .accessibilityLabel(membershipChipTitle)
    }

    private var membershipChipTitle: String {
        switch subscriptions.membership {
        case .pro:
            return "Oracy Pro"
        case .trial(let endsAt):
            if let endsAt {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                return "Trial · ends \(formatter.string(from: endsAt))"
            }
            return "Oracy Pro Trial"
        case .free:
            let left = subscriptions.weeklyFreeRemaining
            return "Free · \(left) left this week"
        }
    }

    /// Matches arc + avatar bounds so JOINED never clips while pulling.
    private var avatarHeroExtent: CGFloat {
        AvatarJoinedYearArc.layoutDiameter(
            avatarSize: stretchedAvatarSize,
            isCelebrating: isDoingGreat
        )
    }

    private var joinedYear: String {
        let date = auth.profile?.createdAt ?? Date()
        let year = Calendar.current.component(.year, from: date)
        return "\(year)"
    }

    private enum AvatarHaptic {
        case light, medium
    }

    private func openExpandedPhoto(haptic: AvatarHaptic = .light) {
        switch haptic {
        case .light: Haptics.light()
        case .medium: Haptics.medium()
        }
        // Present without animating the profile behind — lightbox owns its entrance.
        showExpandedPhoto = true
    }

    // MARK: Stats — one section under the name

    private var statsRow: some View {
        HStack(spacing: 0) {
            ProfileStatCell(
                icon: "flame.fill",
                iconColor: Color(red: 0.92, green: 0.45, blue: 0.28),
                valueText: "\(streak)",
                label: "day streak",
                gradient: [
                    Color(red: 0.95, green: 0.42, blue: 0.28),
                    Color(red: 0.88, green: 0.58, blue: 0.22)
                ]
            )

            ProfileStatCell(
                icon: "text.bubble.fill",
                iconColor: Color(red: 0.35, green: 0.55, blue: 0.78),
                valueText: formattedWords(totalWords),
                label: "words spoken",
                gradient: [
                    Color(red: 0.32, green: 0.52, blue: 0.82),
                    Color(red: 0.45, green: 0.70, blue: 0.78)
                ]
            )

            ProfileStatCell(
                icon: "globe.americas.fill",
                iconColor: Color(red: 0.40, green: 0.62, blue: 0.48),
                valueText: "40%",
                label: "global rank",
                gradient: [
                    Color(red: 0.28, green: 0.62, blue: 0.48),
                    Color(red: 0.55, green: 0.78, blue: 0.42)
                ]
            )
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
    }

    private func formattedWords(_ n: Int) -> String {
        if n >= 1000 {
            return String(format: "%.1fk", Double(n) / 1000.0)
        }
        return "\(n)"
    }

    // MARK: Practice activity (year heatmap)

    private var activitySection: some View {
        Group {
            if showSecondaryChrome {
                PracticeActivitySection(model: activityModel, streak: streak)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Practice activity")
                        .font(Theme.fraunces(22, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Color.clear.frame(height: 120)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Week chart

    private var weekChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 8) {
                Text("Practice pulse")
                    .font(Theme.fraunces(22, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                ProfileSectionInfoButton(
                    title: "Practice pulse",
                    message: "A closer look at the last seven days — how long you spoke each day, and whether your average is up or down versus the week before.",
                    point: .top,
                    arrowEdge: .bottom
                )

                Spacer(minLength: 8)

                Text(weekModel.currentRangeLabel)
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Text("This week’s speaking rhythm at a glance.")
                .font(Theme.grotesk(13))
                .foregroundStyle(Theme.textSecondary.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Text("Avg \(weekModel.averageSeconds)s · \(weekModel.daysPracticed)/7 days")
                .font(Theme.grotesk(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)

            if showSecondaryChrome {
                PracticeWeekChart(points: weekModel.currentWeek)
                    .frame(height: 160)
            } else {
                Color.clear.frame(height: 160)
            }

            HStack(spacing: 6) {
                Image(systemName: weekModel.deltaSeconds >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 12, weight: .semibold))
                Text(weekModel.comparisonLabel)
                    .font(Theme.grotesk(13, weight: .medium))
            }
            .foregroundStyle(weekModel.deltaSeconds >= 0 ? Theme.success : Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Referral / Guest Pass

    private var referralSection: some View {
        let inviteOnly = RemoteConfigService.shared.isInviteOnlyEnabled
        return VStack(alignment: .leading, spacing: 18) {
            Text(inviteOnly ? "Share Pass & Get Rewards" : "Invite friends. Earn rewards.")
                .font(Theme.fraunces(22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text(inviteOnly
                 ? "Invite friends with a Guest Pass and earn speaking rewards."
                 : "Share your code. Hit milestones for more weekly speaks and Pro time.")
                .font(Theme.grotesk(14))
                .foregroundStyle(Theme.textSecondary)

            Button {
                openRewards()
            } label: {
                if showSecondaryChrome {
                    GuestPassMetalCard(inviterName: displayName, allowsMotion: !isScrolling)
                } else {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(red: 0.48, green: 0.34, blue: 0.28))
                        .frame(height: 232)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens reward and referral code")

            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(referralCount == 1 ? "1 friend joined" : "\(referralCount) friends joined")
                    .font(Theme.grotesk(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            Button {
                openRewards()
            } label: {
                Text("View Rewards")
                    .font(Theme.grotesk(16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func openRewards() {
        Haptics.soft()
        guard auth.isLoggedIn else {
            showAuth = true
            return
        }
        showInviteReward = true
    }
}

// MARK: - Stat cell

private struct ProfileStatCell: View {
    let icon: String
    let iconColor: Color
    let valueText: String
    let label: String
    let gradient: [Color]

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(height: 18)

            Text(valueText)
                .font(Theme.grotesk(36, weight: .bold))
                .foregroundStyle(
                    LinearGradient(
                        colors: gradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .monospacedDigit()
                .minimumScaleFactor(0.7)
                .lineLimit(1)

            Text(label)
                .font(Theme.grotesk(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(valueText) \(label)")
    }
}

// MARK: - Week model + chart

struct PracticeDayPoint: Identifiable, Equatable {
    let date: Date
    let seconds: Double

    var id: Date { date }
}

struct PracticeWeekModel {
    let currentWeek: [PracticeDayPoint]
    let previousWeek: [PracticeDayPoint]

    init(sessions: [SpeakingSession]) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let currentStart = cal.date(byAdding: .day, value: -6, to: today)!
        let previousStart = cal.date(byAdding: .day, value: -13, to: today)!
        let previousEnd = cal.date(byAdding: .day, value: -7, to: today)!

        func seconds(on day: Date) -> Double {
            sessions.reduce(0) { sum, session in
                guard let created = session.createdAt,
                      cal.isDate(created, inSameDayAs: day) else { return sum }
                return sum + (session.durationSeconds ?? 0)
            }
        }

        currentWeek = (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: currentStart)!
            return PracticeDayPoint(date: day, seconds: seconds(on: day))
        }
        previousWeek = (0..<7).map { offset in
            let day = cal.date(byAdding: .day, value: offset, to: previousStart)!
            return PracticeDayPoint(date: day, seconds: seconds(on: day))
        }
        _ = previousEnd
    }

    var averageSeconds: Int {
        let total = currentWeek.map(\.seconds).reduce(0, +)
        return Int((total / 7).rounded())
    }

    var daysPracticed: Int {
        currentWeek.filter { $0.seconds > 0 }.count
    }

    var previousAverage: Int {
        let total = previousWeek.map(\.seconds).reduce(0, +)
        return Int((total / 7).rounded())
    }

    var deltaSeconds: Int { averageSeconds - previousAverage }

    var currentRangeLabel: String {
        rangeLabel(from: currentWeek.first?.date, to: currentWeek.last?.date)
    }

    var previousRangeLabel: String {
        rangeLabel(from: previousWeek.first?.date, to: previousWeek.last?.date)
    }

    var comparisonLabel: String {
        let absDelta = abs(deltaSeconds)
        let direction = deltaSeconds >= 0 ? "up" : "down"
        return "\(direction) \(absDelta)s vs \(previousRangeLabel)"
    }

    private func rangeLabel(from start: Date?, to end: Date?) -> String {
        guard let start, let end else { return "" }
        let f = DateFormatter()
        f.dateFormat = "d MMM"
        return "\(f.string(from: start)) – \(f.string(from: end))"
    }
}

private struct PracticeWeekChart: View {
    let points: [PracticeDayPoint]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 0 → 1 drives the line rising from the baseline.
    @State private var drawProgress: CGFloat = 0
    /// Left-to-right reveal of the stroke.
    @State private var wipeProgress: CGFloat = 0

    private var yMax: Double {
        max(points.map(\.seconds).max() ?? 0, 1) * 1.15
    }

    var body: some View {
        Chart(points) { point in
            LineMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Seconds", point.seconds * Double(drawProgress))
            )
            .foregroundStyle(Theme.accent)
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.catmullRom)

            PointMark(
                x: .value("Day", point.date, unit: .day),
                y: .value("Seconds", point.seconds * Double(drawProgress))
            )
            .foregroundStyle(Theme.accent.opacity(Double(drawProgress)))
            .symbolSize(18 + 10 * drawProgress)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(shortDay(date))
                            .font(Theme.grotesk(10, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                    .foregroundStyle(Theme.textSecondary.opacity(0.25))
                AxisValueLabel {
                    if let n = value.as(Double.self), n >= 0 {
                        Text("\(Int(n))s")
                            .font(Theme.grotesk(10))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        // Small floor padding so baseline dots/line aren't clipped by the plot edge.
        .chartYScale(domain: (-yMax * 0.04)...yMax)
        .chartPlotStyle { plot in
            plot
                .padding(.vertical, 4)
                .mask {
                    Rectangle()
                        .scale(x: max(wipeProgress, 0.001), y: 1, anchor: .leading)
                }
        }
        .onAppear { playEntrance() }
        .onChange(of: points) { _, _ in
            playEntrance(reset: true)
        }
    }

    private func playEntrance(reset: Bool = false) {
        if reduceMotion {
            drawProgress = 1
            wipeProgress = 1
            return
        }
        if reset {
            drawProgress = 0
            wipeProgress = 0
        }
        withAnimation(.easeOut(duration: 0.85)) {
            drawProgress = 1
        }
        withAnimation(.easeInOut(duration: 1.05).delay(0.05)) {
            wipeProgress = 1
        }
    }

    private func shortDay(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE"
        return f.string(from: date)
    }
}

// MARK: - Metal Guest Pass (gyro shine)

struct GuestPassMetalCard: View {
    var inviterName: String = "a friend"
    /// Pause gyro while a parent ScrollView is moving — live 3D + gradient
    /// invalidation every frame is what made Reward / Profile hitch.
    var allowsMotion: Bool = true

    @StateObject private var motion = CardMotionSampler()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Single warm bronze family — no competing cool hues.
    private let metal: [Color] = [
        Color(red: 0.42, green: 0.30, blue: 0.24),
        Color(red: 0.58, green: 0.40, blue: 0.32),
        Color(red: 0.48, green: 0.34, blue: 0.28),
        Color(red: 0.36, green: 0.26, blue: 0.22)
    ]

    private var shineX: CGFloat { motion.nx }
    private var tiltEnabled: Bool { !reduceMotion }

    var body: some View {
        ZStack(alignment: .topLeading) {
            metalFace
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .drawingGroup()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    Text("Oracy")
                        .font(Theme.fraunces(18, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.95))
                    Spacer(minLength: 12)
                    Image(systemName: "waveform")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }

                Spacer(minLength: 28)

                Text("GUEST PASS")
                    .font(Theme.grotesk(11, weight: .bold))
                    .tracking(2)
                    .foregroundStyle(Color.white.opacity(0.58))

                Spacer().frame(height: 14)

                Text("Invite by \(inviterName)")
                    .font(Theme.fraunces(24, weight: .semibold))
                    .foregroundStyle(Color.white)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 28)

                HStack(alignment: .center) {
                    Text("REFERRAL")
                        .font(Theme.grotesk(10, weight: .semibold))
                        .tracking(1.6)
                        .foregroundStyle(Color.white.opacity(0.45))
                    Spacer(minLength: 12)
                    Text("SHARE TO UNLOCK")
                        .font(Theme.grotesk(10, weight: .semibold))
                        .tracking(1.2)
                        .foregroundStyle(Color.white.opacity(0.72))
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 26)
        }
        .frame(height: 232)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.18), radius: 12, y: 6)
        .rotation3DEffect(
            .degrees(tiltEnabled ? Double(motion.nx - 0.5) * 3.2 : 0),
            axis: (x: 0, y: 1, z: 0),
            perspective: 0.7
        )
        .rotation3DEffect(
            .degrees(tiltEnabled ? Double(0.5 - motion.ny) * 2.4 : 0),
            axis: (x: 1, y: 0, z: 0),
            perspective: 0.7
        )
        .task {
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            syncMotion()
        }
        .onChange(of: allowsMotion) { _, _ in
            syncMotion()
        }
        .onDisappear {
            motion.stop()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Oracy Guest Pass, invite by \(inviterName)")
    }

    private var metalFace: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: metal,
                        startPoint: UnitPoint(x: 0.15 + shineX * 0.08, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.82, green: 0.62, blue: 0.48).opacity(0.35),
                            .clear,
                            Color(red: 0.32, green: 0.22, blue: 0.18).opacity(0.25)
                        ],
                        startPoint: UnitPoint(x: shineX, y: 0),
                        endPoint: UnitPoint(x: 1 - shineX * 0.4, y: 1)
                    )
                )

            if tiltEnabled {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.28),
                                .clear
                            ],
                            startPoint: UnitPoint(x: shineX - 0.18, y: 0.1),
                            endPoint: UnitPoint(x: shineX + 0.18, y: 0.9)
                        )
                    )
                    .blendMode(.softLight)
            }

            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
        }
    }

    private func syncMotion() {
        if allowsMotion, !reduceMotion {
            motion.start()
        } else {
            motion.stop()
        }
    }
}

@MainActor
private final class CardMotionSampler: ObservableObject {
    @Published var nx: CGFloat = 0.5
    @Published var ny: CGFloat = 0.5

    private let manager = CMMotionManager()
    private var timer: AnyCancellable?

    func start() {
        guard timer == nil, manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1 / 20
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical)
        timer = Timer.publish(every: 1 / 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.tick()
            }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        guard let motion = manager.deviceMotion else { return }
        let roll = CGFloat(motion.attitude.roll) / (.pi * 1.8)
        let pitch = CGFloat(motion.attitude.pitch) / (.pi * 1.4)
        let targetX = min(1, max(0, roll + 0.5))
        let targetY = min(1, max(0, pitch + 0.5))
        let nextX = nx + (targetX - nx) * 0.07
        let nextY = ny + (targetY - ny) * 0.07
        // Skip tiny updates so SwiftUI isn't invalidated 20×/sec for noise.
        if abs(nextX - nx) > 0.004 { nx = nextX }
        if abs(nextY - ny) > 0.004 { ny = nextY }
    }
}
