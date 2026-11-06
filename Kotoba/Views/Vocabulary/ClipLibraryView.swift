import SwiftUI

/// Leveled library over the clips you imported yourself.
///
/// There is deliberately no bundled catalog of third-party videos: the entries
/// here are your own YouTube links, subtitle imports and local files, grouped by
/// the app's estimated JLPT level.
struct ClipLibraryView: View {
    @EnvironmentObject private var app: AppModel
    @State private var level: JLPTLevel?
    @State private var source: AppModel.ClipSourceFilter = .all
    @State private var query = ""
    @State private var selected: Clip?

    private var clips: [Clip] {
        app.libraryClips(level: level, query: query, source: source)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard
                searchField
                levelChips
                sourcePicker
                list
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("素材库")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { clip in
            ClipInfoSheet(clip: clip)
                .environmentObject(app)
        }
    }

    // MARK: Pieces

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(clips.count) 条片段")
                .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("按估算等级整理你自己的素材；YouTube 片段在导入时抓取的字幕也会显示在这里。")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
                .font(Theme.font(size: 13))
            TextField("搜索标题、系列或字幕内容", text: $query)
                .font(Theme.font(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("搜索素材"))
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
                .a11yButton("清空搜索")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(text: "全部等级", isSelected: level == nil) { level = nil }
                ForEach(JLPTLevel.allCases, id: \.self) { candidate in
                    Chip(text: candidate.label, isSelected: level == candidate, tint: Theme.levelColor(candidate)) {
                        level = candidate
                    }
                }
            }
        }
    }

    private var sourcePicker: some View {
        Picker("来源", selection: $source) {
            ForEach(AppModel.ClipSourceFilter.allCases) { filter in
                Text(filter.title).tag(filter)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityLabel(Text("按来源筛选"))
    }

    private var list: some View {
        VStack(spacing: 0) {
            if clips.isEmpty {
                EmptyStateView(
                    symbol: "film.stack",
                    title: "没有匹配的片段",
                    message: "换个等级或来源，或者在「内容管理」里导入 YouTube 链接、字幕文件。"
                )
                .card()
            } else {
                ForEach(Array(clips.enumerated()), id: \.element.id) { index, clip in
                    Button {
                        selected = clip
                    } label: {
                        row(clip)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(rowAccessibility(clip)))
                    .accessibilityHint(Text("双击查看片段信息"))
                    if index < clips.count - 1 {
                        Hairline().padding(.leading, 14)
                    }
                }
            }
        }
        .card(padded: false)
    }

    private func row(_ clip: Clip) -> some View {
        let estimate = app.metricsByClip[clip.id]?.level ?? clip.level
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(clip.title)
                        .font(Theme.font(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    LevelBadge(level: estimate)
                }
                Text("\(clip.displaySeries) · \(clip.media.shortLabel) · \(clip.lines.count) 句")
                    .font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                if let first = clip.lines.first {
                    Text(first)
                        .font(Theme.font(size: 11, design: .serif))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if app.savedClipIDs.contains(clip.id) {
                Image(systemName: "bookmark.fill")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.amber)
            }
            Image(systemName: "chevron.right")
                .font(Theme.font(size: 11, weight: .semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func rowAccessibility(_ clip: Clip) -> String {
        let estimate = app.metricsByClip[clip.id]?.level ?? clip.level
        let level = estimate?.label ?? "未分级"
        return "\(clip.title)，\(clip.displaySeries)，\(clip.media.shortLabel)，\(level)，\(clip.lines.count) 句"
    }
}
