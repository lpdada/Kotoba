import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct ClipImporterView: View {
    @EnvironmentObject private var app: AppModel

    @State private var isImportingClips = false
    @State private var isImportingMedia = false
    @State private var showFormat = false

    private var mediaFiles: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: app.store.mediaDirectory().path))?.sorted() ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                introCard
                importCard
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
    }

    // MARK: Cards

    private var introCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("用自己的素材学日语")
                .font(.system(size: 19, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("应用不附带任何影视片段。你可以把自己合法持有的短视频或音频放进本地媒体目录，再导入一份字幕清单，就能像内置示例一样滚动学习。所有文件只保存在这台设备上。")
                .font(.system(size: 12))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(mediaFiles, id: \.self) { file in
                        HStack(spacing: 8) {
                            Image(systemName: icon(for: file))
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.accent)
                            Text(file)
                                .font(.system(size: 12, design: .monospaced))
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
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .buttonStyle(.plain)

            if showFormat {
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.sampleJSON)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                    HStack {
                        Button("复制示例") {
                            UIPasteboard.general.string = Self.sampleJSON
                            app.toast = "示例已复制"
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        Spacer()
                    }
                    Text("要点：transcript 一行一句；media 支持 {\"kind\":\"localFile\",\"value\":\"文件名.mp4\"}、{\"kind\":\"generated\"}（无视频时用朗读演示）或 {\"kind\":\"youtube\",\"id\":\"…\",\"start\":12,\"end\":24}（使用官方内嵌播放器，视频仍由平台托管）。")
                        .font(.system(size: 10))
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
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(app.customClips) { clip in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(clip.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text("\(clip.media.shortLabel) ・ \(clip.lines.count) 行 ・ \(Int(clip.durationSeconds))s")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Button {
                                app.removeCustomClip(clip)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.system(size: 13))
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
