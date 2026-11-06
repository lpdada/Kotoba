import AVFoundation
import Foundation

/// Records and plays back shadowing attempts.
///
/// Not actor isolated: AVFoundation callbacks arrive on background queues, so
/// published state is funnelled through the main queue (same pattern as
/// `ClipPlayer` and `SpeechService`).
final class ShadowingRecorder: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum Phase: Equatable {
        case idle
        case recording
        case playing
        case denied
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var elapsed: Double = 0

    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var startedAt: Date?
    private var destination: URL?

    var isRecording: Bool { phase == .recording }
    var isPlaying: Bool { phase == .playing }

    deinit {
        timer?.invalidate()
        recorder?.stop()
        player?.stop()
    }

    // MARK: Permission

    func requestPermission() async -> Bool {
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            return true
        case .denied:
            return false
        default:
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
    }

    // MARK: Recording

    @discardableResult
    func startRecording(to url: URL) -> Bool {
        stopPlayback()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
            try session.setActive(true)
        } catch {
            publish(.failed("无法启用录音会话：\(error.localizedDescription)"))
            return false
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            recorder.isMeteringEnabled = false
            guard recorder.record() else {
                publish(.failed("录音启动失败"))
                return false
            }
            self.recorder = recorder
            self.destination = url
            self.startedAt = Date()
            self.elapsed = 0
            publish(.recording)
            startTimer()
            return true
        } catch {
            publish(.failed("录音失败：\(error.localizedDescription)"))
            return false
        }
    }

    /// Stops recording and returns the file plus its duration.
    func stopRecording() -> (url: URL, duration: Double)? {
        guard let recorder, let url = destination else {
            stopTimer()
            publish(.idle)
            return nil
        }
        let duration = max(Date().timeIntervalSince(startedAt ?? Date()), recorder.currentTime, 0.1)
        recorder.stop()
        self.recorder = nil
        self.destination = nil
        self.startedAt = nil
        stopTimer()
        publish(.idle)
        return (url, duration)
    }

    // MARK: Playback

    func play(url: URL) {
        if recorder != nil { stopRecording() }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try session.setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else {
                publish(.failed("无法播放录音"))
                return
            }
            self.player = player
            publish(.playing)
        } catch {
            publish(.failed("播放失败：\(error.localizedDescription)"))
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        if phase == .playing { publish(.idle) }
    }

    func resetError() {
        if case .failed = phase { publish(.idle) }
        if phase == .denied { publish(.idle) }
    }

    // MARK: AV

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        self.player = nil
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .playing else { return }
            self.phase = .idle
        }
    }

    // MARK: Internals

    private func startTimer() {
        stopTimer()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isRecording, let startedAt = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        elapsed = 0
    }

    private func publish(_ phase: Phase) {
        DispatchQueue.main.async { [weak self] in
            self?.phase = phase
        }
    }
}
