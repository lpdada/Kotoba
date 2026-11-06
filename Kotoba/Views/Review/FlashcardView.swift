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
                    .font(Theme.font(size: 14))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.18), value: isFlipped)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(spokenContent))
        .accessibilityHint(Text(isFlipped ? "双击回到正面" : "双击翻面看答案"))
        .accessibilityAddTraits(.isButton)
    }

    /// Everything VoiceOver should read for the current side of the card.
    private var spokenContent: String {
        if let word {
            if isFlipped {
                let meanings = word.meanings.joined(separator: "；")
                return "\(word.word)，读音 \(word.reading)，意思 \(meanings)，熟悉度 \(word.familiarity)"
            }
            return "生词卡，正面：\(word.word)"
        }
        if let kanjiLiteral {
            let entry = app.kanjiEntry(kanjiLiteral)
            if isFlipped, let entry {
                let readings = entry.onReadings.isEmpty ? "" : "音读 \(entry.onReadings.joined(separator: "、"))，"
                let kun = entry.kunReadings.isEmpty ? "" : "训读 \(entry.kunReadings.prefix(2).joined(separator: "、"))，"
                let meaning = entry.hasChineseGloss ? entry.chineseGloss : entry.meanings.joined(separator: "、")
                return "汉字 \(kanjiLiteral)，\(readings)\(kun)意思 \(meaning)"
            }
            return "汉字卡，正面：\(kanjiLiteral)"
        }
        if let sentence {
            return isFlipped
                ? "整句卡，\(sentence.text)，翻译 \(sentence.translation)"
                : "整句卡，正面：\(sentence.text)"
        }
        return "卡片不可用"
    }

    // MARK: Word

    @ViewBuilder
    private func wordFace(_ word: SavedWord) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(word.word)
                    .scaledFont(40, relativeTo: .title, weight: .semibold, design: .serif)
                    .foregroundStyle(Theme.ink)
                    .minimumScaleFactor(0.6)
                    .lineLimit(2)
                if isFlipped, !word.reading.isEmpty {
                    Text(word.reading)
                        .font(Theme.font(size: 15))
                        .foregroundStyle(Theme.secondaryText)
                }
                if isFlipped, !word.romaji.isEmpty {
                    Text(word.romaji)
                        .font(Theme.font(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.accent.opacity(0.8))
                }
            }
            Spacer()
            Button {
                onSpeak(word.word)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.font(size: 14, weight: .semibold))
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
                            .font(Theme.font(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                            .frame(width: 14)
                        Text(meaning)
                            .font(Theme.font(size: 14))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if word.meanings.isEmpty {
                    Text("没有词典释义，回忆一下它在原句里的用法。")
                        .font(Theme.font(size: 13))
                        .foregroundStyle(Theme.secondaryText)
                }
            }

            if let source = word.sourceSentence, !source.isEmpty {
                Text(source)
                    .font(Theme.font(size: 13, design: .serif))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }

            if !word.note.isEmpty {
                Text("笔记：\(word.note)")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.lilac)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 6) {
                LevelBadge(level: word.level)
                FamiliarityBadge(level: word.familiarity, compact: true)
                Spacer()
                Text("第 \(word.scheduling.reviewCount) 次")
                    .font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        } else {
            Spacer(minLength: 0)
            Text("想一想读音和意思，再点卡片翻面")
                .font(Theme.font(size: 11))
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
                    .scaledFont(56, relativeTo: .title, weight: .medium, design: .serif)
                    .foregroundStyle(Theme.ink)
                Text("汉字卡")
                    .font(Theme.font(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            Spacer()
            Button {
                onSpeak(literal)
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(Theme.font(size: 14, weight: .semibold))
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
                        .font(Theme.font(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.accent)
                }
                if !entry.onReadings.isEmpty {
                    Text("音：\(entry.onReadings.joined(separator: "、"))")
                        .font(Theme.font(size: 13, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
                if !entry.kunReadings.isEmpty {
                    Text("训：\(entry.kunReadings.prefix(3).joined(separator: "、"))")
                        .font(Theme.font(size: 13, design: .serif))
                        .foregroundStyle(Theme.ink)
                }
                Text(entry.hasChineseGloss ? entry.chineseGloss : entry.meanings.joined(separator: " / "))
                    .font(Theme.font(size: 14))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if !examples.isEmpty {
                    Text(examples.map { "\($0.word)（\($0.reading)）\($0.meaning)" }.joined(separator: " ・ "))
                        .font(Theme.font(size: 11))
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
                        .font(Theme.font(size: 10))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
        } else {
            Spacer(minLength: 0)
            Text("想一想读音和意思，再点卡片翻面")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
    }

    // MARK: Sentence

    @ViewBuilder
    private func sentenceFace(_ card: SentenceCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TagLabel(text: "整句", tint: Theme.lilac)
            Text(card.text)
                .font(Theme.font(size: 22, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }

        if isFlipped {
            Hairline()
            Text(card.translation)
                .font(Theme.font(size: 14))
                .foregroundStyle(Theme.ink.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
            if !card.note.isEmpty {
                Text("笔记：\(card.note)")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.lilac)
            }
        }

        Spacer(minLength: 0)
        HStack {
            Button {
                onSpeak(card.text)
            } label: {
                Label("朗读", systemImage: "speaker.wave.2")
                    .font(Theme.font(size: 12))
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
