import SwiftUI

struct WordLookupSheet: View {
    let token: ClipToken
    let sentence: String
    let clip: Clip?

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var entry: DictEntry?
    @State private var savedWord: SavedWord?
    @State private var explanation: WordExplanation?
    @State private var isExplaining = false
    @State private var noteDraft = ""
    @State private var showNoteEditor = false
    @State private var selectedKanji: KanjiSelection?

    private var surface: String { token.text }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    kanjiStrip
                    meaningsSection
                    explanationSection
                    examplesSection
                    corpusSection
                    sourceSection
                    actionSection
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("查词")
                        .font(.system(size: 14, weight: .semibold))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await load() }
        .sheet(item: $selectedKanji) { selection in
            KanjiDetailView(literal: selection.literal)
                .environmentObject(app)
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry?.word ?? surface)
                        .font(.system(size: 30, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        if let reading = entry?.reading, !reading.isEmpty {
                            Text(reading)
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        let romaji = entry?.romaji ?? token.romaji
                        if let romaji, !romaji.isEmpty {
                            Text(romaji)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.accent.opacity(0.8))
                        }
                    }
                }
                Spacer()
                Button {
                    app.speech.speak(entry?.word ?? surface, rate: app.profile.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 42, height: 42)
                        .background(Theme.accentSoft, in: Circle())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                LevelBadge(level: entry?.level)
                if let pos = entry?.posLabel, !pos.isEmpty {
                    TagLabel(text: pos)
                }
                if let formation = token.formation {
                    TagLabel(text: formation, tint: Theme.lilac)
                }
                if let savedWord {
                    FamiliarityBadge(level: savedWord.familiarity)
                }
            }
        }
        .card()
    }

    // MARK: Kanji

    private var kanjiStrip: some View {
        let characters = app.kanji.entries(in: entry?.word ?? surface)
        return Group {
            if !characters.isEmpty {
                HStack(spacing: 6) {
                    Text("汉字")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                    ForEach(characters) { kanjiEntry in
                        Button {
                            selectedKanji = KanjiSelection(literal: kanjiEntry.literal)
                        } label: {
                            Text(kanjiEntry.literal)
                                .font(.system(size: 15, design: .serif))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .foregroundStyle(Theme.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: Meanings

    private var meaningsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "释义", subtitle: entry == nil ? "内置词典未收录，可用 AI 解释补充" : "英英释义来自 JMdict")
            if let entry, !entry.meanings.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.meanings.enumerated()), id: \.offset) { index, meaning in
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(index + 1)")
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                                .frame(width: 16)
                            Text(meaning)
                                .font(.system(size: 14))
                                .foregroundStyle(Theme.ink)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .card()
            } else {
                Text("没有匹配到词条。它可能是专有名词、口语缩略，或者需要按更长的词组来理解。")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                    .card()
            }
        }
    }

    // MARK: Explanation

    private var explanationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionHeader(title: "这句里的意思", subtitle: nil)
                if let explanation {
                    TagLabel(text: explanation.source, tint: explanation.isRemote ? Theme.jade : Theme.secondaryText)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if isExplaining {
                    HStack(spacing: 8) {
                        ProgressView().tint(Theme.accent)
                        Text("正在分析这句话…")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                } else if let explanation {
                    Text(explanation.headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    if !explanation.grammar.isEmpty {
                        Text(explanation.grammar)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.ink.opacity(0.85))
                    }
                    if !explanation.nuance.isEmpty {
                        Text(explanation.nuance)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Button {
                        Task { await regenerate() }
                    } label: {
                        Text(app.profile.aiEnabled ? "重新用 AI 解释" : "换一段本地分析")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        Task { await generate() }
                    } label: {
                        Text("生成解释")
                            .font(.system(size: 13, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .card()
        }
    }

    // MARK: Examples

    private var examplesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "例句", subtitle: "点句子可朗读")
            VStack(alignment: .leading, spacing: 14) {
                if let examples = entry?.examples, !examples.isEmpty {
                    ForEach(examples.prefix(3)) { example in
                        VStack(alignment: .leading, spacing: 4) {
                            FuriganaMarkupView(
                                markup: example.furigana.isEmpty ? example.japanese : example.furigana,
                                fontSize: 16
                            )
                            Text(example.english)
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            app.speech.speak(example.japanese, rate: app.profile.speechRate)
                        }
                    }
                } else {
                    Text("这个条目还没有例句，可以先用视频里的原句记忆。")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .card()
        }
    }

    // MARK: Corpus

    private var corpusSection: some View {
        let hits = app.library.clips(containing: token.lookupKey, tokenizer: app.tokenizer)
            .filter { $0.id != clip?.id }
        return Group {
            if !hits.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: "在其他片段里听到", subtitle: "\(hits.count) 条")
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(hits.prefix(4)) { hit in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(hit.title)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                Text(hit.transcript.replacingOccurrences(of: "\n", with: " / "))
                                    .font(.system(size: 11, design: .serif))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(2)
                            }
                        }
                    }
                    .card()
                }
            }
        }
    }

    // MARK: Source sentence

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "原句", subtitle: clip?.title)
            VStack(alignment: .leading, spacing: 8) {
                Text(sentence)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let translation = clip?.translation, !translation.isEmpty {
                    Text(translation)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    // MARK: Actions

    private var actionSection: some View {
        VStack(spacing: 10) {
            if let savedWord {
                HStack(spacing: 10) {
                    Button {
                        app.speech.speak(savedWord.word, rate: app.profile.speechRate)
                    } label: {
                        Label("朗读", systemImage: "speaker.wave.1")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)

                    Button {
                        app.markKnown(savedWord)
                        self.savedWord = app.savedWord(id: savedWord.id)
                    } label: {
                        Label("已掌握", systemImage: "checkmark.seal")
                            .font(.system(size: 13, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .foregroundStyle(Theme.jade)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    noteDraft = savedWord.note
                    showNoteEditor.toggle()
                } label: {
                    HStack {
                        Image(systemName: "square.and.pencil")
                        Text(savedWord.note.isEmpty ? "添加笔记" : "编辑笔记")
                        Spacer()
                    }
                    .font(.system(size: 13))
                    .padding(12)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .foregroundStyle(Theme.secondaryText)
                }
                .buttonStyle(.plain)

                if showNoteEditor {
                    VStack(alignment: .leading, spacing: 8) {
                        TextEditor(text: $noteDraft)
                            .font(.system(size: 13))
                            .frame(height: 80)
                            .padding(6)
                            .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        HStack {
                            Button("取消") { showNoteEditor = false }
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.secondaryText)
                            Spacer()
                            Button("保存笔记") {
                                var copy = savedWord
                                copy.note = noteDraft
                                app.updateWord(copy)
                                self.savedWord = copy
                                showNoteEditor = false
                            }
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }

                Button(role: .destructive) {
                    app.removeWord(savedWord)
                    self.savedWord = nil
                    app.toast = "已移出生词本"
                } label: {
                    Text("移出生词本")
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Theme.rose.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .foregroundStyle(Theme.rose)
                }
                .buttonStyle(.plain)
            } else {
                PrimaryActionButton(title: "保存到生词本", systemImage: "plus.circle.fill") {
                    savedWord = app.saveWord(
                        entry: entry,
                        surface: surface,
                        sentence: sentence,
                        clip: clip
                    )
                }
                Text("保存后会自动进入间隔复习队列，默认间隔为 1 分钟。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    // MARK: Data

    private func load() async {
        if entry == nil {
            let resolved = app.dictionary.resolve(surface: token.lookupKey)
            entry = resolved.entry ?? app.dictionary.best(surface)
        }
        if let entry, let existing = app.savedWord(forEntryID: entry.id) {
            savedWord = existing
        } else if let existing = app.savedWord(id: "surface:" + surface) {
            savedWord = existing
        }
        if let cached = app.cachedExplanation(word: surface, sentence: sentence) {
            explanation = cached
        } else {
            await generate()
        }
    }

    private func generate() async {
        guard explanation == nil, !isExplaining else { return }
        isExplaining = true
        let result = await app.explain(word: surface, sentence: sentence, entry: entry)
        explanation = result
        isExplaining = false
    }

    private func regenerate() async {
        isExplaining = true
        explanation = nil
        app.invalidateExplanation(word: surface, sentence: sentence)
        let result = await app.explain(word: surface, sentence: sentence, entry: entry)
        explanation = result
        isExplaining = false
    }
}
