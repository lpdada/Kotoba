import SwiftUI

/// Sentence-by-sentence intensive listening with shadowing.
///
/// Two drive modes, decided by the clip:
/// * media clips (local file / remote URL) are driven by `ClipPlayer`, so A-B loop,
///   repeat and auto-pause work on real audio/video;
/// * clips without media (bundled samples, YouTube embeds) fall back to the local
///   Japanese TTS and a timer, which keeps the same controls usable offline.
struct IntensiveListeningView: View {
    let clip: Clip
    @ObservedObject var player: ClipPlayer

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var engine = IntensiveEngine(sentences: [])
    @State private var sentences: [IntensiveSentence] = []
    @State private var isPlaying = false
    @State private var didFinish = false
    @State private var ttsTimer: Timer?
    @State private var showShadowPanel = false
    @StateObject private var recorder = ShadowingRecorder()
    @State private var pendingRecording: (url: URL, duration: Double)?
    @State private var latestRecord: ShadowingRecord?
    @State private var permissionDenied = false
    @State private var compareTask: Task<Void, Never>?

    private var usesMedia: Bool { app.library.mediaURL(for: clip) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    sentenceCard
                    controlsCard
                    sentenceListCard
                    shadowingCard
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("精听 · 跟读")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("结束") { close() }
                        .fontWeight(.semibold)
                }
            }
        }
        .onAppear(perform: start)
        .onDisappear(perform: teardown)
    }

    // MARK: Header

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.title)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(usesMedia ? "逐句播放：从当前句的时间点起播" : "无媒体素材：用本地朗读逐句练习")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                if !sentences.isEmpty {
                    Text("\(engine.currentIndex + 1)/\(sentences.count)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(geometry.size.width * engine.progress, 4))
                }
            }
            .frame(height: 4)
        }
        .card()
    }

    // MARK: Current sentence

    private var sentenceCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let sentence = engine.current {
                HStack {
                    TagLabel(text: "第 \(sentence.index + 1) 句", tint: Theme.accent)
                    Text("\(sentence.timeLabel) ・ \(String(format: "%.1f", sentence.duration)) 秒")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    if engine.isAwaitingUser {
                        TagLabel(text: "已暂停", tint: Theme.amber)
                    }
                }

                let tokens = app.tokenizer.tokenize(sentence.japanese)
                SubtitleLineView(
                    tokens: tokens,
                    translation: sentence.translation,
                    familiarityFor: { token in
                        guard let identifier = token.entryID else { return nil }
                        return app.words.first { $0.id == identifier }?.familiarity
                    },
                    showFurigana: app.profile.furiganaEnabled,
                    showRomaji: app.profile.romajiEnabled,
                    showTranslation: app.profile.translationEnabled,
                    activeTokenID: nil
                ) { _ in }

                if !app.profile.furiganaEnabled {
                    Text("振假名已在设置里关闭")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            } else {
                Text("这条片段没有可练习的句子。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Controls

    private var controlsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                transportButton("上一句", system: "backward.end.fill") {
                    if engine.previous() != nil { playCurrent(restart: true) }
                }
                transportButton(isPlaying ? "暂停" : "播放", system: isPlaying ? "pause.fill" : "play.fill") {
                    togglePlayback()
                }
                transportButton("下一句", system: "forward.end.fill") {
                    if engine.next() != nil { playCurrent(restart: true) }
                }
                transportButton("重放", system: "arrow.counterclockwise") {
                    playCurrent(restart: true)
                }
            }

            Hairline()

            HStack(spacing: 8) {
                Chip(text: engine.loopCurrent ? "A-B 循环 开" : "A-B 循环 关", isSelected: engine.loopCurrent) {
                    engine.setLoop(!engine.loopCurrent)
                }
                Chip(text: engine.autoPauseAtEnd ? "句末暂停 开" : "句末暂停 关", isSelected: engine.autoPauseAtEnd) {
                    engine.setAutoPause(!engine.autoPauseAtEnd)
                }
            }

            HStack(spacing: 8) {
                Text("重复")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(1...3, id: \.self) { count in
                    Chip(text: "\(count) 次", isSelected: engine.repeatTarget == count) {
                        engine.setRepeat(count)
                    }
                }
                Spacer()
                Text(engine.repeatLabel)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }

            HStack(spacing: 8) {
                Text("速度")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Slider(
                    value: Binding(
                        get: { app.profile.playbackRate },
                        set: { value in
                            app.updateProfile { $0.playbackRate = value }
                            player.setRate(value)
                        }
                    ),
                    in: 0.5...1.5,
                    step: 0.05
                )
                .tint(Theme.accent)
                Text(String(format: "%.2fx", app.profile.playbackRate))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 44, alignment: .trailing)
            }

            Text(statusLine)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var statusLine: String {
        var parts: [String] = []
        parts.append(engine.loopCurrent ? "循环：本句无限重复" : "循环：关")
        parts.append(engine.autoPauseAtEnd ? "句末：暂停等你操作" : "句末：自动跳下一句")
        parts.append("重复：\(engine.repeatLabel)")
        if didFinish { parts.append("已到结尾") }
        return parts.joined(separator: " · ")
    }

    private func transportButton(_ title: String, system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundStyle(Theme.accent)
        }
        .buttonStyle(.plain)
    }

    // MARK: Sentence list

    private var sentenceListCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "句子列表", subtitle: "点任意一句跳转播放")
            if sentences.isEmpty {
                Text("没有句子。").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(sentences) { sentence in
                        Button {
                            if engine.select(sentence.index) != nil {
                                playCurrent(restart: true)
                            }
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("\(sentence.index + 1)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                    .foregroundStyle(sentence.index == engine.currentIndex ? Theme.accent : Theme.secondaryText)
                                    .frame(width: 18, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sentence.japanese)
                                        .font(.system(size: 13, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                        .multilineTextAlignment(.leading)
                                    if let translation = sentence.translation {
                                        Text(translation)
                                            .font(.system(size: 10))
                                            .foregroundStyle(Theme.secondaryText)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer(minLength: 0)
                                if sentence.index == engine.currentIndex {
                                    Image(systemName: "waveform")
                                        .font(.system(size: 11))
                                        .foregroundStyle(Theme.accent)
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                sentence.index == engine.currentIndex ? Theme.accentSoft : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Shadowing

    private var shadowingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "跟读", subtitle: "录下自己，和原句对比")
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { showShadowPanel.toggle() }
                } label: {
                    Image(systemName: showShadowPanel ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            if showShadowPanel {
                HStack(spacing: 10) {
                    Button {
                        toggleRecording()
                    } label: {
                        Label(
                            recorder.isRecording ? "停止录音" : "录音",
                            systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle"
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            (recorder.isRecording ? Theme.rose : Theme.accent).opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                        .foregroundStyle(recorder.isRecording ? Theme.rose : Theme.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        playOriginal()
                    } label: {
                        Label("听原句", systemImage: "speaker.wave.2")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: 10) {
                    Button {
                        playRecording()
                    } label: {
                        Label("听我的", systemImage: "mic")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentRecording() == nil)

                    Button {
                        compare()
                    } label: {
                        Label("对比播放", systemImage: "arrow.left.arrow.right")
                            .font(.system(size: 13))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }

                if recorder.isRecording {
                    Text(String(format: "录音中… %.1f 秒", recorder.elapsed))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.rose)
                }

                if case .failed(let message) = recorder.phase {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if permissionDenied {
                    Text("没有麦克风权限：请在 系统设置 › 隐私与安全性 › 麦克风 里允许 Kotoba。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let latestRecord {
                    HStack(spacing: 8) {
                        TagLabel(
                            text: latestRecord.rating.title,
                            tint: latestRecord.rating == .gotIt ? Theme.jade : Theme.amber
                        )
                        Text("上次：\(latestRecord.rating.title) ・ \(String(format: "%.1f", latestRecord.durationSeconds)) 秒")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Button {
                            app.speech.speak(engine.current?.japanese ?? "", rate: app.profile.speechRate)
                        } label: {
                            Image(systemName: "speaker.wave.1")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if pendingRecording != nil {
                    HStack(spacing: 8) {
                        Text("这次跟读怎么样？")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        Spacer()
                        Chip(text: "跟上了", isSelected: false, tint: Theme.jade) {
                            rate(.gotIt)
                        }
                        Chip(text: "再来一次", isSelected: false, tint: Theme.amber) {
                            rate(.practiceAgain)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Lifecycle

    private func start() {
        let built = IntensiveSentenceBuilder.build(for: clip)
        sentences = built
        engine = IntensiveEngine(sentences: built, currentIndex: 0)
        player.onSegmentEnd = { handleSentenceEnd() }
        refreshLatestRecord()
        if usesMedia {
            player.setRate(app.profile.playbackRate)
            playCurrent(restart: true)
        }
    }

    private func teardown() {
        ttsTimer?.invalidate()
        ttsTimer = nil
        compareTask?.cancel()
        player.onSegmentEnd = nil
        player.pause()
        app.speech.stop()
        recorder.stopPlayback()
        if recorder.isRecording { _ = recorder.stopRecording() }
    }

    private func close() {
        dismiss()
    }

    // MARK: Transport

    private func togglePlayback() {
        if isPlaying {
            isPlaying = false
            player.pause()
            stopTTSTimer()
            app.speech.stop()
            return
        }
        didFinish = false
        if engine.isAwaitingUser {
            engine.resume()
            if engine.next() != nil {
                playCurrent(restart: true)
                return
            }
        }
        playCurrent(restart: false)
    }

    private func playCurrent(restart: Bool) {
        guard let sentence = engine.current else { return }
        if restart {
            engine.restartCurrent()
            didFinish = false
        }
        isPlaying = true
        if usesMedia {
            player.onSegmentEnd = { handleSentenceEnd() }
            player.playRange(start: sentence.start, end: sentence.end)
            player.setRate(app.profile.playbackRate)
        } else {
            app.speech.speak(sentence.japanese, rate: app.profile.speechRate)
            startTTSTimer(seconds: max(1.2, min(sentence.duration, 8)))
        }
    }

    private func handleSentenceEnd() {
        let action = engine.handleSentenceEnd()
        switch action {
        case .replay:
            playCurrent(restart: false)
        case .advance:
            playCurrent(restart: false)
        case .pause:
            isPlaying = false
            player.pause()
            stopTTSTimer()
        case .finished:
            isPlaying = false
            player.pause()
            stopTTSTimer()
            didFinish = true
        }
        refreshLatestRecord()
    }

    private func startTTSTimer(seconds: Double) {
        stopTTSTimer()
        ttsTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { _ in
            DispatchQueue.main.async { handleSentenceEnd() }
        }
    }

    private func stopTTSTimer() {
        ttsTimer?.invalidate()
        ttsTimer = nil
    }

    // MARK: Shadowing actions

    private func currentRecording() -> URL? {
        guard let record = app.latestRecord(
            forClip: clip.id,
            sentence: engine.currentIndex
        ) else { return pendingRecording?.url }
        return app.audioURL(for: record)
    }

    private func toggleRecording() {
        if recorder.isRecording {
            guard let result = recorder.stopRecording() else { return }
            pendingRecording = result
            return
        }
        guard let sentence = engine.current else { return }
        permissionDenied = false
        recorder.resetError()
        Task { @MainActor in
            let granted = await recorder.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }
            let name = "\(clip.id)-s\(sentence.index)-\(UUID().uuidString).m4a"
            let url = app.shadowingDirectory().appendingPathComponent(name)
            _ = recorder.startRecording(to: url)
        }
    }

    private func playRecording() {
        guard let url = currentRecording() else { return }
        recorder.play(url: url)
    }

    private func playOriginal() {
        guard let sentence = engine.current else { return }
        if usesMedia {
            let wasLoop = engine.loopCurrent
            engine.setLoop(false)
            player.playRange(start: sentence.start, end: sentence.end)
            engine.setLoop(wasLoop)
        } else {
            app.speech.speak(sentence.japanese, rate: app.profile.speechRate)
        }
    }

    private func compare() {
        guard let sentence = engine.current, let mine = currentRecording() else { return }
        compareTask?.cancel()
        playOriginal()
        let delay = max(sentence.duration, 1.0) + 0.35
        compareTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            recorder.play(url: mine)
        }
    }

    private func rate(_ rating: ShadowingRating) {
        guard let pending = pendingRecording, let sentence = engine.current else { return }
        app.saveShadowingRecord(
            clipID: clip.id,
            sentenceIndex: sentence.index,
            japanese: sentence.japanese,
            fileName: pending.url.lastPathComponent,
            duration: pending.duration,
            rating: rating
        )
        app.toast = "已保存跟读记录（\(rating.title)）"
        pendingRecording = nil
        refreshLatestRecord()
    }

    private func refreshLatestRecord() {
        latestRecord = app.latestRecord(forClip: clip.id, sentence: engine.currentIndex)
    }
}
