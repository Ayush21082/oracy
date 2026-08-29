import SwiftUI
import UIKit
import AVFoundation

struct RecordingView: View {
    let challenge: Challenge

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var recorder = AudioRecorderService()
    @State private var showAnalysis = false
    @State private var showMicPermissionPage = false
    @State private var friendlyError: RecordingFriendlyError?

    private enum RecordingFriendlyError: Identifiable {
        case upload
        case generic

        var id: String {
            switch self {
            case .upload: return "upload"
            case .generic: return "generic"
            }
        }

        var title: String {
            switch self {
            case .upload: return FriendlyErrorCopy.uploadTitle
            case .generic: return FriendlyErrorCopy.defaultTitle
            }
        }

        var message: String {
            switch self {
            case .upload: return FriendlyErrorCopy.uploadMessage
            case .generic: return FriendlyErrorCopy.defaultMessage
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ThemeBackground()

                VStack(spacing: 32) {
                    timerDisplay
                    promptText
                    waveformView
                    controls
                }
                .padding(24)
                .opacity(showMicPermissionPage ? 0 : 1)
                .allowsHitTesting(!showMicPermissionPage)

                if showMicPermissionPage {
                    MicrophonePermissionView(
                        onGranted: {
                            withAnimation(.easeOut(duration: 0.25)) {
                                showMicPermissionPage = false
                            }
                            startRecording()
                        },
                        onDismiss: { dismiss() }
                    )
                    .transition(.opacity)
                    .zIndex(10)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        AnalyticsService.shared.track(.recordingCancelled, [
                            "challenge_id": challenge.id.uuidString.lowercased()
                        ])
                        dismiss()
                    }
                        .disabled(showAnalysis || showMicPermissionPage)
                }
            }
            .toolbar(showMicPermissionPage ? .hidden : .automatic, for: .navigationBar)
            .fullScreenCover(item: $friendlyError) { error in
                FriendlyErrorView(
                    title: error.title,
                    message: error.message,
                    onRetry: {
                        let kind = error
                        friendlyError = nil
                        switch kind {
                        case .upload:
                            showAnalysis = true
                        case .generic:
                            startRecording()
                        }
                    },
                    onDismiss: {
                        let kind = error
                        friendlyError = nil
                        if kind == .upload {
                            dismiss()
                        }
                    }
                )
            }
            .fullScreenCover(isPresented: $showAnalysis, onDismiss: {
                // If analysis failed, host already dismissed and set friendlyError.
            }) {
                if let audioURL = recorder.recordingFileURL {
                    AnalysisRevealHost(
                        challenge: challenge,
                        audioURL: audioURL,
                        durationSeconds: recorder.elapsedSeconds,
                        onDone: { dismiss() },
                        onError: {
                            showAnalysis = false
                            Task { @MainActor in
                                try? await Task.sleep(for: .milliseconds(350))
                                friendlyError = .upload
                            }
                        }
                    )
                }
            }
            .task {
                await prepareRecording()
            }
            .trackScreen("recording", ["challenge_id": challenge.id.uuidString.lowercased()])
            .onChange(of: recorder.state) { _, newState in
                if newState == .finished {
                    AnalyticsService.shared.track(.recordingCompleted, [
                        "challenge_id": challenge.id.uuidString.lowercased(),
                        "duration_seconds": String(Int(recorder.elapsedSeconds.rounded()))
                    ])
                    showAnalysis = true
                }
            }
            .onChange(of: recorder.remainingSeconds) { oldValue, newValue in
                let oldSec = Int(oldValue)
                let newSec = Int(newValue)
                guard oldSec != newSec, newSec >= 0, newSec <= 5 else { return }
                Haptics.rigid()
            }
        }
    }

    private func prepareRecording() async {
        guard recorder.state == .idle else { return }

        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startRecording()
        case .denied, .undetermined:
            showMicPermissionPage = true
        @unknown default:
            showMicPermissionPage = true
        }
    }

    private var timerDisplay: some View {
        VStack(spacing: 8) {
            Text(timeString(from: recorder.remainingSeconds))
                .font(.system(size: 56, weight: .light, design: .monospaced))
                .foregroundStyle(timerColor)
                .contentTransition(.numericText())
                .scaleEffect(recorder.displayTimerPhase == .countdown ? 1.04 : 1)
                .animation(reduceMotion ? nil : .themeBounceSnappy, value: Int(recorder.remainingSeconds))
                .accessibilityLabel("\(Int(recorder.remainingSeconds)) seconds remaining")

            if recorder.displayTimerPhase == .finished && recorder.state == .finished {
                Text("Time's up. Nice work.")
                    .font(Theme.grotesk(17, weight: .medium))
                    .foregroundStyle(Theme.success)
            }
        }
    }

    private var timerColor: Color {
        switch recorder.displayTimerPhase {
        case .normal: return Theme.textPrimary
        case .warning: return Theme.textPrimary
        case .countdown: return Theme.accent
        case .finished: return Theme.success
        }
    }

    private var promptText: some View {
        Text(challenge.prompt)
            .font(Theme.fraunces(20, weight: .medium))
            .multilineTextAlignment(.center)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
    }

    private var waveformView: some View {
        HStack(spacing: 3) {
            ForEach(recorder.audioLevels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(recorder.state == .recording ? Theme.accent : Theme.textSecondary.opacity(0.3))
                    .frame(width: 4, height: max(4, recorder.audioLevels[index] * 60))
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.05), value: recorder.audioLevels[index])
            }
        }
        .frame(height: 60)
        .accessibilityLabel(recorder.state == .recording ? "Recording" : recorder.state == .paused ? "Paused" : "Not recording")
    }

    private var controls: some View {
        HStack(spacing: 40) {
            if recorder.state == .idle {
                ProgressView()
                    .tint(Theme.accent)
                    .accessibilityLabel("Starting recording")
            } else if recorder.state == .recording {
                Button {
                    recorder.pauseRecording()
                } label: {
                    Image(systemName: "pause.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(BounceButtonStyle())
                .accessibilityLabel("Pause recording")

                Button {
                    recorder.stopRecording()
                } label: {
                    RecordButton(isRecording: true)
                }
                .buttonStyle(BounceButtonStyle(pressedScale: 0.9, haptic: .medium))
                .accessibilityLabel("Stop recording")
            } else if recorder.state == .paused {
                Button {
                    recorder.resumeRecording()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(BounceButtonStyle(haptic: .medium))
                .accessibilityLabel("Resume recording")

                Button {
                    recorder.stopRecording()
                } label: {
                    RecordButton(isRecording: true)
                }
                .buttonStyle(BounceButtonStyle(pressedScale: 0.9, haptic: .medium))
                .accessibilityLabel("Stop recording")
            }
        }
        .frame(minHeight: Theme.minTapTarget)
    }

    private func startRecording() {
        do {
            try recorder.startRecording()
            Haptics.medium()
            AnalyticsService.shared.track(.recordingStarted, [
                "challenge_id": challenge.id.uuidString.lowercased()
            ])
        } catch {
            Haptics.error()
            friendlyError = .generic
        }
    }

    private func timeString(from seconds: TimeInterval) -> String {
        let s = Int(max(0, seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

struct RecordButton: View {
    let isRecording: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        ZStack {
            if isRecording && !reduceMotion {
                Circle()
                    .fill(Theme.accent.opacity(0.2))
                    .frame(width: 80, height: 80)
                    .scaleEffect(pulse ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: pulse)
                    .onAppear { pulse = true }
            }

            Circle()
                .fill(isRecording ? Theme.accent : Theme.accent)
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: isRecording ? 8 : 32)
                        .fill(Color(red: 0.98, green: 0.97, blue: 0.96))
                        .frame(width: isRecording ? 24 : 56, height: isRecording ? 24 : 56)
                )
        }
    }
}
