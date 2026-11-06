import SwiftUI

/// Browse the bundled kanji by JLPT level or by radical, and search them.
struct KanjiListView: View {
    @EnvironmentObject private var app: AppModel
    @State private var mode: Mode = .level
    @State private var query = ""
    @State private var levelKey = 1
    @State private var radical = ""
    @State private var visibleCount = 120
    @State private var selected: String?

    enum Mode: String, CaseIterable, Identifiable {
        case level, radical
        var id: String { rawValue }
        var title: String { self == .level ? "按等级" : "按部首" }
    }

    private var levelGroups: [KanjiLevelGroup] { app.kanji.levelGroups }
    private var radicalGroups: [KanjiRadicalGroup] { Array(app.kanji.radicalGroups.prefix(40)) }

    private var searchResults: [KanjiEntry] {
        app.kanji.search(query, limit: 120)
    }

    private var currentEntries: [KanjiEntry] {
        if mode == .level {
            return app.kanji.entries(levelSortKey: levelKey)
        }
        return app.kanji.entries(radical: radical)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summaryCard
                searchField
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    modePicker
                    if mode == .level { levelChips } else { radicalChips }
                    kanjiGrid(searchResults.isEmpty ? currentEntries : [])
                } else {
                    resultList
                }
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("汉字")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: Binding(
            get: { selected.map(KanjiSelection.init) },
            set: { selected = $0?.literal }
        )) { selection in
            KanjiDetailView(literal: selection.literal)
                .environmentObject(app)
        }
    }

    // MARK: Pieces

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(app.kanjiLearnedCount)")
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("已经熟悉的汉字 ・ 复习中 \(app.kanjiCards.count) ・ 待复习 \(app.kanjiDueCount)")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Text("共 \(app.kanji.count) 字")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.accent)
            }
            if app.kanjiCards.isEmpty {
                Text("在汉字详情里点「加入汉字复习」，它就会和生词一起进入复习队列。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
                .font(.system(size: 13))
            TextField("搜索汉字、拼音、读音或意思", text: $query)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var modePicker: some View {
        Picker("分组", selection: $mode) {
            ForEach(Mode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var levelChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(levelGroups) { group in
                    Chip(text: "\(group.label) \(group.count)", isSelected: levelKey == group.key) {
                        levelKey = group.key
                        visibleCount = 120
                    }
                }
            }
        }
    }

    private var radicalChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(radicalGroups) { group in
                    Chip(text: "\(group.radical) \(group.count)", isSelected: radical == group.radical) {
                        radical = group.radical
                        visibleCount = 120
                    }
                }
            }
        }
    }

    private func kanjiGrid(_ entries: [KanjiEntry]) -> some View {
        let shown = Array(entries.prefix(visibleCount))
        return VStack(alignment: .leading, spacing: 8) {
            if entries.isEmpty {
                EmptyStateView(
                    symbol: "character.book.closed",
                    title: "没有可显示的字",
                    message: "换一个等级或部首，或者用搜索。"
                )
                .card()
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6),
                    spacing: 6
                ) {
                    ForEach(shown) { entry in
                        Button {
                            selected = entry.literal
                        } label: {
                            cell(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if entries.count > shown.count {
                    Button("再显示 \(min(120, entries.count - shown.count)) 个") {
                        visibleCount += 120
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    private func cell(_ entry: KanjiEntry) -> some View {
        let card = app.kanjiCard(entry.literal)
        return VStack(spacing: 2) {
            Text(entry.literal)
                .font(.system(size: 22, weight: .medium, design: .serif))
                .foregroundStyle(card != nil ? Theme.familiarityColor(card?.familiarity ?? 1) : Theme.ink)
            Text(entry.meaningSummary)
                .font(.system(size: 8))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.hairline, lineWidth: 1)
        )
    }

    private var resultList: some View {
        VStack(spacing: 0) {
            if searchResults.isEmpty {
                EmptyStateView(
                    symbol: "magnifyingglass",
                    title: "没有匹配的汉字",
                    message: "可以试拼音（ri）、音读（にち）、训读（ひ）或意思（sun）。"
                )
                .card()
            } else {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, entry in
                    Button {
                        selected = entry.literal
                    } label: {
                        HStack(spacing: 10) {
                            Text(entry.literal)
                                .font(.system(size: 24, design: .serif))
                                .foregroundStyle(Theme.ink)
                                .frame(width: 30)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(entry.meaningSummary)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.ink)
                                    if !entry.pinyin.isEmpty {
                                        Text(entry.pinyin)
                                            .font(.system(size: 10, weight: .medium, design: .rounded))
                                            .foregroundStyle(Theme.accent)
                                    }
                                }
                                Text(entry.onReadings.prefix(2).joined(separator: "、"))
                                    .font(.system(size: 10))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            TagLabel(text: entry.levelLabel, tint: Theme.accent)
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if index < searchResults.count - 1 {
                        Hairline().padding(.leading, 52)
                    }
                }
            }
        }
        .card(padded: false)
    }
}

/// Wrapper so `.sheet(item:)` can carry a plain string.
struct KanjiSelection: Identifiable {
    let literal: String
    var id: String { literal }
}
