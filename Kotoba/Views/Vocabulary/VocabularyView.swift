import SwiftUI

struct VocabularyView: View {
    @EnvironmentObject private var app: AppModel
    @State private var searchText = ""
    @State private var mode: Mode = .notebook
    @State private var filter: Filter = .all

    enum Mode: String, CaseIterable, Identifiable {
        case notebook, dictionary
        var id: String { rawValue }
        var title: String { self == .notebook ? "生词本" : "词典" }
    }

    enum Filter: String, CaseIterable, Identifiable {
        case all, fresh, learning, familiar, mastered
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "全部"
            case .fresh: return "新词"
            case .learning: return "学习中"
            case .familiar: return "熟悉"
            case .mastered: return "掌握"
            }
        }

        func matches(_ word: SavedWord) -> Bool {
            switch self {
            case .all: return true
            case .fresh: return word.scheduling.isNew
            case .learning: return !word.scheduling.isNew && word.familiarity <= 2
            case .familiar: return word.familiarity == 3 || word.familiarity == 4
            case .mastered: return word.familiarity >= 5
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    summaryCard
                    modePicker
                    searchField
                    if mode == .notebook {
                        filterRow
                        notebookList
                    } else {
                        dictionaryList
                    }
                }
                .padding(18)
                .padding(.bottom, 12)
            }
            .background(Theme.screenBackground)
            .navigationTitle("生词")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        DecksView()
                    } label: {
                        Image(systemName: "square.stack.3d.up")
                    }
                }
            }
        }
    }

    // MARK: Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(app.knownWordCount)")
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.ink)
                    Text("已经熟悉的词 ・ 共 \(app.words.count) 个")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(app.learningWordCount)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                    Text("学习中")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(app.dueReviewCount())")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.rose)
                    Text("待复习")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            HStack(spacing: 6) {
                ForEach(1...5, id: \.self) { level in
                    let count = app.familiarityCounts[level] ?? 0
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.familiarityColor(level))
                            .frame(height: 4)
                            .opacity(count > 0 ? 1 : 0.25)
                        Text("\(count)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondaryText)
                    }
                }
            }
        }
        .card()
    }

    private var modePicker: some View {
        Picker("模式", selection: $mode) {
            ForEach(Mode.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.secondaryText)
                .font(.system(size: 13))
            TextField("搜索日语词、假名或英文释义", text: $searchText)
                .font(.system(size: 14))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
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

    private var filterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Filter.allCases) { item in
                    Chip(text: item.title, isSelected: filter == item) {
                        filter = item
                    }
                }
            }
        }
    }

    // MARK: Lists

    private var filteredWords: [SavedWord] {
        var result = app.words
        if filter != .all {
            result = result.filter { filter.matches($0) }
        }
        let query = searchText.trimmingCharacters(in: .whitespaces)
        if !query.isEmpty {
            let normalized = Kana.hiraganized(query).lowercased()
            result = result.filter { word in
                word.word.contains(query)
                    || Kana.hiraganized(word.word).lowercased().contains(normalized)
                    || word.reading.contains(query)
                    || word.meanings.joined(separator: " ").lowercased().contains(query.lowercased())
            }
        }
        return result.sorted { lhs, rhs in
            if lhs.scheduling.isDue() != rhs.scheduling.isDue() {
                return lhs.scheduling.isDue()
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    private var notebookList: some View {
        Group {
            if app.words.isEmpty {
                EmptyStateView(
                    symbol: "square.stack",
                    title: "生词本还是空的",
                    message: "在片段里点任意一个词，选择「保存到生词本」，它就会出现在这里。"
                )
                .card()
            } else if filteredWords.isEmpty {
                EmptyStateView(
                    symbol: "line.3.horizontal.decrease.circle",
                    title: "没有符合条件的词",
                    message: "换个筛选条件，或者清空搜索关键词。"
                )
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(filteredWords.enumerated()), id: \.element.id) { index, word in
                        NavigationLink {
                            WordDetailView(wordID: word.id)
                        } label: {
                            WordRow(word: word)
                        }
                        .buttonStyle(.plain)
                        if index < filteredWords.count - 1 {
                            Hairline().padding(.leading, 44)
                        }
                    }
                }
                .card(padded: false)
                .padding(2)
            }
        }
    }

    private var dictionaryList: some View {
        let results = app.dictionary.search(searchText, limit: 40)
        return VStack(alignment: .leading, spacing: 10) {
            if searchText.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("试试搜索「映画」「たべる」「友達」")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                    Text("共 \(app.dictionary.entries.count) 条词条，覆盖 JLPT N5–N1 与常用功能词。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .card()
            } else if results.isEmpty {
                EmptyStateView(
                    symbol: "questionmark.circle",
                    title: "没有找到词条",
                    message: "可以改用假名搜索，或在片段里点词让 AI 解释。"
                )
                .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, entry in
                        DictionaryRow(entry: entry, isSaved: app.isSaved(entryID: entry.id)) {
                            app.saveWord(entry: entry, surface: entry.word, sentence: nil, clip: nil)
                        }
                        if index < results.count - 1 {
                            Hairline().padding(.leading, 16)
                        }
                    }
                }
                .card(padded: false)
            }
        }
    }
}

// MARK: - Rows

struct WordRow: View {
    let word: SavedWord

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Theme.familiarityColor(word.familiarity).opacity(0.16))
                    .frame(width: 30, height: 30)
                Text("\(word.familiarity)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.familiarityColor(word.familiarity))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(word.word)
                        .font(.system(size: 17, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.ink)
                    LevelBadge(level: word.level)
                    if word.isIgnored {
                        TagLabel(text: "忽略", tint: Theme.secondaryText)
                    }
                }
                if !word.reading.isEmpty {
                    Text(word.reading)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                if !word.primaryMeaning.isEmpty {
                    Text(word.primaryMeaning)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 3) {
                FamiliarityBadge(level: word.familiarity, compact: true)
                Text(word.dueDescription)
                    .font(.system(size: 9))
                    .foregroundStyle(word.isDue ? Theme.rose : Theme.secondaryText)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

struct DictionaryRow: View {
    let entry: DictEntry
    let isSaved: Bool
    let onSave: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.word)
                        .font(.system(size: 16, weight: .medium, design: .serif))
                        .foregroundStyle(Theme.ink)
                    LevelBadge(level: entry.level)
                }
                Text("\(entry.reading)・\(entry.posLabel)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                Text(entry.meanings.prefix(2).joined(separator: "; "))
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                onSave()
            } label: {
                Image(systemName: isSaved ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSaved ? Theme.jade : Theme.accent)
            }
            .buttonStyle(.plain)
            .disabled(isSaved)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 14)
    }
}
