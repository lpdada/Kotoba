import SwiftUI

/// Detail page for a single kanji: readings, meaning, components, example words
/// and (optionally) joining the review queue.
struct KanjiDetailView: View {
    let literal: String

    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var noteDraft = ""
    @State private var didLoadNote = false

    private var entry: KanjiEntry? { app.kanjiEntry(literal) }
    private var card: KanjiCard? { app.kanjiCard(literal) }
    private var examples: [KanjiExampleWord] {
        guard let entry else { return [] }
        return app.exampleWords(for: entry)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let entry {
                        header(entry)
                        readings(entry)
                        meaning(entry)
                        examplesCard
                        reviewCard(entry)
                        if card != nil {
                            noteCard
                        }
                    } else {
                        EmptyStateView(
                            symbol: "character.book.closed",
                            title: "没有收录这个字",
                            message: "当前汉字表覆盖常用汉字与 JLPT N5–N1（2,387 字）。"
                        )
                    }
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("汉字")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear {
                guard !didLoadNote, let card else { return }
                noteDraft = card.note
                didLoadNote = true
            }
        }
    }

    // MARK: Header

    private func header(_ entry: KanjiEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(entry.literal)
                    .font(.system(size: 64, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
                VStack(alignment: .leading, spacing: 4) {
                    if !entry.pinyin.isEmpty {
                        Text(entry.pinyin)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(entry.meaningSummary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(2)
                }
                .padding(.top, 12)
                Spacer()
                Button {
                    app.speech.speak(entry.literal, rate: app.profile.speechRate)
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .background(Theme.accentSoft, in: Circle())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                TagLabel(text: entry.levelLabel, tint: Theme.accent)
                TagLabel(text: "\(entry.strokes) 画", tint: Theme.secondaryText)
                TagLabel(text: "部首 \(entry.radicalGlyph)", tint: Theme.lilac)
                TagLabel(text: entry.gradeLabel, tint: Theme.secondaryText)
                if let card {
                    FamiliarityBadge(level: card.familiarity, compact: true)
                }
            }
        }
        .card()
    }

    // MARK: Readings

    private func readings(_ entry: KanjiEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "读音", subtitle: "「.」前是词干，后面是送假名")
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text("音读")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 34, alignment: .leading)
                    if entry.onReadings.isEmpty {
                        Text("—").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    } else {
                        TokenFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(entry.onReadings, id: \.self) { reading in
                                TagLabel(text: reading, tint: Theme.accent)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                Hairline()
                HStack(alignment: .top, spacing: 8) {
                    Text("训读")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 34, alignment: .leading)
                    if entry.kunReadings.isEmpty {
                        Text("—").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                    } else {
                        TokenFlowLayout(spacing: 6, lineSpacing: 6) {
                            ForEach(entry.kunReadings, id: \.self) { reading in
                                TagLabel(text: reading, tint: Theme.jade)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Meaning

    private func meaning(_ entry: KanjiEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "意思", subtitle: entry.hasChineseGloss ? "中文释义 + 英文原义" : "英文原义（KANJIDIC2）")
            if entry.hasChineseGloss {
                Text(entry.chineseGloss)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Theme.ink)
            }
            VStack(alignment: .leading, spacing: 3) {
                ForEach(Array(entry.meanings.enumerated()), id: \.offset) { _, meaning in
                    Text("· \(meaning)")
                        .font(.system(size: 12))
                        .foregroundStyle(entry.hasChineseGloss ? Theme.secondaryText : Theme.ink)
                }
            }
            if !entry.hasChineseGloss {
                Text("这个字还没有人工核对的中文释义，以免给出错误对应，这里保留英文原义；需要的话可以加进复习后在笔记里写自己的中文。")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Examples

    private var examplesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "例词", subtitle: "从内置词典里挑出的常用词")
            if examples.isEmpty {
                Text("词典里没有包含这个字的常用词。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(examples.enumerated()), id: \.element.id) { index, example in
                        HStack(alignment: .top, spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(example.word)
                                        .font(.system(size: 16, design: .serif))
                                        .foregroundStyle(Theme.ink)
                                    if !example.reading.isEmpty, example.reading != example.word {
                                        Text(example.reading)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.secondaryText)
                                    }
                                    LevelBadge(level: example.level)
                                }
                                Text(example.meaning)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Button {
                                app.speech.speak(example.word, rate: app.profile.speechRate)
                            } label: {
                                Image(systemName: "speaker.wave.1")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.vertical, 8)
                        if index < examples.count - 1 {
                            Hairline()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: Review

    private func reviewCard(_ entry: KanjiEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "汉字复习", subtitle: "和生词共用同一套间隔算法")
            if let card {
                HStack(spacing: 8) {
                    ForEach(ReviewRating.allCases) { rating in
                        Button {
                            _ = app.applyKanjiRating(rating, literal: entry.literal)
                            app.toast = "\(rating.title)：\(SpacedRepetition.previewInterval(state: card.scheduling, rating: rating))"
                        } label: {
                            VStack(spacing: 3) {
                                Text(rating.title)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(SpacedRepetition.previewInterval(state: card.scheduling, rating: rating))
                                    .font(.system(size: 9))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                Theme.ratingColor(rating).opacity(0.12),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                            .foregroundStyle(Theme.ratingColor(rating))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("第 \(card.scheduling.reviewCount) 次 ・ \(card.dueText)")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                    Spacer()
                    Button("移出复习") {
                        app.removeKanjiCard(card)
                        app.toast = "已移出汉字复习"
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.rose)
                    .buttonStyle(.plain)
                }
            } else {
                PrimaryActionButton(title: "加入汉字复习", systemImage: "plus.circle.fill") {
                    app.saveKanjiCard(entry)
                }
                Text("加入后会像生词卡一样进入复习队列：正面是汉字，背面是读音、意思与例词。")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private var noteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "我的笔记", subtitle: "写自己的记忆法或中文对应")
            TextEditor(text: $noteDraft)
                .font(.system(size: 13))
                .frame(height: 80)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(Theme.cardMuted, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            HStack {
                Button("保存") {
                    guard var card else { return }
                    card.note = noteDraft
                    app.updateKanjiCard(card)
                    app.toast = "笔记已保存"
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                Spacer()
            }
        }
        .card()
    }
}

private extension KanjiCard {
    var dueText: String {
        if scheduling.isNew { return "新卡" }
        if scheduling.isDue() { return "待复习" }
        return SpacedRepetition.describe(seconds: scheduling.dueAt.timeIntervalSinceNow) + "后"
    }
}
