import SwiftUI

/// Browse the bundled OpenJLPT grammar set (526 entries, N5–N1).
///
/// Read-only: no review scheduling, no entry into the review queue yet. Meanings
/// are English from the source, so every row is labelled 「英文原文」.
struct GrammarBrowseView: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @State private var level: JLPTLevel?
    @State private var query = ""
    @State private var selected: GrammarEntry?

    private var visible: [GrammarEntry] {
        app.grammar.search(query, level: level)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard
                searchField
                levelChips
                list
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("语法")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selected) { entry in
            GrammarDetailSheet(entry: entry)
        }
    }

    // MARK: Pieces

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(visible.count) 条语法")
                .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text(app.grammar.isLoaded ? app.grammar.status : "语法表尚未载入")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.secondaryText)
            Text("数据来自 OpenJLPT（CC BY-SA 4.0）。释义保留英文原文，未做机器翻译。")
                .font(Theme.font(size: 10))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .a11yCombine("语法浏览，共 \(visible.count) 条，来源 OpenJLPT")
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
                .font(Theme.font(size: 13))
            TextField("搜索句型、罗马字、释义", text: $query)
                .font(Theme.font(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(Text("搜索语法"))
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
                Chip(text: "全部", isSelected: level == nil) { level = nil }
                ForEach(JLPTLevel.allCases, id: \.self) { candidate in
                    let count = app.grammar.entries(for: candidate).count
                    Chip(
                        text: "\(candidate.label) \(count)",
                        isSelected: level == candidate,
                        tint: Theme.levelColor(candidate)
                    ) {
                        level = candidate
                    }
                }
            }
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            if visible.isEmpty {
                EmptyStateView(
                    symbol: "text.book.closed",
                    title: "没有匹配的语法",
                    message: query.isEmpty ? "换一个等级试试。" : "换个关键词，或清空搜索。"
                )
                .card()
            } else {
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        selected = entry
                    } label: {
                        row(entry)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(rowLabel(entry)))
                    .accessibilityHint(Text("双击查看用法与例句"))
                    if index < visible.count - 1 {
                        Hairline().padding(.leading, 14)
                    }
                }
            }
        }
        .card(padded: false)
    }

    private func row(_ entry: GrammarEntry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.pattern)
                        .font(Theme.font(size: 15, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    LevelBadge(level: shown.level)
                }
                if let romaji = entry.romaji, !romaji.isEmpty {
                    Text(romaji)
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(entry.meaningEN)
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if app.grammar.status(for: entry) != .unseen {
                Text(app.grammar.status(for: entry).title)
                    .font(Theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(
                        app.grammar.status(for: entry) == .learned ? Theme.jade : Theme.amber
                    )
            }
            Text("EN")
                .font(Theme.font(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
    }

    private func rowLabel(_ entry: GrammarEntry) -> String {
        let level = entry.level?.label ?? "未分级"
        let romaji = entry.romaji.map { "，罗马字 \($0)" } ?? ""
        return "\(entry.pattern)\(romaji)，\(level)，英文释义 \(entry.meaningEN)"
    }
}

// MARK: - Detail

struct GrammarDetailSheet: View {
    let entry: GrammarEntry
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var app: AppModel

    /// The entry on screen; tapping a related row swaps it without stacking sheets.
    @State private var current: GrammarEntry?

    private var shown: GrammarEntry { current ?? entry }

    private var related: [GrammarEntry] {
        app.grammar.related(to: shown)
    }

    private var status: GrammarStatus {
        app.grammar.status(for: shown)
    }

    /// Example furigana follows the same reading preference as the rest of the app.
    private var showFurigana: Bool {
        app.profile.furiganaEnabled
    }

    /// Label for the next tap, matching `GrammarStatus.next`.
    private var toggleTitle: String {
        switch status {
        case .unseen: return "标记为学习中"
        case .learning: return "标记为已学会"
        case .learned: return "取消标记"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerCard
                    statusCard
                    if !shown.formation.isEmpty { formationCard }
                    if let notes = shown.notesEN, !notes.isEmpty { notesCard(notes) }
                    if !shown.examples.isEmpty { examplesCard }
                    if !related.isEmpty { relatedCard }
                    attributionCard
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("语法详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(shown.pattern)
                    .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                LevelBadge(level: shown.level)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                if let romaji = shown.romaji, !romaji.isEmpty {
                    Text(romaji)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Button {
                    app.speech.speak(shown.pattern, rate: app.profile.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .a11yButton("朗读句型", hint: "用当前语音读出这个句型")
            }
            Text(shown.meaningEN)
                .font(Theme.font(size: 14))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TagLabel(text: "英文原文", tint: Theme.secondaryText)
                if !shown.zhStatus.isEmpty {
                    TagLabel(text: shown.zhStatus, tint: Theme.hairline)
                }
            }
            if !shown.tags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(shown.tags.prefix(4), id: \.self) { tag in
                        TagLabel(text: tag, tint: Theme.lilac)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var statusCard: some View {
        HStack(spacing: 10) {
            TagLabel(
                text: status.title,
                tint: status == .learned ? Theme.jade : (status == .learning ? Theme.amber : Theme.secondaryText)
            )
            Spacer(minLength: 0)
            Button {
                app.toggleGrammarStatus(shown)
            } label: {
                Text(toggleTitle)
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.accent.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)
            .a11yButton(toggleTitle, hint: "切换这条语法的学习状态")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .a11yCombine("当前状态：\(status.title)")
    }

    private var formationCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "接续")
            Text(shown.formation)
                .font(Theme.font(size: 13, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func notesCard(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionHeader(title: "说明（英文原文）")
            Text(notes)
                .font(Theme.font(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "例句")
            ForEach(Array(shown.examples.enumerated()), id: \.offset) { _, example in
                VStack(alignment: .leading, spacing: 3) {
                    Text(example.ja)
                        .font(Theme.font(size: 15, design: .serif))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if showFurigana, let furigana = example.furigana, !furigana.isEmpty {
                        Text(furigana)
                            .font(Theme.font(size: 10))
                            .foregroundStyle(Theme.secondaryText.opacity(0.8))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !example.en.isEmpty {
                        Text(example.en)
                            .font(Theme.font(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button {
                        app.speech.speak(example.ja, rate: app.profile.speechRate)
                    } label: {
                        Label("朗读例句", systemImage: "speaker.wave.1")
                            .font(Theme.font(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .a11yButton("朗读例句", hint: "读出这句日语")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .a11yCombine("\(example.ja)，\(example.en)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var relatedCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "相关语法")
            ForEach(Array(related.enumerated()), id: \.element.id) { index, candidate in
                Button {
                    current = candidate
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(candidate.pattern)
                                    .font(Theme.font(size: 14, weight: .medium, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                LevelBadge(level: candidate.level)
                            }
                            Text(candidate.meaningEN)
                                .font(Theme.font(size: 10))
                                .foregroundStyle(Theme.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(Theme.font(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .a11yButton(
                    "\(candidate.pattern)，\(candidate.level?.label ?? "未分级")，英文释义 \(candidate.meaningEN)",
                    hint: "双击查看这条语法"
                )
                if index < related.count - 1 {
                    Hairline()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var attributionCard: some View {
        Text("句型与英文释义来自 OpenJLPT（CC BY-SA 4.0）。中文释义尚未人工核对，因此不显示。")
            .font(Theme.font(size: 10))
            .foregroundStyle(Theme.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
    }
}
