import Foundation

/// Splits Japanese subtitle text into tappable tokens.
///
/// This is a dictionary-driven segmenter, not a full morphological analyser.
/// It minimises a total *cost* over the sentence: every candidate token has a
/// cost that falls with length and frequency, single-character words that are
/// not grammatical words carry a penalty, and unknown characters cost more than
/// a dictionary hit. Minimising (rather than maximising) means the dynamic
/// program naturally prefers "one real word" over "five plausible letters".
///
/// Reverse conjugation (`Deinflector`) lets inflected surfaces such as
/// `食べました` resolve to `食べる`, and adjacent unknown characters are merged
/// afterwards so unknown compounds stay tappable as a single unit.
final class Tokenizer {
    private let dictionary: DictionaryStore
    private var cache: [String: [ClipToken]] = [:]

    // Cost constants, tuned against short conversational subtitles.
    private let maxLookahead = 10
    private let exactBase = 4.2
    private let exactLengthWeight = 1.15
    private let deinflectBase = 5.0
    private let deinflectLengthWeight = 0.95
    private let frequencyWeight = 0.35
    private let shortTokenPenalty = 4.0
    private let homographPenalty = 3.0
    private let unknownRunBase = 2.0
    private let unknownRunLengthWeight = 1.0
    private let unknownCharCost = 3.2

    init(dictionary: DictionaryStore) {
        self.dictionary = dictionary
    }

    // MARK: Tokenizing

    func tokenize(_ text: String) -> [ClipToken] {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return [] }
        if let cached = cache[line] { return cached }

        let characters = Array(line)
        let count = characters.count
        var cost = [Double](repeating: .greatestFiniteMagnitude, count: count + 1)
        var spanAt = [Int](repeating: 0, count: count + 1)
        var entryAt = [DictEntry?](repeating: nil, count: count + 1)
        var formationAt = [String?](repeating: nil, count: count + 1)
        var unknownAt = [Bool](repeating: false, count: count + 1)
        cost[0] = 0

        for index in 0..<count {
            guard cost[index] < .greatestFiniteMagnitude else { continue }

            if Kana.isPunctuation(characters[index]) {
                var end = index
                while end < count, Kana.isPunctuation(characters[end]) { end += 1 }
                let span = end - index
                if cost[index] < cost[end] {
                    cost[end] = cost[index]
                    spanAt[end] = span
                    entryAt[end] = nil
                    formationAt[end] = nil
                    unknownAt[end] = false
                }
                continue
            }

            let maxSpan = min(maxLookahead, count - index)
            if maxSpan >= 1 {
                for span in 1...maxSpan {
                    let surface = String(characters[index..<(index + span)])
                    if let match = evaluate(surface) {
                        let total = cost[index] + match.cost
                        if total < cost[index + span] {
                            cost[index + span] = total
                            spanAt[index + span] = span
                            entryAt[index + span] = match.entry
                            formationAt[index + span] = match.formation
                            unknownAt[index + span] = false
                        }
                    }
                }
            }

            // Unknown run: a single tappable unit made only of characters the
            // dictionary cannot match on its own. Because the run stops at the
            // first known character it can never swallow a real word, it just
            // keeps unanalysable compounds (すみません, ラーメン) whole.
            // Loanwords: a contiguous katakana run is one unit even when the
            // dictionary only knows a fragment of it (ラー + メン).
            var katakanaLength = 0
            while index + katakanaLength < count {
                let character = characters[index + katakanaLength]
                guard isKatakana(character) || character == "ー" else { break }
                katakanaLength += 1
            }
            if katakanaLength >= 2, dictionary.best(String(characters[index..<(index + katakanaLength)])) == nil {
                let runCost = unknownRunBase + 0.45 * Double(katakanaLength)
                if cost[index] + runCost < cost[index + katakanaLength] {
                    cost[index + katakanaLength] = cost[index] + runCost
                    spanAt[index + katakanaLength] = katakanaLength
                    entryAt[index + katakanaLength] = nil
                    formationAt[index + katakanaLength] = nil
                    unknownAt[index + katakanaLength] = true
                }
            }

            var runLength = 0
            while index + runLength < count {
                let character = characters[index + runLength]
                if Kana.isPunctuation(character) { break }
                if Kana.isDigit(character) || (character.isASCII && character.isLetter) { break }
                if dictionary.best(String(character)) != nil { break }
                runLength += 1
            }
            if runLength >= 2 {
                let runCost = unknownRunBase + unknownRunLengthWeight * Double(runLength)
                if cost[index] + runCost < cost[index + runLength] {
                    cost[index + runLength] = cost[index] + runCost
                    spanAt[index + runLength] = runLength
                    entryAt[index + runLength] = nil
                    formationAt[index + runLength] = nil
                    unknownAt[index + runLength] = true
                }
            }

            let single = cost[index] + unknownCharCost
            if single < cost[index + 1] {
                cost[index + 1] = single
                spanAt[index + 1] = 1
                entryAt[index + 1] = nil
                formationAt[index + 1] = nil
                unknownAt[index + 1] = true
            }
        }

        var tokens: [ClipToken] = []
        var cursor = count
        while cursor > 0 {
            let span = spanAt[cursor]
            guard span > 0, cursor - span >= 0 else { break }
            let start = cursor - span
            let surface = String(characters[start..<cursor])
            let entry = entryAt[cursor]
            tokens.append(
                ClipToken(
                    id: 0,
                    text: surface,
                    lemma: entry?.word,
                    reading: entry?.word == surface ? entry?.reading : nil,
                    romaji: entry?.word == surface ? romaji(for: surface, entry: entry) : nil,
                    entryID: entry?.id,
                    kind: kind(for: surface, entry: entry),
                    formation: formationAt[cursor],
                    characterRange: start..<cursor
                )
            )
            cursor = start
        }
        tokens.reverse()

        let merged = mergeUnknownRuns(tokens)
        let numbered = merged.enumerated().map { offset, token in
            ClipToken(
                id: offset,
                text: token.text,
                lemma: token.lemma,
                reading: token.reading,
                romaji: token.romaji,
                entryID: token.entryID,
                kind: token.kind,
                formation: token.formation,
                characterRange: token.characterRange
            )
        }
        cache[line] = numbered
        return numbered
    }

    private func mergeUnknownRuns(_ tokens: [ClipToken]) -> [ClipToken] {
        var result: [ClipToken] = []
        for token in tokens {
            if let last = result.last,
               last.kind == .unknown,
               token.kind == .unknown,
               let previousRange = result.indices.last {
                let mergedRange = last.characterRange.lowerBound..<token.characterRange.upperBound
                let merged = ClipToken(
                    id: result[previousRange].id,
                    text: last.text + token.text,
                    lemma: nil,
                    reading: nil,
                    romaji: nil,
                    entryID: nil,
                    kind: .unknown,
                    formation: nil,
                    characterRange: mergedRange
                )
                result[previousRange] = merged
            } else {
                result.append(token)
            }
        }
        return result
    }

    private func romaji(for surface: String, entry: DictEntry?) -> String? {
        if let entry {
            return entry.romaji.isEmpty ? Kana.romaji(entry.reading) : entry.romaji
        }
        guard surface.count <= 8, surface.allSatisfy({ Kana.isKana($0) }) else { return nil }
        return Kana.romaji(surface)
    }

    private func kind(for surface: String, entry: DictEntry?) -> TokenKind {
        if let entry { return entry.isParticle ? .particle : .word }
        if surface.allSatisfy({ Kana.isPunctuation($0) }) { return .punctuation }
        if surface.allSatisfy({ Kana.isDigit($0) }) { return .number }
        if surface.allSatisfy({ $0.isASCII && ($0.isLetter || $0 == "'" || $0 == "-") }) { return .latin }
        return .unknown
    }

    private struct Match {
        let cost: Double
        let entry: DictEntry?
        let formation: String?
    }

    private func evaluate(_ surface: String) -> Match? {
        let span = Double(surface.count)
        if let entry = dictionary.best(surface) {
            var value = exactBase - exactLengthWeight * span
            value -= frequencyWeight * Double(6 - min(entry.frequencyBand, 5))
            if surface.count == 1, let character = surface.first, Kana.isKana(character), !isGrammaticalWord(entry) {
                value += shortTokenPenalty
            }
            // A kana-only surface rarely means the kanji homograph (がい is not
            // 害, いと is not 糸) unless the dictionary headword itself is kana.
            if entry.hasKanji,
               !entry.isFunctionWord,
               surface.allSatisfy({ Kana.isKana($0) }) {
                value += homographPenalty
            }
            return Match(cost: value, entry: entry, formation: nil)
        }
        if surface.count == 1, let character = surface.first, Kana.isKanji(character),
           let stemEntry = verbStemEntry(for: surface) {
            // A bare verb stem (見, 行) is not a dictionary headword; resolve it to
            // 見る / 行く so it stays tappable instead of becoming "unknown".
            let value = exactBase - frequencyWeight * Double(6 - min(stemEntry.frequencyBand, 5))
            return Match(cost: value, entry: stemEntry, formation: "词干（原形 \(stemEntry.word)）")
        }
        guard surface.count >= 2 else { return nil }
        if let resolved = dictionary.resolveBest(surface: surface) {
            var value = deinflectBase - deinflectLengthWeight * span
            value -= frequencyWeight * 0.7 * Double(6 - min(resolved.entry.frequencyBand, 5))
            return Match(cost: value, entry: resolved.entry, formation: resolved.formation)
        }
        return nil
    }

    private func isKatakana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        return (0x30A1...0x30F6).contains(scalar.value)
    }

    /// Tries the common dictionary forms for a bare kanji stem (見 → 見る, 行 → 行く).
    private func verbStemEntry(for stem: String) -> DictEntry? {
        let endings = ["る", "い", "う", "く", "す", "つ", "ぬ", "ぶ", "む", "ぐ", "える", "いる"]
        for ending in endings {
            if let entry = dictionary.best(stem + ending) {
                return entry
            }
        }
        return nil
    }

    private func isGrammaticalWord(_ entry: DictEntry) -> Bool {
        entry.isFunctionWord || entry.partsOfSpeech.contains("pn") || entry.partsOfSpeech.contains("num")
    }

    // MARK: Clip level analysis

    func analyze(_ clip: Clip) -> ClipAnalysis {
        let lineTexts = clip.lines
        var lines: [[ClipToken]] = []
        var flattened: [ClipToken] = []
        var levelRanks: [Int] = []
        var lookupKeys = Set<String>()
        var unknownCount = 0
        var total = 0

        for (lineIndex, line) in lineTexts.enumerated() {
            let tokens = tokenize(line)
            lines.append(tokens)
            for token in tokens {
                let identifier = lineIndex * 1000 + token.id
                flattened.append(
                    ClipToken(
                        id: identifier,
                        text: token.text,
                        lemma: token.lemma,
                        reading: token.reading,
                        romaji: token.romaji,
                        entryID: token.entryID,
                        kind: token.kind,
                        formation: token.formation,
                        characterRange: token.characterRange
                    )
                )
                guard token.kind != .punctuation else { continue }
                total += 1
                lookupKeys.insert(token.lookupKey)
                if token.entryID == nil {
                    unknownCount += 1
                } else if let entry = token.entryID.flatMap({ dictionary.entry(withID: $0) }),
                          let level = entry.level {
                    levelRanks.append(level.rank)
                }
            }
        }

        let averageRank: Double
        if levelRanks.isEmpty {
            averageRank = clip.level.map { Double($0.rank) } ?? 1.0
        } else {
            averageRank = Double(levelRanks.reduce(0, +)) / Double(levelRanks.count)
        }
        let metrics = ClipMetrics(
            level: clip.level ?? JLPTLevel.nearest(rank: averageRank),
            levelRank: averageRank,
            tokenCount: total,
            unknownRatio: total > 0 ? Double(unknownCount) / Double(total) : 0,
            uniqueWordCount: lookupKeys.count
        )
        return ClipAnalysis(lines: lines, allTokens: flattened, metrics: metrics)
    }
}
