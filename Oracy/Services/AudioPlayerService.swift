import AVFoundation
import Foundation

@MainActor
@Observable
final class AudioPlayerService: NSObject {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var levels: [CGFloat] = Array(repeating: 0.12, count: 28)
    var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var playingSessionId: UUID?

    var activeSessionId: UUID? { playingSessionId }

    func load(url: URL, sessionId: UUID) throws {
        stop()
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)

        player = try AVAudioPlayer(contentsOf: url)
        player?.delegate = self
        player?.isMeteringEnabled = true
        player?.prepareToPlay()
        duration = player?.duration ?? 0
        currentTime = 0
        playingSessionId = sessionId
        isPlaying = false
        levels = Array(repeating: 0.12, count: 28)
    }

    func toggle() {
        guard let player else { return }
        if player.isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        player?.play()
        isPlaying = true
        startMetering()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        timer?.invalidate()
        dampenLevels()
    }

    func stop() {
        timer?.invalidate()
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        playingSessionId = nil
        dampenLevels()
    }

    func stopIfPlaying(sessionId: UUID) {
        if playingSessionId == sessionId {
            stop()
        }
    }

    private func startMetering() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    private func tick() {
        guard let player, player.isPlaying else { return }
        player.updateMeters()
        let power = player.averagePower(forChannel: 0)
        let normalized = max(0.08, CGFloat((power + 50) / 50))
        levels.removeFirst()
        levels.append(normalized)
        currentTime = player.currentTime
        duration = player.duration
    }

    private func dampenLevels() {
        levels = Array(repeating: 0.12, count: 28)
    }
}

extension AudioPlayerService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            isPlaying = false
            currentTime = duration
            timer?.invalidate()
            dampenLevels()
        }
    }
}
