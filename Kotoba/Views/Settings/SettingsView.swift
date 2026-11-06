import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel

    @State private var nameDraft = ""
    @State private var baseURLDraft = ""
    @State private var modelDraft = ""
    @State private var keyDraft = ""
    @State private var showResetAlert = false
    @State private var isTesting = false
    @State private var exportURL: URL?
    @State private var isRestoring = false
    @State private var pendingRestoreURL: URL?
    @State private var showRestoreConfirm = false
    @State private var restoreError: String?
    @State private var showRestoreError = false
    @State private var ankiURL: URL?
    @State private var transcriptionTestResult: String?
    @State private var isTestingTranscription = false

    var body: some View {
        Form {
            learnerSection
            subtitleSection
            playbackSection
            voiceSection
            aiSection
            transcriptionSection
            dataSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.screenBackground)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: loadDrafts)
        .alert("清空所有学习数据？", isPresented: $showResetAlert) {
            Button("取消", role: .cancel) {}
            Button("清空", role: .destructive) {
                app.resetEverything()
            }
        } message: {
            Text("生词本、复习进度、观看记录与自建分组都会被删除，操作不可撤销。")
        }
        .fileImporter(
            isPresented: $isRestoring,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                pendingRestoreURL = urls.first
                showRestoreConfirm = pendingRestoreURL != nil
            case .failure(let error):
                restoreError = "选择文件失败：\(error.localizedDescription)"
                showRestoreError = true
            }
        }
        .confirmationDialog("用备份覆盖当前数据？", isPresented: $showRestoreConfirm, titleVisibility: .visible) {
            Button("覆盖恢复", role: .destructive) { performRestore() }
            Button("取消", role: .cancel) { pendingRestoreURL = nil }
        } message: {
            Text("现有生词、复习进度、分组与片段清单都会被备份内容替换；媒体文件不会被删除。")
        }
        .alert("恢复失败", isPresented: $showRestoreError) {
            Button("好") { restoreError = nil }
        } message: {
            Text(restoreError ?? "未知错误")
        }
    }

    // MARK: Learner

    private var learnerSection: some View {
        Section {
            HStack {
                Text("昵称")
                Spacer()
                TextField("昵称", text: $nameDraft)
                    .multilineTextAlignment(.trailing)
                    .onSubmit {
                        app.updateProfile { $0.displayName = nameDraft.isEmpty ? "同学" : nameDraft }
                    }
            }

            Picker("等级", selection: Binding(
                get: { app.profile.level },
                set: { value in app.updateProfile { $0.level = value } }
            )) {
                ForEach(JLPTLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(level)
                }
            }

            Stepper("每日目标 \(app.profile.dailyGoalMinutes) 分钟", value: Binding(
                get: { app.profile.dailyGoalMinutes },
                set: { value in app.updateProfile { $0.dailyGoalMinutes = value } }
            ), in: 3...120, step: 5)

            Stepper("每日新词 \(app.profile.dailyNewWords) 个", value: Binding(
                get: { app.profile.dailyNewWords },
                set: { value in app.updateProfile { $0.dailyNewWords = value } }
            ), in: 0...60)

            Stepper("复习上限 \(app.profile.dailyReviewLimit) 张", value: Binding(
                get: { app.profile.dailyReviewLimit },
                set: { value in app.updateProfile { $0.dailyReviewLimit = value } }
            ), in: 10...300, step: 10)
        } header: {
            Text("学习目标")
        } footer: {
            Text("等级影响推荐排序与新词难度，不会限制你能看什么。")
        }
    }

    // MARK: Subtitles

    private var subtitleSection: some View {
        Section("字幕") {
            Toggle("振假名", isOn: Binding(
                get: { app.profile.furiganaEnabled },
                set: { value in app.updateProfile { $0.furiganaEnabled = value } }
            ))
            Toggle("罗马字", isOn: Binding(
                get: { app.profile.romajiEnabled },
                set: { value in app.updateProfile { $0.romajiEnabled = value } }
            ))
            Toggle("翻译", isOn: Binding(
                get: { app.profile.translationEnabled },
                set: { value in app.updateProfile { $0.translationEnabled = value } }
            ))
            Picker("翻译语言", selection: Binding(
                get: { app.profile.translationLanguage },
                set: { value in app.updateProfile { $0.translationLanguage = value } }
            )) {
                ForEach(TranslationLanguage.allCases) { language in
                    Text(language.label).tag(language)
                }
            }
        }
    }

    // MARK: Playback

    private var playbackSection: some View {
        Section("播放") {
            Toggle("进入片段自动播放", isOn: Binding(
                get: { app.profile.autoplayEnabled },
                set: { value in app.updateProfile { $0.autoplayEnabled = value } }
            ))
            Toggle("循环片段", isOn: Binding(
                get: { app.profile.loopClip },
                set: { value in app.updateProfile { $0.loopClip = value } }
            ))
            VStack(alignment: .leading, spacing: 4) {
                Text("视频速度 \(String(format: "%.2fx", app.profile.playbackRate))")
                    .font(Theme.font(size: 12))
                Slider(value: Binding(
                    get: { app.profile.playbackRate },
                    set: { value in app.updateProfile { $0.playbackRate = value } }
                ), in: 0.5...1.5, step: 0.05)
                .tint(Theme.accent)
                .accessibilityLabel(Text("视频速度"))
                .accessibilityValue(Text(String(format: "%.2f 倍", app.profile.playbackRate)))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("朗读速度 \(String(format: "%.2f", app.profile.speechRate))")
                    .font(Theme.font(size: 12))
                Slider(value: Binding(
                    get: { app.profile.speechRate },
                    set: { value in app.updateProfile { $0.speechRate = value } }
                ), in: 0.3...0.62, step: 0.02)
                .tint(Theme.accent)
                .accessibilityLabel(Text("朗读速度"))
                .accessibilityValue(Text(String(format: "%.2f", app.profile.speechRate)))
            }
            if !app.speech.hasJapaneseVoice {
                Text("没有检测到日语语音包，可在 系统设置 › 辅助功能 › 朗读内容 中下载。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.rose)
            }
        }
    }

    // MARK: Voice

    private var voiceSection: some View {
        Section {
            Picker("朗读方式", selection: Binding(
                get: { selectedMode },
                set: { value in app.updateVoiceOptions { $0.mode = value } }
            )) {
                ForEach(ReadAloudMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }

            if selectedMode == .server {
                TextField("朗读服务器（留空则复用转写地址）", text: Binding(
                    get: { app.voiceOptions.serverURL },
                    set: { value in app.updateVoiceOptions { $0.serverURL = value } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityLabel(Text("朗读服务器地址"))
                HStack {
                    Spacer()
                    Text(effectiveReadAloudServer)
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            Picker("日语语音", selection: Binding(
                get: { app.voiceOptions.voice },
                set: { value in app.updateVoiceOptions { $0.voice = value } }
            )) {
                ForEach(EdgeTTSVoice.allCases) { voice in
                    Text(voice.title).tag(voice)
                }
            }

            if app.voiceOptions.voice == .custom {
                TextField("语音 ID，例如 ja-JP-NanamiNeural", text: Binding(
                    get: { app.voiceOptions.customVoiceID },
                    set: { value in app.updateVoiceOptions { $0.customVoiceID = value } }
                ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            }

            HStack {
                Button("试听") {
                    app.speech.speak("こんにちは、今日はいい天気ですね。", rate: app.profile.speechRate)
                }
                .font(Theme.font(size: 13, weight: .semibold))
                .accessibilityHint(Text("用当前语音朗读一句日语"))
                Spacer()
                Text(lastEngineLabel)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("朗读语音")
        } footer: {
            Text("三种方式都只发送要朗读的文本，不附带账号或学习记录。「服务器合成」会请求你自己的 edge-tts 代理（POST /tts），地址留空时复用「云端转写」里填的服务器；「Edge 直连」由本机直接请求 Microsoft，被其反滥用校验拒绝时自动改用系统语音；任何失败都不会弹窗打断学习。")
        }
    }

    /// The picker must show what the user chose, not the normalised engine mode:
    /// a stored `.server` with an empty address still reads as "server" here so
    /// the row stays selected and the address field stays visible.
    private var selectedMode: ReadAloudMode {
        if let stored = app.voiceOptions.mode { return stored }
        return app.voiceOptions.effectiveMode(transcriptionURL: app.transcription.serverURL)
    }

    private var effectiveReadAloudServer: String {
        let resolved = app.voiceOptions.resolvedServerURL(transcriptionURL: app.transcription.serverURL)
        return resolved.isEmpty ? "未配置地址" : resolved
    }

    private var lastEngineLabel: String {
        switch app.speech.lastEngine {
        case "edge": return "上次：Edge 直连"
        case "server": return "上次：服务器合成"
        default: return "上次：系统语音"
        }
    }

    // MARK: AI

    private var aiSection: some View {
        Section {
            Toggle("使用 AI 解释语境", isOn: Binding(
                get: { app.profile.aiEnabled },
                set: { value in app.updateProfile { $0.aiEnabled = value } }
            ))

            if app.profile.aiEnabled {
                TextField("接口地址（OpenAI 兼容）", text: $baseURLDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        app.updateProfile { $0.aiBaseURL = baseURLDraft }
                    }
                TextField("模型名", text: $modelDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit {
                        app.updateProfile { $0.aiModel = modelDraft }
                    }
                SecureField(app.aiKeyStored ? "已保存密钥，留空则保留" : "API Key", text: $keyDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                HStack {
                    Button("保存密钥") {
                        app.saveAIKey(keyDraft)
                        keyDraft = ""
                        app.updateProfile {
                            $0.aiBaseURL = baseURLDraft
                            $0.aiModel = modelDraft
                        }
                    }
                    .font(Theme.font(size: 13, weight: .semibold))

                    Spacer()

                    Button(isTesting ? "测试中…" : "测试连接") {
                        Task { await testConnection() }
                    }
                    .font(Theme.font(size: 13))
                    .disabled(isTesting || !app.aiKeyStored)
                }
            }
        } header: {
            Text("AI 语境解释")
        } footer: {
            Text("关闭时使用完全离线的语法分析（断词 + 助词角色 + 变形还原），不联网。开启后会把「字幕 + 被点的词 + 词典释义」发送到你填写的接口。密钥保存在钥匙串。")
        }
    }

    // MARK: Self-hosted transcription

    private var transcriptionSection: some View {
        Section {
            Toggle("启用服务器转写", isOn: Binding(
                get: { app.transcription.isEnabled },
                set: { value in app.updateTranscription { $0.isEnabled = value } }
            ))

            TextField("服务器地址（例如 https://your-host）", text: Binding(
                get: { app.transcription.serverURL },
                set: { value in
                    app.updateTranscription { $0.serverURL = value }
                    // Editing the address invalidates the previous connectivity result.
                    transcriptionTestResult = nil
                }
            ))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityLabel(Text("转写服务器地址"))

            HStack {
                Spacer()
                Text(app.transcription.statusLabel)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(app.transcription.isConfigured ? Theme.jade : Theme.secondaryText)
            }

            Toggle("同时请求中文翻译", isOn: Binding(
                get: { app.transcription.translateToChinese },
                set: { value in app.updateTranscription { $0.translateToChinese = value } }
            ))

            Stepper("超时 \(app.transcription.timeoutSeconds) 秒", value: Binding(
                get: { app.transcription.timeoutSeconds },
                set: { value in app.updateTranscription { $0.timeoutSeconds = value } }
            ), in: 15...300, step: 15)

            HStack {
                Button(isTestingTranscription ? "测试中…" : "测试连接") {
                    Task { await testTranscription() }
                }
                .font(Theme.font(size: 13))
                .disabled(isTestingTranscription || app.transcription.healthURL == nil)
                Spacer()
                if let transcriptionTestResult {
                    Text(transcriptionTestResult)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Text("云端转写（可选）")
        } footer: {
            Text("默认关闭。开启并填好地址后，「导入 YouTube 片段」会多出一个「服务器转写」按钮：把视频 ID 发到你的服务器，取回带时间轴的日文字幕（以及可选的中文翻译）。Kotoba 不内置地址、密钥或令牌；鉴权请在你的服务器或反向代理上做。没有配置时一切功能仍按离线流程工作。")
        }
    }

    private func testTranscription() async {
        isTestingTranscription = true
        transcriptionTestResult = await app.pingTranscriptionServer()
        isTestingTranscription = false
    }

    // MARK: Data

    private var dataSection: some View {
        Section("数据") {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("分享导出文件", systemImage: "square.and.arrow.up")
                }
            }
            Button {
                if let url = app.exportState() {
                    exportURL = url
                    app.toast = "已导出到 \(url.lastPathComponent)"
                }
            } label: {
                Label("导出备份 (JSON)", systemImage: "arrow.down.doc")
            }
            Button {
                isRestoring = true
            } label: {
                Label("从备份恢复 (JSON)", systemImage: "arrow.up.doc")
            }
            Button {
                if let url = app.exportAnkiTSV() {
                    ankiURL = url
                    app.toast = "已导出 \(url.lastPathComponent)"
                }
            } label: {
                Label("导出 Anki 卡片 (TSV)", systemImage: "square.and.arrow.up.on.square")
            }
            .accessibilityHint(Text("生成 5 列制表符文件，可在 Anki 里导入"))
            if let ankiURL {
                ShareLink(item: ankiURL) {
                    Label("分享 Anki 文件", systemImage: "square.and.arrow.up")
                }
            }
            Button(role: .destructive) {
                showResetAlert = true
            } label: {
                Label("清空所有数据", systemImage: "trash")
            }
        }
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            HStack {
                Text("版本")
                Spacer()
                Text("1.0 (1)").foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Text("内置词条")
                Spacer()
                Text("\(app.dictionary.entries.count)").foregroundStyle(Theme.secondaryText)
            }
            HStack {
                Text("素材")
                Spacer()
                Text("\(app.library.clips.count) 条").foregroundStyle(Theme.secondaryText)
            }
        } header: {
            Text("关于")
        } footer: {
            Text("词典数据来自 OpenJLPT / JMdict / Tatoeba，遵循 CC BY-SA 4.0；详见仓库 ATTRIBUTION.md。应用本身不附带任何影视素材，片段由使用者自行导入并仅在本地播放。")
        }
    }

    // MARK: Actions

    private func performRestore() {
        guard let url = pendingRestoreURL else { return }
        pendingRestoreURL = nil
        do {
            let report = try app.restore(from: url)
            app.toast = "已恢复：\(report.summary)"
        } catch {
            restoreError = error.localizedDescription
            showRestoreError = true
        }
    }

    private func loadDrafts() {
        nameDraft = app.profile.displayName
        baseURLDraft = app.profile.aiBaseURL
        modelDraft = app.profile.aiModel
    }

    private func testConnection() async {
        isTesting = true
        let config = AIConfiguration(
            baseURL: baseURLDraft.isEmpty ? app.profile.aiBaseURL : baseURLDraft,
            model: modelDraft.isEmpty ? app.profile.aiModel : modelDraft,
            apiKey: Secrets.value(for: Secrets.aiKeyAccount) ?? ""
        )
        let explainer = RemoteLLMExplainer(configuration: config, language: app.profile.aiLanguage)
        do {
            let result = try await explainer.explain(
                word: "映画",
                sentence: "昨日友達と映画を見に行きました。",
                entry: app.dictionary.best("映画")
            )
            app.toast = "连接成功：\(result.headline.prefix(28))…"
        } catch {
            app.toast = "连接失败：\(error.localizedDescription)"
        }
        isTesting = false
    }
}
