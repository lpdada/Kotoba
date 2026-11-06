import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ClipImporterView: View {
    @EnvironmentObject private var app: AppModel

    @State private var isImportingClips = false
    @State private var isImportingMedia = false
    @State private var showFormat = false

    // YouTube card
    @State private var youtubeLink = ""
    @State private var youtubeTitle = ""
    @State private var youtubeJapanese = ""
    @State private var youtubeChinese = ""
    @State private var youtubeLevel: JLPTLevel = .n5
    @State private var youtubeStart = ""
    @State private var youtubeEnd = ""

    // Subtitle card
    @State private var isImportingSubtitles = false
    @State private var subtitleMediaName = ""
    @State private var subtitleSeries = ""
    @State private var subtitleLines = 3
    @State private var subtitleMaxSeconds = 12.0
    @State private var subtitleLevel: JLPTLevel = .n5
    @State private var subtitleStatus: String?
    @State private var subtitleError: String?

    private var mediaFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: app.store.mediaDirectory().path))?.sorted() ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                importCard
                youtubeCard
                subtitleCard
                mediaCard
                formatCard
                customClipsCard
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("内容管理")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(
            isPresented: $isImportingClips,
            allowedContentTypes: [.json],
            allowsMultipleSelection: false
        ) { result in
            handleClipImport(result)
        }
        .fileImporter(
            isPresented: $isImportingMedia,
            allowedContentTypes: [.movie, .audio, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleMediaImport(result)
        }
        .fileImporter(
            isPresented: $isImportingSubtitles,
            allowedContentTypes: Self.subtitleTypes,
            allowsMultipleSelection: false
        ) { result in
            handleSubtitleImport(result)
        }
    }

    private static let subtitleTypes: [UTType] = {
        var types: [UTType] = [.plainText]
        for ext in ["srt", "vtt", "sbv", "ass", "ssa", "txt"] {
            if let type = UTType(filenameExtension: ext), !types.contains(type) {
                types.append(type)
            }
        }
        return types
    }()

    // MARK: Cards

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用自己的素材学日语")
                .font(Theme.font(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("应用不附带任何影视片段。你可以把自己合法持有的短视频或音频放进本地媒体目录，再导入一份字幕清单，就能像内置示例一样滚动学习。所有文件只保存在这台设备上。")
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TagLabel(text: "本地播放", tint: Theme.jade)
                TagLabel(text: "不上传", tint: Theme.accent)
                TagLabel(text: "可随时删除", tint: Theme.lilac)
            }
        }
        .card()
    }

    private var importCard: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(title: "导入片段清单 (.json)", systemImage: "doc.badge.plus") {
                isImportingClips = true
            }
            SecondaryActionButton(title: "导入视频 / 音频文件", systemImage: "film") {
                isImportingMedia = true
            }
        }
    }

    private var mediaCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "本地媒体", subtitle: "文件 App › 我的 iPhone › Kotoba › Media")
            if mediaFiles.isEmpty {
                Text("还没有媒体文件。导入后，片段里的 media 填文件名即可，例如 \"clip01.mp4\"。")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(mediaFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: file))
                                .font(Theme.font(size: 12))
                                .foregroundStyle(Theme.accent)
                            Text(file)
                                .font(Theme.font(size: 12, design: .monospaced))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var formatCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showFormat.toggle() }
            } label: {
                HStack {
                    SectionHeader(title: "清单格式", subtitle: "点击展开示例")
                    Image(systemName: showFormat ? "chevron.up" : "chevron.down")
                        .font(Theme.font(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if showFormat {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.sampleJSON)
                        .font(Theme.font(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    HStack {
                        Button("复制示例") {
                            UIPasteboard.general.string = Self.sampleJSON
                            app.toast = "示例已复制"
                        }
                        .font(Theme.font(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    Text("要点：transcript 一行一句；media 支持 {\"kind\":\"localFile\",\"value\":\"文件名.mp4\"}、{\"kind\":\"generated\"}（无视频时用朗读演示）或 {\"kind\":\"youtube\",\"id\":\"…\",\"start\":12,\"end\":24}（使用官方内嵌播放器，视频仍由平台托管）。")
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(10)
                .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .card()
    }

    private var customClipsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "已导入片段", subtitle: "\(app.customClips.count) 条")
            if app.customClips.isEmpty {
                Text("暂无自建片段。内置示例共 \(app.library.clips.count) 条，用于演示交互。")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(app.customClips) { clip in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.title)
                                    .font(Theme.font(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text("\(clip.media.shortLabel) ・ \(clip.lines.count) 行 ・ \(Int(clip.durationSeconds))s")
                                    .font(Theme.font(size: 10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Button {
                                app.removeCustomClip(clip)
                            } label: {
                                Image(systemName: "trash")
                                    .font(Theme.font(size: 13))
                                    .foregroundStyle(Theme.rose)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
                .card(padded: false)
            }
        }
    }

    // MARK: Actions

    private func handleClipImport(_ result: Result<[URL], Error>) {
        // The importer callback arrives on the main thread; assert it so the
        // main-actor state changes below are explicit.
        MainActor.assumeIsolated {
            applyClipImport(result)
        }
    }

    private func applyClipImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let count = try app.importClips(from: url)
                app.toast = "已导入 \(count) 条片段"
            } catch {
                app.toast = "导入失败：\(error.localizedDescription)"
            }
        case .failure(let error):
            app.toast = "导入取消：\(error.localizedDescription)"
        }
    }

    private func handleMediaImport(_ result: Result<[URL], Error>) {
        MainActor.assumeIsolated {
            applyMediaImport(result)
        }
    }

    private func applyMediaImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            var copied = 0
            for url in urls {
                do {
                    _ = try app.copyMediaFile(from: url)
                    copied += 1
                } catch {
                    app.toast = "复制失败：\(error.localizedDescription)"
                }
            }
            if copied > 0 { app.toast = "已导入 \(copied) 个媒体文件" }
        case .failure(let error):
            app.toast = "导入取消：\(error.localizedDescription)"
        }
    }

    private func icon(for file: String) -> String {
        let lower = file.lowercased()
        if lower.hasSuffix(".mp4") || lower.hasSuffix(".mov") || lower.hasSuffix(".m4v") { return "film" }
        if lower.hasSuffix(".mp3") || lower.hasSuffix(".m4a") || lower.hasSuffix(".wav") { return "waveform" }
        return "doc"
    }

    // MARK: Subtitles

    private var subtitleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "导入字幕（SRT / VTT）",
                subtitle: "按句数与时长自动切片；同一个视频的字幕会切成多条可滚动片段"
            )

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("视频文件名（留空则用朗读演示）")
                TextField("例如：ep01.mp4", text: $subtitleMediaName)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Theme.font(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                if !mediaFiles.isEmpty {
                    Text("可选：" + mediaFiles.prefix(3).joined(separator: "、") + (mediaFiles.count > 3 ? " …" : ""))
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("片段名称（留空则用字幕文件名）")
                TextField("例如：第 1 话", text: $subtitleSeries)
                    .font(Theme.font(size: 13))
                    .padding(10)
                    .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("每段句数")
                    Stepper("\(subtitleLines) 句", value: $subtitleLines, in: 1...6)
                        .font(Theme.font(size: 13))
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("最长时长")
                    Stepper("\(Int(subtitleMaxSeconds)) 秒", value: $subtitleMaxSeconds, in: 4...40, step: 2)
                        .font(Theme.font(size: 13))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                fieldLabel("等级")
                Picker("等级", selection: $subtitleLevel) {
                    ForEach(JLPTLevel.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            PrimaryActionButton(title: "选择字幕文件", systemImage: "captions.bubble") {
                subtitleError = nil
                isImportingSubtitles = true
            }

            if let subtitleStatus {
                Text(subtitleStatus)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.jade)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let subtitleError {
                Text(subtitleError)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.rose)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("支持 BOM、CRLF、序号行、`<i>` 标签、ASS 覆盖标记与重复滚动字幕；字幕文本会自动分词，点词即可查读音与释义。")
                .font(Theme.font(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func handleSubtitleImport(_ result: Result<[URL], Error>) {
        MainActor.assumeIsolated {
            applySubtitleImport(result)
        }
    }

    private func applySubtitleImport(_ result: Result<[URL], Error>) {
        subtitleStatus = nil
        subtitleError = nil
        switch result {
        case .failure(let error):
            subtitleError = "选择文件失败：\(error.localizedDescription)"
        case .success(let urls):
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                let data = try Data(contentsOf: url)
                let parsed = try SubtitleParser.parse(data: data)
                let baseName = url.deletingPathExtension().lastPathComponent
                let typedMedia = subtitleMediaName.trimmingCharacters(in: .whitespaces)
                let resolvedMedia = typedMedia.isEmpty ? matchedMediaFileName(for: baseName) : typedMedia
                let typedSeries = subtitleSeries.trimmingCharacters(in: .whitespaces)
                let series = typedSeries.isEmpty ? baseName : typedSeries
                let added = app.importSubtitleCues(
                    parsed,
                    mediaFileName: resolvedMedia,
                    series: series,
                    level: subtitleLevel,
                    linesPerClip: subtitleLines,
                    maxSeconds: subtitleMaxSeconds
                )
                var parts = [
                    "\(parsed.format.rawValue.uppercased())：\(parsed.cues.count) 条字幕",
                    "生成 \(added) 条片段"
                ]
                if parsed.skippedBlocks > 0 { parts.append("跳过 \(parsed.skippedBlocks) 个异常块") }
                if resolvedMedia.isEmpty { parts.append("未找到同名视频，使用朗读模式") }
                subtitleStatus = parts.joined(separator: "，")
                if added > 0 {
                    app.toast = "已从字幕生成 \(added) 条片段"
                } else {
                    subtitleError = "这些字幕对应的片段已经在库里了"
                }
            } catch {
                subtitleError = error.localizedDescription
            }
        }
    }

    /// Tries to pair "ep01.srt" with "ep01.mp4" (or any video whose name starts with it).
    private func matchedMediaFileName(for baseName: String) -> String {
        let playable = ["mp4", "m4v", "mov", "mp3", "m4a", "wav"]
        let videos = mediaFiles.filter { playable.contains(URL(fileURLWithPath: $0).pathExtension.lowercased()) }
        if let exact = videos.first(where: {
            URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent == baseName
        }) {
            return exact
        }
        if let prefixed = videos.first(where: {
            URL(fileURLWithPath: $0).lastPathComponent.lowercased().hasPrefix(baseName.lowercased())
        }) {
            return prefixed
        }
        return ""
    }

    // MARK: YouTube

    private var youtubeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "导入 YouTube 片段", subtitle: "用官方内嵌播放器循环这个区间，视频仍由平台托管")

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("链接或视频 ID")
                TextField("https://www.youtube.com/watch?v=…", text: $youtubeLink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(Theme.font(size: 13, design: .monospaced))
                    .padding(10)
                    .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                if let parsedLink {
                    HStack(spacing: 6) {
                        TagLabel(text: "ID \(parsedLink.videoID)", tint: Theme.accent)
                        if let start = parsedLink.startSeconds {
                            TagLabel(text: "链接自带起点 \(Int(start)) 秒", tint: Theme.lilac)
                        }
                    }
                } else if !youtubeLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("无法识别这个链接。支持 watch?v= / youtu.be / shorts / embed / live，或直接粘贴 11 位视频 ID。")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.rose)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("标题")
                TextField("例如：便利店点单", text: $youtubeTitle)
                    .font(Theme.font(size: 13))
                    .padding(10)
                    .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("日文字幕（一行一句）")
                editor(
                    text: $youtubeJapanese,
                    placeholder: "すみません、これ、ください。\nはい、二百円です。",
                    height: 96
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("中文翻译（与上一栏一一对应）")
                editor(
                    text: $youtubeChinese,
                    placeholder: "不好意思，请给我这个。\n好的，两百日元。",
                    height: 78
                )
            }

            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("等级")
                    Picker("等级", selection: $youtubeLevel) {
                        ForEach(JLPTLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(level)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("起点（秒）")
                    TextField("0", text: $youtubeStart)
                        .keyboardType(.decimalPad)
                        .font(Theme.font(size: 13, design: .rounded))
                        .padding(10)
                        .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 4) {
                    fieldLabel("终点（秒）")
                    TextField("8", text: $youtubeEnd)
                        .keyboardType(.decimalPad)
                        .font(Theme.font(size: 13, design: .rounded))
                        .padding(10)
                        .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }

            if let duration = youtubeDuration {
                Text("片段时长 \(String(format: "%.1f", duration)) 秒，播放时在该区间内循环。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            } else if youtubeRangeInvalid {
                Text("终点需要大于起点。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.rose)
            }

            PrimaryActionButton(
                title: "保存为片段",
                systemImage: "square.and.arrow.down",
                isEnabled: canSaveYouTube
            ) {
                saveYouTubeClip()
            }

            Text("字幕会在导入后自动分词，点词即可查读音、释义与语境解释；视频不下载、不转码。")
                .font(Theme.font(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.font(size: 11, weight: .medium))
            .foregroundStyle(Theme.secondaryText)
    }

    private func editor(text: Binding<String>, placeholder: String, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            if text.wrappedValue.isEmpty {
                Text(placeholder)
                    .font(Theme.font(size: 12, design: .serif))
                    .foregroundStyle(Theme.secondaryText.opacity(0.7))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .allowsHitTesting(false)
            }
            TextEditor(text: text)
                .font(Theme.font(size: 13, design: .serif))
                .scrollContentBackground(.hidden)
                .padding(6)
                .frame(height: height)
        }
        .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var parsedLink: YouTubeLinkParser.Parsed? {
        YouTubeLinkParser.parse(youtubeLink)
    }

    private var youtubeStartValue: Double {
        let typed = Double(youtubeStart.trimmingCharacters(in: .whitespaces))
        return typed ?? parsedLink?.startSeconds ?? 0
    }

    private var youtubeEndValue: Double? {
        let typed = Double(youtubeEnd.trimmingCharacters(in: .whitespaces))
        return typed ?? (youtubeJapanese.isEmpty ? nil : youtubeStartValue + 8)
    }

    private var youtubeDuration: Double? {
        guard let end = youtubeEndValue, end > youtubeStartValue else { return nil }
        return end - youtubeStartValue
    }

    private var youtubeRangeInvalid: Bool {
        guard let end = youtubeEndValue else { return false }
        return end <= youtubeStartValue
    }

    private var canSaveYouTube: Bool {
        guard parsedLink != nil else { return false }
        guard !youtubeJapanese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard youtubeDuration != nil else { return false }
        return true
    }

    private func saveYouTubeClip() {
        guard let parsed = parsedLink, let end = youtubeEndValue else { return }
        let start = youtubeStartValue
        let transcript = youtubeJapanese.trimmingCharacters(in: .whitespacesAndNewlines)
        let translation = youtubeChinese.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = youtubeTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let clip = Clip(
            id: "yt-\(parsed.videoID)-\(Int(start))-\(Int(end))",
            title: title.isEmpty ? "YouTube 片段 \(parsed.videoID)" : title,
            series: "YouTube",
            episode: "",
            transcript: transcript,
            translation: translation,
            translationEN: "",
            level: youtubeLevel,
            topics: [],
            durationSeconds: max(end - start, 1),
            media: .youtube(id: parsed.videoID, start: start, end: end),
            attribution: "YouTube 内嵌播放，视频由平台托管",
            custom: true
        )
        app.addCustomClip(clip)
        app.toast = "已加入片段库：\(clip.title)"
        youtubeLink = ""
        youtubeTitle = ""
        youtubeJapanese = ""
        youtubeChinese = ""
        youtubeStart = ""
        youtubeEnd = ""
    }

    static let sampleJSON = """
    {
      "version": 1,
      "clips": [
        {
          "id": "my-clip-001",
          "title": "便利店点单",
          "series": "我自己的素材",
          "episode": "第 1 话",
          "transcript": "すみません、これください。\\nおいくらですか。",
          "translation": "不好意思，我要这个。\\n多少钱？",
          "level": "n5",
          "topics": ["日常会话"],
          "duration_seconds": 8,
          "media": { "kind": "localFile", "value": "clip01.mp4" },
          "attribution": "个人收藏，仅供自己学习",
          "custom": true
        }
      ]
    }
    """
}

// MARK: - YouTube link parsing

/// Extracts a video id (and an optional start offset) from the URL shapes people
/// actually paste. Kept dependency-free so it can be unit checked on any host.
enum YouTubeLinkParser {
    struct Parsed: Equatable {
        let videoID: String
        let startSeconds: Double?
    }

    static func parse(_ raw: String) -> Parsed? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if isVideoID(trimmed) {
            return Parsed(videoID: trimmed, startSeconds: nil)
        }

        let normalized = trimmed.lowercased().hasPrefix("http") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: normalized) else { return nil }
        let host = (components.host ?? "").lowercased()
        guard host.contains("youtube") || host.hasSuffix("youtu.be") || host == "youtu.be" else { return nil }

        var identifier: String?
        if host == "youtu.be" || host.hasSuffix(".youtu.be") {
            identifier = components.path.split(separator: "/").first.map(String.init)
        } else if let value = components.queryItems?.first(where: { $0.name == "v" })?.value {
            identifier = value
        } else {
            let parts = components.path.split(separator: "/").map(String.init)
            let markers = ["embed", "shorts", "v", "live", "e"]
            if let index = parts.firstIndex(where: { markers.contains($0) }), index + 1 < parts.count {
                identifier = parts[index + 1]
            }
        }

        guard let videoID = identifier, isVideoID(videoID) else { return nil }
        return Parsed(videoID: videoID, startSeconds: startOffset(in: components))
    }

    static func isVideoID(_ candidate: String) -> Bool {
        guard candidate.count == 11 else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return candidate.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func startOffset(in components: URLComponents) -> Double? {
        if let value = components.queryItems?.first(where: { $0.name == "t" || $0.name == "start" })?.value,
           let seconds = seconds(from: value) {
            return seconds
        }
        if let fragment = components.fragment, fragment.hasPrefix("t=") {
            return seconds(from: String(fragment.dropFirst(2)))
        }
        return nil
    }

    /// Accepts "90", "90s", "1m30s", "1h2m3s" — the formats YouTube links use.
    static func seconds(from value: String) -> Double? {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "hms")) == nil {
            return Double(trimmed)
        }
        var total: Double = 0
        var digits = ""
        for character in trimmed {
            if character.isNumber {
                digits.append(character)
                continue
            }
            guard let number = Double(digits) else { return nil }
            switch character {
            case "h": total += number * 3600
            case "m": total += number * 60
            case "s": total += number
            default: return nil
            }
            digits = ""
        }
        return total > 0 ? total : nil
    }
}
