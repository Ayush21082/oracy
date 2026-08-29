import SwiftUI

struct HistoryView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sessionService = SessionService.shared
    @State private var player = AudioPlayerService()
    @State private var sessionPendingDelete: SpeakingSession?
    @State private var exitingIds: Set<UUID> = []
    @State private var detailSessionId: UUID?

    var body: some View {
        NavigationStack {
            Group {
                if sessionService.isLoading && sessionService.sessions.isEmpty {
                    ProgressView()
                        .tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if sessionService.sessions.isEmpty {
                    emptyState
                        .transition(.opacity)
                } else {
                    sessionList
                }
            }
            .animation(.easeInOut(duration: 0.35), value: sessionService.sessions.isEmpty)
            .themeBackground()
            .navigationTitle("History")
            .toolbarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .largeTitle) {
                    Text("History")
                        .font(Theme.fraunces(34, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .navigationDestination(item: $detailSessionId) { sessionId in
                if let session = sessionService.sessions.first(where: { $0.id == sessionId }) {
                    HistoryDetailView(session: session, player: player)
                } else {
                    ProgressView()
                        .tint(Theme.accent)
                }
            }
            .task {
                await sessionService.fetchSessions()
            }
            .trackScreen("history")
            .onAppear {
                AnalyticsService.shared.track(.historyOpened)
            }
            .onChange(of: detailSessionId) { _, id in
                guard let id else { return }
                AnalyticsService.shared.track(.historyDetailOpened, [
                    "session_id": id.uuidString.lowercased()
                ])
            }
            .alert("Delete this session?", isPresented: .init(
                get: { sessionPendingDelete != nil },
                set: { if !$0 { sessionPendingDelete = nil } }
            )) {
                Button("Delete", role: .destructive) {
                    if let session = sessionPendingDelete {
                        Task { await delete(session) }
                    }
                }
                Button("Cancel", role: .cancel) {
                    sessionPendingDelete = nil
                }
            } message: {
                Text("This removes the recording and transcript from your history.")
            }
            .onDisappear {
                player.stop()
            }
        }
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "waveform")
                    .font(.system(size: 40))
                    .foregroundStyle(Theme.textSecondary.opacity(0.45))
                Text("No sessions yet")
                    .font(Theme.fraunces(24, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Complete a speaking challenge and your recordings will show up here.")
                    .font(Theme.grotesk(16))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
            .frame(maxWidth: .infinity)
            .containerRelativeFrame(.vertical)
        }
        .emojiPullToRefresh {
            await sessionService.fetchSessions()
        }
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(sessionService.sessions) { session in
                    HistorySessionCard(
                        session: session,
                        player: player,
                        isDiscarding: exitingIds.contains(session.id),
                        onOpenDetail: {
                            Haptics.light()
                            detailSessionId = session.id
                        },
                        onDelete: { sessionPendingDelete = session }
                    )
                    .zIndex(exitingIds.contains(session.id) ? 2 : 0)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .contentMargins(.top, 0, for: .scrollContent)
        .emojiPullToRefresh {
            await sessionService.fetchSessions()
        }
    }

    private func delete(_ session: SpeakingSession) async {
        player.stopIfPlaying(sessionId: session.id)
        sessionPendingDelete = nil

        withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.08)) {
            _ = exitingIds.insert(session.id)
        }

        // Let the card's multi-stage discard finish before removing data.
        let waitMs = reduceMotion ? 120 : 720
        try? await Task.sleep(for: .milliseconds(waitMs))

        do {
            try await sessionService.deleteSession(session)
            exitingIds.remove(session.id)
            AnalyticsService.shared.track(.sessionDeleted, [
                "session_id": session.id.uuidString.lowercased()
            ])
        } catch {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                _ = exitingIds.remove(session.id)
            }
            AppErrorCenter.shared.present(
                title: FriendlyErrorCopy.deleteTitle,
                message: FriendlyErrorCopy.deleteMessage,
                retry: { Task { await delete(session) } }
            )
        }
    }
}

// MARK: - Card

struct HistorySessionCard: View {
    let session: SpeakingSession
    var player: AudioPlayerService
    var isDiscarding: Bool = false
    let onOpenDetail: () -> Void
    let onDelete: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var audioURL: URL?
    @State private var isLoadingAudio = false
    @State private var loadFailed = false

    /// Discard choreography
    @State private var lift = false
    @State private var fling = false
    @State private var collapse = false

    private var isThisPlaying: Bool {
        player.activeSessionId == session.id && player.isPlaying
    }

    private var isThisLoaded: Bool {
        player.activeSessionId == session.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            audioRow
            if let transcript = session.transcript, !transcript.isEmpty {
                Text(transcript)
                    .font(Theme.grotesk(14))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18)
        .background(Theme.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .shadow(
            color: Theme.shadow,
            radius: lift && !fling ? 18 : 8,
            y: lift && !fling ? 10 : 2
        )
        .rotation3DEffect(
            .degrees(fling ? 62 : (lift ? -6 : 0)),
            axis: (x: 0.15, y: 1, z: 0.08),
            perspective: 0.65
        )
        .rotationEffect(.degrees(fling ? 14 : (lift ? -2 : 0)))
        .scaleEffect(fling ? 0.55 : (lift ? 1.04 : 1), anchor: .topTrailing)
        .offset(x: fling ? 140 : 0, y: fling ? -90 : (lift ? -6 : 0))
        .blur(radius: fling ? 5 : 0)
        .opacity(fling ? 0 : 1)
        .frame(maxHeight: collapse ? 0 : nil)
        .clipped()
        .allowsHitTesting(!isDiscarding)
        .contentShape(RoundedRectangle(cornerRadius: Theme.cornerRadius))
        .onTapGesture {
            onOpenDetail()
        }
        .task(id: session.id) {
            await prepareAudio()
        }
        .onChange(of: isDiscarding) { _, discarding in
            guard discarding else {
                lift = false
                fling = false
                collapse = false
                return
            }
            Task { await runDiscardAnimation() }
        }
    }

    private func runDiscardAnimation() async {
        if reduceMotion {
            Haptics.medium()
            withAnimation(.easeOut(duration: 0.15)) {
                fling = true
                collapse = true
            }
            return
        }

        // 1) Lift off the list — like picking up a card
        Haptics.medium()
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            lift = true
        }
        try? await Task.sleep(for: .milliseconds(160))

        // 2) Fling toward trash corner with a 3D toss
        Haptics.rigid()
        withAnimation(.timingCurve(0.2, 0.8, 0.2, 1, duration: 0.48)) {
            fling = true
        }
        try? await Task.sleep(for: .milliseconds(280))

        // 3) Collapse the slot so the list closes smoothly
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            collapse = true
        }
        Haptics.soft()
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                Text(session.challenge?.prompt ?? "Speaking practice")
                    .font(Theme.fraunces(20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(dateTimeLabel)
                    .font(Theme.grotesk(13))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 8)

            Button(action: onOpenDetail) {
                Image(systemName: "chart.bar.doc.horizontal")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BounceButtonStyle(pressedScale: 0.82, haptic: .light))
            .accessibilityLabel("Open feedback")
            .accessibilityHint("Shows detailed stats for this recording")

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BounceButtonStyle(pressedScale: 0.82, haptic: .medium))
            .accessibilityLabel("Delete session")
        }
    }

    private var audioRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await togglePlayback() }
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentMuted)
                        .frame(width: 44, height: 44)
                    if isLoadingAudio {
                        ProgressView()
                            .tint(Theme.accent)
                    } else {
                        Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .offset(x: isThisPlaying ? 0 : 1)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
            }
            .buttonStyle(BounceButtonStyle(pressedScale: 0.88, haptic: .soft))
            .disabled(loadFailed || (audioURL == nil && !isLoadingAudio))
            .accessibilityLabel(isThisPlaying ? "Pause" : "Play recording")

            PlaybackVisualizer(
                levels: isThisPlaying ? player.levels : Array(repeating: 0.14, count: 28),
                isActive: isThisPlaying
            )
            .frame(maxWidth: .infinity)
            .frame(height: 36)

            Text(timeLabel)
                .font(Theme.grotesk(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .frame(minWidth: 40, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }

    private var dateTimeLabel: String {
        guard let date = session.createdAt else { return "" }
        let datePart: String
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            datePart = "Today"
        } else if calendar.isDateInYesterday(date) {
            datePart = "Yesterday"
        } else {
            let df = DateFormatter()
            df.dateFormat = "MMM d"
            datePart = df.string(from: date)
        }
        let tf = DateFormatter()
        tf.dateFormat = "h:mm a"
        return "\(datePart) · \(tf.string(from: date))"
    }

    private var timeLabel: String {
        if isThisLoaded, player.duration > 0 {
            let t = isThisPlaying || player.currentTime > 0 ? player.currentTime : player.duration
            return format(t)
        }
        if let seconds = session.durationSeconds, seconds > 0 {
            return format(seconds)
        }
        return "—"
    }

    private func format(_ time: TimeInterval) -> String {
        let s = Int(max(0, time))
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func prepareAudio() async {
        loadFailed = false
        isLoadingAudio = true
        defer { isLoadingAudio = false }
        audioURL = await SessionService.shared.audioURL(for: session)
        loadFailed = audioURL == nil
    }

    private func togglePlayback() async {
        if isThisLoaded {
            player.toggle()
            return
        }
        isLoadingAudio = true
        defer { isLoadingAudio = false }

        var url = audioURL
        if url == nil {
            url = await SessionService.shared.audioURL(for: session)
        }
        guard let url else {
            loadFailed = true
            return
        }
        audioURL = url
        do {
            try player.load(url: url, sessionId: session.id)
            player.play()
        } catch {
            loadFailed = true
        }
    }
}

// MARK: - Visualizer

struct PlaybackVisualizer: View {
    let levels: [CGFloat]
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isActive ? Theme.accent : Theme.textSecondary.opacity(0.25))
                    .frame(width: 3, height: max(4, levels[index] * 32))
                    .animation(
                        reduceMotion || !isActive ? nil : .easeOut(duration: 0.05),
                        value: levels[index]
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityHidden(true)
    }
}
