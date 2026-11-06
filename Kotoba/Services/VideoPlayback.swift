import AVFoundation
import AVKit
import SwiftUI

/// Loops a defined segment of a video file or stream.
///
/// Deliberately not actor-isolated: AVFoundation callbacks arrive on background
/// queues, so mutation of published state is funnelled through the main queue.
final class ClipPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var isReady = false
    @Published private(set) var failure: String?

    let player = AVPlayer()

    private var segmentStart: Double = 0
    private var segmentEnd: Double = 0
    private var boundaryObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var loadedURL: URL?
    /// When false the clip stops on the segment boundary instead of looping.
    private(set) var isLooping = true

    init() {
        player.actionAtItemEnd = .pause
        player.isMuted = false
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSegmentEnd()
        }
    }

    deinit {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
    }

    // MARK: Loading

    func load(url: URL, start: Double, end: Double, rate: Double, loops: Bool = true) {
        isLooping = loops
        guard loadedURL != url || player.currentItem == nil else {
            setSegment(start: start, end: end)
            setRate(rate)
            return
        }
        unload()
        loadedURL = url
        segmentStart = max(start, 0)
        segmentEnd = max(end, segmentStart + 0.5)

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.isMuted = false
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let status = item.status
            let message = item.error?.localizedDescription
            DispatchQueue.main.async {
                guard let self else { return }
                switch status {
                case .readyToPlay:
                    self.isReady = true
                    self.failure = nil
                case .failed:
                    self.failure = message ?? "视频无法播放"
                    self.isReady = false
                default:
                    break
                }
            }
        }
        setSegment(start: segmentStart, end: segmentEnd)
        setRate(rate)
        seekToSegmentStart()
    }

    func setSegment(start: Double, end: Double) {
        segmentStart = max(start, 0)
        segmentEnd = max(end, segmentStart + 0.5)
        installBoundaryObserver()
    }

    private func installBoundaryObserver() {
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        let target = CMTime(seconds: segmentEnd, preferredTimescale: 600)
        boundaryObserver = player.addBoundaryTimeObserver(forTimes: [NSValue(time: target)], queue: .main) { [weak self] in
            self?.handleSegmentEnd()
        }
    }

    // MARK: Transport

    func play() {
        guard isReady else { return }
        if let item = player.currentItem, item.currentTime().seconds >= segmentEnd - 0.05 {
            seekToSegmentStart()
        }
        player.play()
        isPlaying = true
    }

    func pause() {
        player.pause()
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    func restart() {
        seekToSegmentStart()
        if isPlaying || player.rate > 0 {
            player.play()
        }
    }

    func setLooping(_ value: Bool) {
        isLooping = value
    }

    /// Called when the playhead reaches the end of the requested segment.
    private func handleSegmentEnd() {
        guard isLooping else {
            pause()
            return
        }
        restart()
    }

    func seekToSegmentStart() {
        let time = CMTime(seconds: segmentStart, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Double) {
        player.defaultRate = Float(rate)
        if isPlaying {
            player.rate = Float(rate)
        }
    }

    /// Continuous playback position inside the segment, 0...1.
    var segmentProgress: (Double, Double) {
        let current = player.currentTime().seconds
        let bounded = min(max(current, segmentStart), segmentEnd)
        return (bounded, segmentEnd - segmentStart)
    }

    func unload() {
        pause()
        if let boundaryObserver {
            player.removeTimeObserver(boundaryObserver)
            self.boundaryObserver = nil
        }
        statusObservation?.invalidate()
        statusObservation = nil
        player.replaceCurrentItem(with: nil)
        loadedURL = nil
        isReady = false
        isPlaying = false
        failure = nil
    }
}

/// Hosts the player layer without SwiftUI's own layout guesswork.
struct VideoSurface: UIViewRepresentable {
    let player: AVPlayer
    var gravity: AVLayerVideoGravity = .resizeAspect

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.backgroundColor = .black
        view.playerLayer.videoGravity = gravity
        view.playerLayer.player = player
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
        uiView.playerLayer.videoGravity = gravity
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // Safe by construction: layerClass guarantees the type.
        layer as! AVPlayerLayer
    }
}
