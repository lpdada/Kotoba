import Foundation
import SwiftUI
import WebKit

/// Plays one YouTube segment with the official embedded player.
///
/// The clip stays hosted on YouTube and is streamed by YouTube's own player, so
/// no video file is stored, re-encoded or redistributed by this app.
struct YouTubeEmbedView: UIViewRepresentable {
    let videoID: String
    let start: Double
    let end: Double
    let autoplay: Bool
    let muted: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .black
        context.coordinator.load(webView, videoID: videoID, start: start, end: end, autoplay: autoplay, muted: muted)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.load(webView, videoID: videoID, start: start, end: end, autoplay: autoplay, muted: muted)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.loadHTMLString("<html><body></body></html>", baseURL: nil)
    }

    final class Coordinator {
        private var loadedKey: String?

        func load(
            _ webView: WKWebView,
            videoID: String,
            start: Double,
            end: Double,
            autoplay: Bool,
            muted: Bool
        ) {
            let key = "\(videoID)-\(start)-\(end)-\(autoplay)-\(muted)"
            guard key != loadedKey else { return }
            loadedKey = key
            let html = Self.html(videoID: videoID, start: start, end: end, autoplay: autoplay, muted: muted)
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
        }

        private static func html(videoID: String, start: Double, end: Double, autoplay: Bool, muted: Bool) -> String {
            let startSeconds = Int(max(start, 0))
            let endSeconds = max(Int(end), startSeconds + 1)
            let playFlag = autoplay ? 1 : 0
            let muteFlag = muted ? 1 : 0
            return """
            <!DOCTYPE html>
            <html>
              <head>
                <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0">
                <style>
                  html, body { margin:0; padding:0; background:#000; height:100%; overflow:hidden; }
                  iframe { position:absolute; inset:0; width:100%; height:100%; border:0; }
                </style>
              </head>
              <body>
                <iframe
                  id="player"
                  src="https://www.youtube-nocookie.com/embed/\(videoID)?start=\(startSeconds)&end=\(endSeconds)&autoplay=\(playFlag)&mute=\(muteFlag)&loop=1&playlist=\(videoID)&playsinline=1&rel=0&modestbranding=1&controls=0&iv_load_policy=3&fs=0"
                  allow="autoplay; encrypted-media; picture-in-picture"
                  allowfullscreen>
                </iframe>
                <script>
                  // Re-seek when the embedded player reports the segment ended.
                  var lastReload = 0;
                  function reloadSegment() {
                    var now = Date.now();
                    if (now - lastReload < 900) { return; }
                    lastReload = now;
                    var frame = document.getElementById('player');
                    var base = frame.src.split('&reload=')[0];
                    frame.src = base + '&reload=' + now;
                  }
                  window.addEventListener('message', function (event) {
                    try {
                      var payload = JSON.parse(event.data);
                      if (payload && payload.event === 'onStateChange' && payload.info === 0) {
                        reloadSegment();
                      }
                    } catch (error) {}
                  });
                </script>
              </body>
            </html>
            """
        }
    }
}

/// Fallback surface shown when a clip has no video file: an original animated scene.
struct GeneratedSceneView: View {
    let seed: String
    let isPlaying: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { geometry in
                let size = geometry.size
                ZStack {
                    LinearGradient(
                        colors: gradientColors(time: time),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    // Two drifting bands give the frame a sense of motion.
                    ForEach(0..<3, id: \.self) { index in
                        let offset = (time * 0.12 + Double(index) * 0.31).truncatingRemainder(dividingBy: 1)
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .fill(Color.white.opacity(0.05 + Double(index) * 0.012))
                            .frame(width: size.width * 1.5, height: size.height * 0.16)
                            .rotationEffect(.degrees(-18))
                            .offset(x: -size.width * 0.2 + offset * size.width * 0.6,
                                    y: size.height * (0.2 + Double(index) * 0.28))
                    }
                    // Subtle "sound wave" bars, driven by the same clock.
                    HStack(spacing: 4) {
                        ForEach(0..<22, id: \.self) { bar in
                            let wave = sin(time * 2.2 + Double(bar) * 0.55)
                            Capsule()
                                .fill(Color.white.opacity(0.22))
                                .frame(width: 3, height: 10 + abs(wave) * 34)
                        }
                    }
                    .offset(y: size.height * 0.28)
                }
            }
        }
        .ignoresSafeArea()
    }

    private func gradientColors(time: TimeInterval) -> [Color] {
        let drift = (sin(time * 0.18) + 1) / 2
        let base = Theme.colorHash(seed)
        return [
            base.opacity(0.92),
            Theme.ink.opacity(0.96),
            Color(red: 0.10 + drift * 0.12, green: 0.12 + drift * 0.08, blue: 0.20)
        ]
    }
}
