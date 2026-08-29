import AVFoundation
import Foundation

enum RecordingState: Equatable {
    case idle
    case recording
    case paused
    case finished
}

@MainActor
@Observable
final class AudioRecorderService: NSObject {
    var state: RecordingState = .idle
    var elapsedSeconds: TimeInterval = 0
    var remainingSeconds: TimeInterval = 60
    var audioLevels: [CGFloat] = Array(repeating: 0.1, count: 30)
    var permissionGranted = false
    var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var recordingURL: URL?
    private let maxDuration: TimeInterval = 60

    var recordingFileURL: URL? { recordingURL }

    func requestPermission() async -> Bool {
        let granted = await AVAudioApplication.requestRecordPermission()
        permissionGranted = granted
        if !granted {
            errorMessage = "Microphone access is required to practice speaking."
        }
        return granted
    }

    func startRecording() throws {
        // Already live — don't restart (Home → Recording auto-start can fire twice).
        if state == .recording || state == .paused { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        recordingURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder?.isMeteringEnabled = true
        recorder?.delegate = self
        recorder?.record()

        state = .recording
        elapsedSeconds = 0
        remainingSeconds = maxDuration
        startTimer()
    }

    func pauseRecording() {
        recorder?.pause()
        state = .paused
        timer?.invalidate()
    }

    func resumeRecording() {
        recorder?.record()
        state = .recording
        startTimer()
    }

    func stopRecording() {
        recorder?.stop()
        timer?.invalidate()
        state = .finished
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let recorder, recorder.isRecording else { return }

        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0)
        let normalized = max(0.05, CGFloat((power + 50) / 50))
        audioLevels.removeFirst()
        audioLevels.append(normalized)

        elapsedSeconds = recorder.currentTime
        remainingSeconds = max(0, maxDuration - elapsedSeconds)

        if elapsedSeconds >= maxDuration {
            stopRecording()
        }
    }

    func reset() {
        timer?.invalidate()
        recorder?.stop()
        recorder = nil
        recordingURL = nil
        state = .idle
        elapsedSeconds = 0
        remainingSeconds = maxDuration
        audioLevels = Array(repeating: 0.1, count: 30)
        errorMessage = nil
    }

    var timerPhase: TimerPhase {
        switch remainingSeconds {
        case 6...: return .normal
        case 1...5: return .countdown
        default: return .finished
        }
    }

    enum TimerPhase {
        case normal, warning, countdown, finished
    }

    var displayTimerPhase: TimerPhase {
        switch remainingSeconds {
        case 21...: return .normal
        case 6...20: return .warning
        case 1...5: return .countdown
        default: return .finished
        }
    }
}

extension AudioRecorderService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            if flag { state = .finished }
        }
    }
}
