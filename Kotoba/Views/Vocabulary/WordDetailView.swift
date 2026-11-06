import SwiftUI

struct WordDetailView: View {
    let wordID: String

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var noteDraft = ""
    @State private var didLoadNote = false
    @State private var showDecks = false
    @State private var selectedKanji: KanjiSelection?

    private var word: SavedWord? { app.word(id: wordID) }
    private var entry: DictEntry? {
        guard let word else { return nil }
        return app.dictionary.entry(withID: word.id) ?? app.dictionary.best(word.word)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let word {
                    header(word)
                    scheduleCard(word)
                    meaningsCard(word)
                    kanjiCardSection(word)
                    noteCard(word)
                    if let sentence = word.sourceSentence, !sentence.isEmpty {
                        sourceCard(sentence)
                    }
                    if let examples = entry?.examples, !examples.isEmpty {
                        examplesCard(examples)
                    }
                    quickReviewCard(word)
                    dangerZone(word)
                } else {
                    EmptyStateView(
                        symbol: "questionmark.circle",
                        title: "找不到这个词",
                        message: "它可能已经被删除。"
                    )
                }
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("词条")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let word, !didLoadNote {
                noteDraft = word.note
                didLoadNote = true
            }
        }
        .sheet(item: $selectedKanji) { selection in
            KanjiDetailView(literal: selection.literal)
                .environmentObject(app)
        }
        .sheet(isPresented: $showDecks) {
            if let word {
                DeckPickerSheet(word: word)
                    .environmentObject(app)
            }
        }
    }

    // MARK: Cards

    private func header(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(word.word)
                        .scaledFont(32, relativeTo: .title, weight: .semibold, design: .serif)
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        if !word.reading.isEmpty {
                            Text(word.reading)
                                .font(Theme.font(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        if !word.romaji.isEmpty {
                            Text(word.romaji)
                                .font(Theme.font(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.accent.opacity(0.8))
                        }
                    }
                }
                Spacer()
                Button {
                    app.speech.speak(word.word, rate: app.profile.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(Theme.font(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Theme.accentSoft, in: Circle())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
                .a11yButton("朗读 \(word.word)")
            }
            HStack(spacing: 6) {
                LevelBadge(level: word.level)
                FamiliarityBadge(level: word.familiarity)
                if word.isIgnored {
                    TagLabel(text: "已忽略", tint: Theme.secondaryText)
                }
                ForEach(word.deckIDs, id: \.self) { deckID in
                    if let deck = app.deck(for: deckID) {
                        TagLabel(text: deck.name, tint: Theme.lilac)
                    }
                }
            }
        }
        .card()
    }

    private func scheduleCard(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "记忆状态", subtitle: "按你自己的评分推算")
            HStack(spacing: 8) {
                StatTile(
                    title: "当前间隔",
                    value: intervalText(word.scheduling.intervalDays),
                    caption: word.scheduling.isNew ? "还没开始复习" : "下次 \(word.scheduling.dueAt.formatted(date: .abbreviated, time: .shortened))",
                    tint: Theme.accent
                )
                StatTile(
                    title: "难度系数",
                    value: String(format: "%.2f", word.scheduling.easeFactor),
                    caption: "越低越难",
                    tint: Theme.lilac
                )
                StatTile(
                    title: "复习次数",
                    value: "\(word.scheduling.reviewCount)",
                    caption: "遗忘 \(word.scheduling.lapseCount) 次",
                    tint: Theme.jade
                )
            }
        }
    }

    private func meaningsCard(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "释义", subtitle: entry?.posLabel)
            if word.meanings.isEmpty {
                Text("没有词典释义，可以自己写一句中文笔记。")
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(word.meanings.enumerated()), id: \.offset) { index, meaning in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(Theme.font(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(meaning)
                                .font(Theme.font(size: 14))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func kanjiCardSection(_ word: SavedWord) -> some View {
        let characters = app.kanji.entries(in: word.word)
        return Group {
            if !characters.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "汉字", subtitle: "点开看读音、部首与例词")
                    HStack(spacing: 8) {
                        ForEach(characters) { kanjiEntry in
                            Button {
                                selectedKanji = KanjiSelection(literal: kanjiEntry.literal)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(kanjiEntry.literal)
                                        .font(Theme.font(size: 22, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                    Text(kanjiEntry.levelLabel)
                                        .font(Theme.font(size: 8))
                                        .foregroundStyle(Theme.secondaryText)
                                }
                                .frame(width: 52, height: 52)
                                .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
            }
        }
    }

    private func noteCard(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "我的笔记", subtitle: "写中文、写例句都行")
            TextEditor(text: $noteDraft)
                .font(Theme.font(size: 13))
                .frame(height: 90)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Button("保存") {
                    var copy = word
                    copy.note = noteDraft
                    app.updateWord(copy)
                    app.toast = "笔记已保存"
                }
                .font(Theme.font(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                Spacer()
                Button("加入分组") { showDecks = true }
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private func sourceCard(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "来源片段", subtitle: nil)
            Text(sentence)
                .font(Theme.font(size: 15, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let clipID = word?.sourceClipID, let clip = app.library.clip(id: clipID) {
                Text("\(clip.displaySeries) ・ \(clip.title)")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func examplesCard(_ examples: [DictExample]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "词典例句", subtitle: "点句子可朗读")
            ForEach(examples.prefix(3)) { example in
                VStack(alignment: .leading, spacing: 3) {
                    FuriganaMarkupView(
                        markup: example.furigana.isEmpty ? example.japanese : example.furigana,
                        fontSize: 15
                    )
                    Text(example.english)
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    app.speech.speak(example.japanese, rate: app.profile.speechRate)
                }
            }
        }
        .card()
    }

    private func quickReviewCard(_ word: SavedWord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "单独练一次", subtitle: "等于闪卡里的一次评分")
            HStack(spacing: 8) {
                ForEach(ReviewRating.allCases) { rating in
                    Button {
                        app.applyWordRating(rating, wordID: word.id)
                        app.toast = "\(rating.title)：\(SpacedRepetition.describe(seconds: (app.word(id: word.id)?.scheduling.dueAt ?? Date()).timeIntervalSinceNow))后"
                    } label: {
                        VStack(spacing: 3) {
                            Text(rating.title)
                                .font(Theme.font(size: 13, weight: .semibold))
                            Text(SpacedRepetition.previewInterval(state: word.scheduling, rating: rating))
                                .font(Theme.font(size: 9))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(Theme.ratingColor(rating).opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .foregroundStyle(Theme.ratingColor(rating))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("评分：\(rating.title)"))
                    .accessibilityHint(Text("\(rating.hint)，下次约 \(SpacedRepetition.previewInterval(state: word.scheduling, rating: rating))后"))
                }
            }
        }
        .card()
    }

    private func dangerZone(_ word: SavedWord) -> some View {
        VStack(spacing: 8) {
            SecondaryActionButton(
                title: word.isIgnored ? "恢复参与复习" : "暂时忽略这个词",
                systemImage: word.isIgnored ? "arrow.uturn.backward" : "eye.slash",
                tint: Theme.secondaryText
            ) {
                app.toggleIgnored(word)
            }
            SecondaryActionButton(title: "从生词本删除", systemImage: "trash", tint: Theme.rose) {
                app.removeWord(word)
                dismiss()
            }
        }
    }

    private func intervalText(_ days: Double) -> String {
        if days < 1 { return "学习阶段" }
        if days < 30 { return String(format: "%.0f 天", days) }
        if days < 365 { return String(format: "%.0f 个月", days / 30) }
        return String(format: "%.1f 年", days / 365)
    }
}

// MARK: - Deck picker

struct DeckPickerSheet: View {
    let word: SavedWord

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(app.decks) { deck in
                    Button {
                        var copy = word
                        if let index = copy.deckIDs.firstIndex(of: deck.id) {
                            copy.deckIDs.remove(at: index)
                        } else {
                            copy.deckIDs.append(deck.id)
                        }
                        if copy.deckIDs.isEmpty {
                            copy.deckIDs = [Deck.defaultDeckID]
                        }
                        app.updateWord(copy)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(deck.name)
                                    .foregroundStyle(Theme.ink)
                                Text("\(app.wordCount(inDeck: deck.id)) 个词")
                                    .font(Theme.font(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            if word.deckIDs.contains(deck.id) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                }
            }
            .navigationTitle("加入分组")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
