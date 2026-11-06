import AVFoundation
import Foundation
import Network

/// Single entry point for every read-aloud in the app.
///
/// Three modes, all with the same silent-fallback guarantee:
/// 1. `server`     — POST to the user's own edge-tts proxy (default when an
///                   address is configured, and this build pre-fills one);
/// 2. `edgeDirect` — Microsoft's endpoint directly;
/// 3. `systemOnly` — never touch the network.
///
/// Long text is split into ≤1000-character chunks (the proxy's own limit) and
/// played back in order. Any failure records the time and immediately speaks
/// with the system voice — nothing is ever surfaced mid-study.
final class SpeechService: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false
    @Published private(set) var lastSpoken: String?
    /// "edge", "server" or "system" — shown in settings.
    @Published private(set) var lastEngine: String = "system"

    private enum Engine {
        case edge
        case server
    }

    private let synthesizer = AVSpeechSynthesizer()
    private let cache = EdgeTTSCache.shared
    private let edge: EdgeTTSService
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "app.kotoba.speech.network")

    private var player: AVAudioPlayer?
    private var workTask: Task<Void, Never>?
    private var playQueue: [URL] = []
    private var queueEngine: String = "server"
    private var lastRate: Double = 0.45
    private var online = true
    private var lastFailure: Date?
    private var mode: ReadAloudMode = .edgeDirect
    private var voiceID = EdgeTTSVoice.nanami.neuralName
    private var serverBaseURL = ""

    override init() {
        edge = EdgeTTSService(cache: cache)
        super.init()
        synthesizer.delegate = self
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async { self?.online = path.status == .satisfied }
        }
        monitor.start(queue: monitorQueue)
    }

    deinit {
        monitor.cancel()
        workTask?.cancel()
    }

    var hasJapaneseVoice: Bool {
        AVSpeechSynthesisVoice(language: "ja-JP") != nil
    }

    /// Called whenever the user changes read-aloud settings.
    func configure(mode: ReadAloudMode, voiceID: String, serverBaseURL: String) {
        self.mode = mode
        self.voiceID = voiceID
        self.serverBaseURL = serverBaseURL
    }

    // MARK: Speak

    func speak(_ text: String, rate: Double) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        lastSpoken = trimmed
        lastRate = rate

        switch mode {
        case .systemOnly:
            speakWithSystemVoice(trimmed, rate: rate)
        case .edgeDirect:
            speakOverNetwork(trimmed, rate: rate, engine: .edge)
        case .server:
            if serverBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                speakOverNetwork(trimmed, rate: rate, engine: .edge)
            } else {
                speakOverNetwork(trimmed, rate: rate, engine: .server)
            }
        }
    }

    func stop() {
        workTask?.cancel()
        workTask = nil
        playQueue.removeAll()
        player?.stop()
        player = nil
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: Network synthesis (chunked)

    private func speakOverNetwork(_ text: String, rate: Double, engine: Engine) {
        if blockReason() != nil {
            speakWithSystemVoice(text, rate: rate)
            return
        }
        let percent = EdgeTTSProtocol.ratePercent(forSpeechRate: rate)
        let voice = voiceID
        let chunks = TextChunker.chunks(of: text)
        guard !chunks.isEmpty else { return }

        workTask = Task { [weak self] in
            guard let self else { return }
            do {
                var urls: [URL] = []
                urls.reserveCapacity(chunks.count)
                for chunk in chunks {
                    let url = try await self.fetchAudio(chunk, voice: voice, percent: percent, engine: engine)
                    urls.append(url)
                }
                await MainActor.run {
                    self.enqueueAndPlay(urls, engine: engine == .server ? "server" : "edge", text: text, rate: rate)
                }
            } catch {
                await MainActor.run {
                    self.noteFailure()
                    self.speakWithSystemVoice(text, rate: rate)
                }
            }
        }
    }

    private func fetchAudio(_ text: String, voice: String, percent: Int, engine: Engine) async throws -> URL {
        let key = EdgeTTSCacheKey.make(voiceID: voice, ratePercent: percent, text: text)
        if let hit = cache.existing(forKey: key) { return hit }
        switch engine {
        case .server:
            let client = ServerTTSService(baseURL: serverBaseURL)
            let data = try await client.audio(text: text, voiceID: voice, ratePercent: percent, timeout: 15)
            return try cache.store(data, forKey: key)
        case .edge:
            return try await edge.audio(for: text, voiceID: voice, ratePercent: percent, timeout: 15)
        }
    }

    /// Offline or within the cooldown window → skip the network entirely.
    private func blockReason() -> String? {
        guard !voiceID.isEmpty else { return "没有可用的语音 ID" }
        guard online else { return "当前离线" }
        if let lastFailure, Date().timeIntervalSince(lastFailure) < EdgeTTSRouter.failureCooldown {
            return "刚刚失败过，临时改用系统语音"
        }
        return nil
    }

    private func noteFailure() {
        lastFailure = Date()
    }

    // MARK: Playback queue

    private func enqueueAndPlay(_ urls: [URL], engine: String, text: String, rate: Double) {
        guard let first = urls.first else {
            speakWithSystemVoice(text, rate: rate)
            return
        }
        playQueue = Array(urls.dropFirst())
        queueEngine = engine
        play(first, engine: engine, fallbackText: text, rate: rate)
    }

    private func play(_ url: URL, engine: String, fallbackText: String, rate: Double) {
        do {
            Self.configureSession()
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            guard player.play() else { throw ServerTTSService.Failure.malformedAudio }
            self.player = player
            lastEngine = engine
            isSpeaking = true
        } catch {
            noteFailure()
            playQueue.removeAll()
            speakWithSystemVoice(fallbackText, rate: rate)
        }
    }

    private func playNextInQueue() {
        guard !playQueue.isEmpty else {
            isSpeaking = false
            return
        }
        let next = playQueue.removeFirst()
        play(next, engine: queueEngine, fallbackText: lastSpoken ?? "", rate: lastRate)
    }

    private func speakWithSystemVoice(_ text: String, rate: Double) {
        Self.configureSession()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "ja-JP")
        utterance.rate = Float(min(max(rate, 0.2), 0.72))
        utterance.preUtteranceDelay = 0.02
        lastEngine = "system"
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    private static func configureSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}

// MARK: - Delegates

extension SpeechService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { self.isSpeaking = false }
    }
}

extension SpeechService: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            self.player = nil
            self.playNextInQueue()
        }
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        DispatchQueue.main.async {
            self.player = nil
            self.playQueue.removeAll()
            self.isSpeaking = false
            self.lastFailure = Date()
        }
    }
}
