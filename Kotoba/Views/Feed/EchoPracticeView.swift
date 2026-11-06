import SwiftUI

/// Echo practice: walk each sentence through Listen → Understand → Imitate → Compare.
///
/// Reuses the existing per-sentence builder, `ClipPlayer`, `SpeechService` and
/// `ShadowingRecorder`; ratings are stored through the existing shadowing records.
struct EchoPracticeView: View {
    let clip: Clip
    @ObservedObject var player: ClipPlayer

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var session: EchoSession
    @State private var recorder = ShadowingRecorder()
    @State private var pendingRecording: (url: URL, duration: Double)?
    @State private var permissionDenied = false

    init(clip: Clip, player: ClipPlayer) {
        self.clip = clip
        self.player = player
        _session = State(initialValue: EchoSession(sentences: IntensiveSentenceBuilder.build(for: clip)))
    }

    private var usesMedia: Bool { app.library.mediaURL(for: clip) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    stepStrip
                    contentCard
                    footerCard
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("回声练习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("结束") { close() }
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(clip.title)
                        .font(Theme.font(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("第 \(min(session.index + 1, max(session.sentenceCount, 1))) / \(session.sentenceCount) 句 · 第 \(session.stepNumber) / 4 步")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                TagLabel(text: session.step.title, tint: Theme.accent)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(geometry.size.width * session.progress, 4))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .card()
        .a11yCombine("回声练习，\(clip.title)，第 \(session.index + 1) 句，共 \(session.sentenceCount) 句，当前第 \(session.stepNumber) 步：\(session.step.title)")
    }

    private var stepStrip: some View {
        HStack(spacing: 6) {
            ForEach(EchoStep.allCases) { step in
                VStack(spacing: 3) {
                    Text(step.title)
                        .font(Theme.font(size: 12, weight: .semibold))
                        .foregroundStyle(step.rawValue <= session.step.rawValue ? Theme.accent : Theme.secondaryText)
                    Capsule()
                        .fill(step.rawValue <= session.step.rawValue ? Theme.accent : Theme.hairline)
                        .frame(height: 3)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("第 \(step.rawValue + 1) 步 \(step.title)"))
                .accessibilityValue(Text(step == session.step ? "当前" : (step.rawValue < session.step.rawValue ? "已完成" : "未开始")))
            }
        }
        .padding(.horizontal, 2)
    }

    // MARK: Content

    @ViewBuilder
    private var contentCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.step.detail)
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.secondaryText)

            if let sentence = session.current {
                switch session.step {
                case .listen:
                    listenContent(sentence)
                case .understand:
                    understandContent(sentence)
                case .imitate:
                    imitateContent(sentence)
                case .compare:
                    compareContent(sentence)
                }
            } else {
                Text("这条片段没有可练习的句子。")
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func listenContent(_ sentence: IntensiveSentence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先别开字幕，听一遍")
                .font(Theme.font(size: 20, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink.opacity(0.85))
            Text("（这一句 \(String(format: "%.1f", sentence.duration)) 秒）")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                PrimaryActionButton(title: "播放这一句", systemImage: "play.fill") {
                    play(sentence)
                }
                SecondaryActionButton(title: "再听一次", systemImage: "arrow.counterclockwise") {
                    play(sentence)
                }
            }
        }
    }

    private func understandContent(_ sentence: IntensiveSentence) -> some View {
        let tokens = app.tokenizer.tokenize(sentence.japanese)
        return VStack(alignment: .leading, spacing: 10) {
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
            Button {
                app.speech.speak(sentence.japanese, rate: app.profile.speechRate)
            } label: {
                Label("慢速朗读", systemImage: "speaker.wave.1")
                    .font(Theme.font(size: 12))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    private func imitateContent(_ sentence: IntensiveSentence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sentence.japanese)
                .font(Theme.font(size: 18, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                PrimaryActionButton(
                    title: recorder.isRecording ? "停止录音" : "开始录音",
                    systemImage: recorder.isRecording ? "stop.circle.fill" : "record.circle",
                    tint: recorder.isRecording ? Theme.rose : Theme.accent
                ) {
                    toggleRecording(sentence)
                }
                SecondaryActionButton(title: "听原句", systemImage: "speaker.wave.2") {
                    play(sentence)
                }
            }
            if recorder.isRecording {
                Text(String(format: "录音中… %.1f 秒", recorder.elapsed))
                    .font(Theme.font(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.rose)
            }
            if permissionDenied {
                Text("没有麦克风权限：请在 系统设置 › 隐私与安全性 › 麦克风 里允许 Kotoba。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.rose)
            }
        }
    }

    private func compareContent(_ sentence: IntensiveSentence) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("先听原句，再听自己")
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.secondaryText)
            HStack(spacing: 10) {
                SecondaryActionButton(title: "听原句", systemImage: "speaker.wave.2") {
                    play(sentence)
                }
                SecondaryActionButton(title: "听我的", systemImage: "mic") {
                    if let pendingRecording {
                        recorder.play(url: pendingRecording.url)
                    }
                }
                .disabled(pendingRecording == nil)
            }
            HStack(spacing: 8) {
                Text("这次跟读怎么样？")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Chip(text: "跟上了", isSelected: false, tint: Theme.jade) {
                    rate(sentence, .gotIt)
                }
                Chip(text: "再来一次", isSelected: false, tint: Theme.amber) {
                    rate(sentence, .practiceAgain)
                }
            }
        }
    }

    // MARK: Footer

    private var footerCard: some View {
        HStack(spacing: 10) {
            SecondaryActionButton(title: "重新开始这句", systemImage: "arrow.counterclockwise") {
                session.restart()
            }
            PrimaryActionButton(
                title: session.isFinished ? "已完成" : "下一步",
                systemImage: session.isFinished ? "checkmark" : "chevron.right",
                isEnabled: !session.isFinished
            ) {
                advance()
            }
        }
    }

    // MARK: Behaviour

    private func start() {
        player.setLooping(false)
        player.onSegmentEnd = nil
        if let sentence = session.current, session.step == .listen {
            play(sentence)
        }
    }

    private func teardown() {
        player.pause()
        app.speech.stop()
        recorder.stopPlayback()
        if recorder.isRecording { _ = recorder.stopRecording() }
    }

    private func close() {
        dismiss()
    }

    private func play(_ sentence: IntensiveSentence) {
        if usesMedia {
            player.playRange(start: sentence.start, end: sentence.end)
            player.setRate(app.profile.playbackRate)
        } else {
            app.speech.speak(sentence.japanese, rate: app.profile.speechRate)
        }
    }

    private func advance() {
        let changed = session.advance()
        if changed, let sentence = session.current, session.step == .listen {
            pendingRecording = nil
            play(sentence)
        }
    }

    private func toggleRecording(_ sentence: IntensiveSentence) {
        if recorder.isRecording {
            if let result = recorder.stopRecording() {
                pendingRecording = result
            }
            return
        }
        permissionDenied = false
        recorder.resetError()
        Task { @MainActor in
            let granted = await recorder.requestPermission()
            guard granted else {
                permissionDenied = true
                return
            }
            let name = "\(clip.id)-echo-\(sentence.index)-\(UUID().uuidString).m4a"
            let url = app.shadowingDirectory().appendingPathComponent(name)
            _ = recorder.startRecording(to: url)
        }
    }

    private func rate(_ sentence: IntensiveSentence, _ rating: ShadowingRating) {
        guard let pendingRecording else {
            app.toast = "先录一遍再自评"
            return
        }
        app.saveShadowingRecord(
            clipID: clip.id,
            sentenceIndex: sentence.index,
            japanese: sentence.japanese,
            fileName: pendingRecording.url.lastPathComponent,
            duration: pendingRecording.duration,
            rating: rating
        )
        app.toast = "已记录：\(rating.title)"
    }
}
