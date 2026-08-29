import SwiftUI

/// Full feedback + audio detail for a past History session — plain, title-led layout.
struct HistoryDetailView: View {
    let session: SpeakingSession
    var player: AudioPlayerService

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scoreRevealed = false
    @State private var audioURL: URL?
    @State private var isLoadingAudio = false
    @State private var loadFailed = false

    private var isThisPlaying: Bool {
        player.activeSessionId == session.id && player.isPlaying
    }

    private var isThisLoaded: Bool {
        player.activeSessionId == session.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 40) {
                header
                recordingSection

                if let transcript = session.transcript, !transcript.isEmpty {
                    plainSection(title: "Transcript") {
                        Text(transcript)
                            .font(Theme.grotesk(16))
                            .foregroundStyle(Theme.textPrimary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if let feedback = session.feedbackJson {
                    SessionFeedbackSections(
                        feedback: feedback,
                        scoreRevealed: scoreRevealed,
                        style: .plain
                    )
                } else {
                    plainSection(title: "Feedback unavailable") {
                        Text("This session doesn’t have saved analysis yet. Complete a new practice to see detailed stats.")
                            .font(Theme.grotesk(16))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .themeBackground()
        .navigationBarTitleDisplayMode(.inline)
        .task(id: session.id) {
            await prepareAudio()
            withAnimation(reduceMotion ? .none : .themeBounce) {
                scoreRevealed = true
            }
        }
        .onDisappear {
            if player.activeSessionId == session.id {
                player.stop()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(session.challenge?.prompt ?? "Speaking practice")
                .font(Theme.fraunces(30, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(dateTimeLabel)
                .font(Theme.grotesk(14))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recordingSection: some View {
        plainSection(title: "Recording") {
            HStack(spacing: 14) {
                Button {
                    Task { await togglePlayback() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(Theme.accentMuted)
                            .frame(width: 48, height: 48)
                        if isLoadingAudio {
                            ProgressView().tint(Theme.accent)
                        } else {
                            Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                                .offset(x: isThisPlaying ? 0 : 1)
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
                    .font(Theme.grotesk(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .frame(minWidth: 40, alignment: .trailing)
            }
        }
    }

    private func plainSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(Theme.fraunces(22, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
            df.dateFormat = "MMM d, yyyy"
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
