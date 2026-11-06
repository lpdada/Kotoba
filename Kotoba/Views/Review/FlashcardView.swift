import SwiftUI

/// One side of a flashcard. Flips between prompt and answer.
struct FlashcardFace: View {
    let word: SavedWord?
    let sentence: SentenceCard?
    var kanjiLiteral: String? = nil
    let isFlipped: Bool
    var furiganaEnabled: Bool = true
    var speechRate: Double = 0.45
    var onSpeak: (String) -> Void

    @EnvironmentObject private var app: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let word {
                wordFace(word)
            } else if let kanjiLiteral {
                kanjiFace(kanjiLiteral)
            } else if let sentence {
                sentenceFace(sentence)
            } else {
                Text("卡片已失效")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: isFlipped)
    }

    // MARK: Word

    @ViewBuilder
    private func wordFace(_ word: SavedWord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.word)
                    .font(.system(size: 40, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if isFlipped, !word.reading.isEmpty {
                    Text(word.reading)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                if isFlipped, !word.romaji.isEmpty {
                    Text(word.romaji)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
            }
            Spacer()
            Button {
                onSpeak(word.word)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft, in: Circle())
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }

        if isFlipped {
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(word.meanings.prefix(4).enumerated()), id: \.offset) { index, meaning in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 14)
                        Text(meaning)
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if word.meanings.isEmpty {
                    Text("没有词典释义，回忆一下它在原句里的用法。")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let source = word.sourceSentence, !source.isEmpty {
                Text(source)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if !word.note.isEmpty {
                Text("笔记：\(word.note)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.lilac)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                LevelBadge(level: word.level)
                FamiliarityBadge(level: word.familiarity, compact: true)
                Spacer()
                Text("第 \(word.scheduling.reviewCount) 次")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            Spacer(minLength: 0)
            Text("想一想读音和意思，再点卡片翻面")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Kanji

    @ViewBuilder
    private func kanjiFace(_ literal: String) -> some View {
        let entry = app.kanjiEntry(literal)
        let card = app.kanjiCard(literal)
        let examples = entry.map { app.exampleWords(for: $0, limit: 3) } ?? []

        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(literal)
                    .font(.system(size: 56, weight: .medium, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text("汉字卡")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                onSpeak(literal)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .background(Theme.accentSoft, in: Circle())
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }

        if isFlipped, let entry {
            Hairline()
            VStack(alignment: .leading, spacing: 6) {
                if !entry.pinyin.isEmpty {
                    Text(entry.pinyin)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                if !entry.onReadings.isEmpty {
                    Text("音：\(entry.onReadings.joined(separator: "、"))")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
                if !entry.kunReadings.isEmpty {
                    Text("训：\(entry.kunReadings.prefix(3).joined(separator: "、"))")
                        .font(.system(size: 13, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
                Text(entry.hasChineseGloss ? entry.chineseGloss : entry.meanings.joined(separator: " / "))
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !examples.isEmpty {
                    Text(examples.map { "\($0.word)（\($0.reading)）\($0.meaning)" }.joined(separator: " ・ "))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                TagLabel(text: entry.levelLabel, tint: Theme.accent)
                TagLabel(text: "\(entry.strokes) 画", tint: Theme.secondaryText)
                Spacer()
                if let card {
                    Text("第 \(card.scheduling.reviewCount) 次")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        } else {
            Spacer(minLength: 0)
            Text("想一想读音和意思，再点卡片翻面")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Sentence

    @ViewBuilder
    private func sentenceFace(_ card: SentenceCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TagLabel(text: "整句", tint: Theme.lilac)
            Text(card.text)
                .font(.system(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }

        if isFlipped {
            Hairline()
            Text(card.translation)
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if !card.note.isEmpty {
                Text("笔记：\(card.note)")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.lilac)
            }
        }

        Spacer(minLength: 0)
        HStack {
            Button {
                onSpeak(card.text)
            } label: {
                Label("朗读", systemImage: "speaker.wave.2")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
            Spacer()
            if isFlipped {
                FamiliarityBadge(level: card.familiarity, compact: true)
            }
        }
    }
}
