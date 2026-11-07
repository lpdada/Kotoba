import SwiftUI

struct ClipPageView: View {
    let clip: Clip
    let isActive: Bool
    var onLookup: (ClipToken, String) -> Void
    var onInfo: () -> Void

    @EnvironmentObject private var app: AppModel
    @StateObject private var player = ClipPlayer()
    @State private var analysis: ClipAnalysis?
    @State private var mediaURL: URL?
    @State private var isSpeechPlaying = false
    @State private var appearedAt: Date?
    @State private var showIntensive = false
    @State private var showEcho = false
    @ScaledMetric(relativeTo: .body) private var subtitleMaxHeight: CGFloat = 190
    @State private var resumeAfterIntensive = false
    @State private var safeAreaTop: CGFloat = 0
    @State private var safeAreaBottom: CGFloat = 0

    /// Standard system tab bar height; the bottom padding adds the real safe area.
    private let tabBarHeight: CGFloat = 49

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            mediaLayer
            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                topBar
                Spacer(minLength: 0)
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, safeAreaTop + 8)
            .padding(.bottom, tabBarHeight + safeAreaBottom)
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { readSafeArea(proxy) }
                    .onChange(of: proxy.safeAreaInsets.top) { _, _ in readSafeArea(proxy) }
                    .onChange(of: proxy.safeAreaInsets.bottom) { _, _ in readSafeArea(proxy) }
            }
        )
        .onAppear(perform: prepare)
        .onChange(of: app.profile.playbackRate) { _, rate in
            player.setRate(rate)
        }
        .onChange(of: app.profile.loopClip) { _, loops in
            player.setLooping(loops)
        }
        .sheet(isPresented: $showEcho, onDismiss: restoreAfterMode) {
            EchoPracticeView(clip: clip, player: player)
                .environmentObject(app)
        }
        .sheet(isPresented: $showIntensive, onDismiss: restoreAfterIntensive) {
            IntensiveListeningView(clip: clip, player: player)
                .environmentObject(app)
        }
        .onChange(of: isActive) { _, active in
            if active {
                appearedAt = Date()
                activate()
            } else {
                deactivate()
            }
        }
        .onDisappear(perform: deactivate)
    }

    // MARK: Media

    @ViewBuilder
    private var mediaLayer: some View {
        switch clip.media {
        case .generated:
            GeneratedSceneView(seed: clip.id, isPlaying: isActive)
                .a11yDecorative()
        case .localFile, .remote:
            if let mediaURL {
                if player.isReady {
                    VideoSurface(player: player.player)
                        .ignoresSafeArea()
                        .a11yDecorative()
                } else {
                    ZStack {
                        GeneratedSceneView(seed: clip.id, isPlaying: false)
                        VStack(spacing: 6) {
                            ProgressView().tint(.white)
                            if let failure = player.failure {
                                Text(failure)
                                    .font(Theme.font(size: 11))
                                    .foregroundStyle(.white.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 30)
                            }
                        }
                    }
                }
            } else {
                ZStack {
                    GeneratedSceneView(seed: clip.id, isPlaying: false)
                    Text("未找到媒体文件「\(mediaName)」\n把它放进 文件App › Kotoba › Media")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
        case .youtube(let identifier, let start, let end):
            YouTubeEmbedView(
                videoID: identifier,
                start: start,
                end: end,
                autoplay: isActive && app.profile.autoplayEnabled,
                muted: false
            )
            .ignoresSafeArea()
        }
    }

    private var mediaName: String {
        if case .localFile(let name) = clip.media { return name }
        return "?"
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(clip.displaySeries)
                    .font(Theme.font(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                Text(clip.title)
                    .font(Theme.font(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            Spacer()
            HStack(spacing: 8) {
                LevelBadge(level: analysis?.metrics.level ?? clip.level)
                    .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .accessibilityLabel(Text("片段难度 \((analysis?.metrics.level ?? clip.level)?.label ?? "未分级")"))
                Button {
                    app.toggleSavedClip(clip)
                } label: {
                    Image(systemName: app.savedClipIDs.contains(clip.id) ? "bookmark.fill" : "bookmark")
                        .font(Theme.font(size: 14, weight: .semibold))
                        .foregroundStyle(app.savedClipIDs.contains(clip.id) ? Theme.amber : .white)
                        .padding(8)
                        .background(.black.opacity(0.28), in: Circle())
                }
                .buttonStyle(.plain)
                .a11yButton(
                    app.savedClipIDs.contains(clip.id) ? "取消收藏片段" : "收藏片段",
                    hint: "收藏后在「我的」里能找到",
                    value: app.savedClipIDs.contains(clip.id) ? "已收藏" : "未收藏"
                )
            }
        }
    }

    // MARK: Content

    private var content: some View {
        HStack(alignment: .bottom, spacing: 12) {
            subtitleCard
            actionRail
        }
    }

    private var subtitleCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let analysis {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(analysis.lines.enumerated()), id: \.offset) { index, tokens in
                            SubtitleLineView(
                                tokens: tokens,
                                translation: translation(for: index),
                                familiarityFor: { token in
                                    guard let id = token.entryID else { return nil }
                                    return app.words.first { $0.id == id }?.familiarity
                                },
                                showFurigana: app.profile.furiganaEnabled,
                                showRomaji: app.profile.romajiEnabled,
                                showTranslation: app.profile.translationEnabled,
                                activeTokenID: nil
                            ) { token in
                                onLookup(token, clip.lines[safe: index] ?? clip.transcript)
                            }
                        }
                    }
                    .padding(.bottom, 2)
                }
                .frame(maxHeight: subtitleMaxHeight)
            } else {
                ProgressView().tint(.white)
            }

            HStack(spacing: 10) {
                Text(clip.media.shortLabel)
                    .font(Theme.font(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
                if !clip.attribution.isEmpty {
                    Text("·")
                        .font(Theme.font(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Text(clip.attribution)
                        .font(Theme.font(size: 10))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text("\(Int(clip.durationSeconds))s")
                    .font(Theme.font(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var actionRail: some View {
        VStack(spacing: 14) {
            railButton(
                symbol: isSpeechPlaying ? "speaker.wave.3.fill" : "speaker.wave.2",
                label: "朗读"
            ) {
                toggleSpeech()
            }
            railButton(symbol: "headphones", label: "精听") {
                openIntensive()
            }
            railButton(symbol: "waveform.circle", label: "回声") {
                openEcho()
            }
            railButton(symbol: "arrow.counterclockwise", label: "重播") {
                replay()
            }
            railButton(symbol: "text.quote", label: "整句") {
                app.saveSentence(
                    text: clip.lines.joined(separator: "\n"),
                    translation: clip.translation,
                    clip: clip
                )
            }
            railButton(symbol: "info.circle", label: "信息") {
                onInfo()
            }
        }
        .padding(.bottom, 6)
    }

    private func railButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(Theme.font(size: 17, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.black.opacity(0.3), in: Circle())
                    .foregroundStyle(.white)
                Text(label)
                    .font(Theme.font(size: 9))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .buttonStyle(.plain)
        .a11yButton(label, hint: railHint(for: label))
    }

    private func railHint(for label: String) -> String {
        switch label {
        case "精听": return "逐句播放并跟读"
        case "回声": return "听、懂、模仿、对比四步练习"
        case "重播": return "从这一段的开头重新播放"
        case "整句": return "把这条字幕保存成整句卡片"
        case "信息": return "查看片段难度、字幕与来源"
        default: return "朗读这一段"
        }
    }

    // MARK: Behaviour

    private func readSafeArea(_ proxy: GeometryProxy) {
        safeAreaTop = proxy.safeAreaInsets.top
        safeAreaBottom = proxy.safeAreaInsets.bottom
    }

    private func prepare() {
        analysis = app.library.analysis(for: clip, tokenizer: app.tokenizer)
        mediaURL = app.library.mediaURL(for: clip)
        if let mediaURL {
            let start = clip.startSeconds
            let end = start + (clip.durationSeconds > 0 ? clip.durationSeconds : 12)
            player.load(
                url: mediaURL,
                start: start,
                end: end,
                rate: app.profile.playbackRate,
                loops: app.profile.loopClip
            )
        }
    }

    private func activate() {
        guard appearedAt == nil else {
            if mediaURL != nil { player.play() }
            return
        }
        appearedAt = Date()
        if mediaURL != nil {
            player.play()
        } else if app.profile.autoplayEnabled, !clip.lines.isEmpty {
            toggleSpeech(forceStart: true)
        }
    }

    private func deactivate() {
        player.pause()
        app.speech.stop()
        isSpeechPlaying = false
        if let started = appearedAt {
            let seconds = Date().timeIntervalSince(started)
            if seconds > 1 {
                app.recordWatch(clip: clip, seconds: seconds, completed: seconds > clip.durationSeconds * 0.6)
                app.addStudySeconds(seconds)
            }
            appearedAt = nil
        }
    }

    private func toggleSpeech(forceStart: Bool = false) {
        if isSpeechPlaying && !forceStart {
            app.speech.stop()
            isSpeechPlaying = false
            return
        }
        let text = clip.lines.joined(separator: "。")
        app.speech.speak(text, rate: app.profile.speechRate)
        isSpeechPlaying = true
    }

    private func openEcho() {
        resumeAfterIntensive = player.isPlaying || isSpeechPlaying
        player.pause()
        if isSpeechPlaying {
            app.speech.stop()
            isSpeechPlaying = false
        }
        showEcho = true
    }

    private func restoreAfterMode() {
        restoreAfterIntensive()
    }

    private func openIntensive() {
        resumeAfterIntensive = player.isPlaying || isSpeechPlaying
        player.pause()
        if isSpeechPlaying {
            app.speech.stop()
            isSpeechPlaying = false
        }
        showIntensive = true
    }

    /// Leaves the per-sentence segment behind and restores the clip's normal loop.
    private func restoreAfterIntensive() {
        let start = clip.startSeconds
        let end = start + (clip.durationSeconds > 0 ? clip.durationSeconds : 12)
        if mediaURL != nil {
            player.setSegment(start: start, end: end)
            player.setLooping(app.profile.loopClip)
            player.setRate(app.profile.playbackRate)
            if resumeAfterIntensive {
                player.play()
            }
        } else if resumeAfterIntensive, app.profile.autoplayEnabled {
            toggleSpeech(forceStart: true)
        }
    }

    private func replay() {
        if mediaURL != nil {
            player.restart()
        } else {
            toggleSpeech(forceStart: true)
        }
    }

    private func translation(for index: Int) -> String? {
        guard app.profile.translationEnabled else { return nil }
        switch app.profile.translationLanguage {
        case .chinese:
            return clip.translationLines[safe: index]
        case .english:
            return clip.translationEN.isEmpty ? clip.translationLines[safe: index] : clip.translationEN
        }
    }
}
