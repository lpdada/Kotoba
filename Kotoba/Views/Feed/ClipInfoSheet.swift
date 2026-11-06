import SwiftUI

struct ClipInfoSheet: View {
    let clip: Clip

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var analysis: ClipAnalysis?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(clip.title)
                            .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                            .foregroundStyle(Theme.ink)
                        HStack(spacing: 6) {
                            Text(clip.displaySeries)
                                .font(Theme.font(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                            if !clip.episode.isEmpty {
                                Text("·")
                                    .font(Theme.font(size: 12))
                                    .foregroundStyle(Theme.secondaryText)
                                Text(clip.episode)
                                    .font(Theme.font(size: 12))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        HStack(spacing: 6) {
                            LevelBadge(level: analysis?.metrics.level ?? clip.level)
                            ForEach(clip.topics, id: \.self) { topic in
                                TagLabel(text: topic)
                            }
                            TagLabel(text: clip.media.shortLabel, tint: Theme.lilac)
                        }
                        .padding(.top, 2)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "难度诊断", subtitle: "根据字幕里的词汇分布估算")
                        if let analysis {
                            HStack(spacing: 10) {
                                StatTile(
                                    title: "估算等级",
                                    value: analysis.metrics.level.label,
                                    caption: "综合 \(analysis.metrics.uniqueWordCount) 个不同词",
                                    tint: Theme.levelColor(analysis.metrics.level)
                                )
                                StatTile(
                                    title: "生词占比",
                                    value: String(format: "%.0f%%", analysis.metrics.unknownRatio * 100),
                                    caption: "越低越适合精听",
                                    tint: analysis.metrics.unknownRatio > 0.35 ? Theme.rose : Theme.jade
                                )
                                StatTile(
                                    title: "词数",
                                    value: "\(analysis.metrics.tokenCount)",
                                    caption: "含助词",
                                    tint: Theme.accent
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "字幕与翻译", subtitle: "长按可复制")
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(clip.lines.enumerated()), id: \.offset) { index, line in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line)
                                        .font(Theme.font(size: 15, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                        .textSelection(.enabled)
                                    if let translation = clip.translationLines[safe: index] {
                                        Text(translation)
                                            .font(Theme.font(size: 12))
                                            .foregroundStyle(Theme.secondaryText)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card()
                    }

                    VStack(spacing: 10) {
                        PrimaryActionButton(title: "保存整句卡片", systemImage: "text.quote") {
                            app.saveSentence(
                                text: clip.lines.joined(separator: "\n"),
                                translation: clip.translation,
                                clip: clip
                            )
                        }
                        SecondaryActionButton(
                            title: app.savedClipIDs.contains(clip.id) ? "取消收藏片段" : "收藏片段",
                            systemImage: "bookmark",
                            tint: Theme.amber
                        ) {
                            app.toggleSavedClip(clip)
                        }
                        .accessibilityValue(Text(app.savedClipIDs.contains(clip.id) ? "已收藏" : "未收藏"))
                    }

                    if !clip.attribution.isEmpty {
                        Text("素材来源：\(clip.attribution)")
                            .font(Theme.font(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("片段信息")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            analysis = app.library.analysis(for: clip, tokenizer: app.tokenizer)
        }
    }
}
