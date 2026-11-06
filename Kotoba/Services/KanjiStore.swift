import Foundation

/// Loads the bundled KANJIDIC2 subset and resolves example words from the app's
/// own dictionary (no second word dataset).
final class KanjiStore {
    private(set) var entries: [KanjiEntry] = []
    private(set) var status: String = "尚未载入"

    private var byLiteral: [String: KanjiEntry] = [:]
    private var exampleCache: [String: [KanjiExampleWord]] = [:]

    init() {}

    // MARK: Loading

    func loadBundled() {
        guard let url = Bundle.main.url(forResource: "Kanji", withExtension: "json") else {
            status = "缺少内置汉字文件"
            return
        }
        load(url: url)
    }

    func load(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try load(data: data)
        } catch {
            status = "汉字表载入失败：\(error.localizedDescription)"
        }
    }

    func load(data: Data) throws {
        let file = try JSONDecoder().decode(KanjiFile.self, from: data)
        install(file.entries)
        status = "已载入 \(entries.count) 个汉字"
    }

    func install(_ newEntries: [KanjiEntry]) {
        entries = newEntries
        byLiteral = [:]
        exampleCache = [:]
        for entry in newEntries {
            byLiteral[entry.literal] = entry
        }
    }

    var isLoaded: Bool { !entries.isEmpty }

    // MARK: Lookup

    func entry(for literal: String) -> KanjiEntry? {
        byLiteral[literal]
    }

    func entry(for character: Character) -> KanjiEntry? {
        byLiteral[String(character)]
    }

    /// Kanji contained in a word, in text order, each appearing once.
    func entries(in text: String) -> [KanjiEntry] {
        var seen = Set<String>()
        var result: [KanjiEntry] = []
        for character in text where Kana.isKanji(character) {
            let literal = String(character)
            guard !seen.contains(literal), let entry = byLiteral[literal] else { continue }
            seen.insert(literal)
            result.append(entry)
        }
        return result
    }

    // MARK: Grouping and search

    func entries(levelSortKey: Int) -> [KanjiEntry] {
        entries
            .filter { $0.levelSortKey == levelSortKey }
            .sorted(by: Self.frequencyOrder)
    }

    func entries(radical: String) -> [KanjiEntry] {
        entries
            .filter { $0.radicalGlyph == radical }
            .sorted(by: Self.frequencyOrder)
    }

    /// Proper strict-weak ordering: untagged frequency sorts last, ties by literal.
    private static func frequencyOrder(_ lhs: KanjiEntry, _ rhs: KanjiEntry) -> Bool {
        let left = lhs.frequency > 0 ? lhs.frequency : Int.max
        let right = rhs.frequency > 0 ? rhs.frequency : Int.max
        if left != right { return left < right }
        return lhs.literal < rhs.literal
    }

    var levelGroups: [KanjiLevelGroup] {
        var counts: [Int: Int] = [:]
        for entry in entries { counts[entry.levelSortKey, default: 0] += 1 }
        let labels: [Int: String] = [1: "N5", 2: "N4", 3: "N3", 4: "N2/N1", 9: "未分级"]
        return counts.keys.sorted().map {
            KanjiLevelGroup(key: $0, label: labels[$0] ?? "其他", count: counts[$0] ?? 0)
        }
    }

    var radicalGroups: [KanjiRadicalGroup] {
        var counts: [String: Int] = [:]
        for entry in entries where !entry.radicalGlyph.isEmpty {
            counts[entry.radicalGlyph, default: 0] += 1
        }
        return counts
            .map { KanjiRadicalGroup(radical: $0.key, count: $0.value) }
            .sorted { $0.count > $1.count }
    }

    func search(_ query: String, limit: Int = 80) -> [KanjiEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let lowered = trimmed.lowercased()
        let kanaQuery = Kana.hiraganized(trimmed)
        var scored: [(entry: KanjiEntry, score: Int)] = []
        for entry in entries {
            var score = 0
            if entry.literal == trimmed { score = 200 }
            else if entry.pinyin.contains(lowered) { score = 120 }
            else if entry.onReadings.contains(where: { Kana.hiraganized($0).contains(kanaQuery) }) { score = 100 }
            else if entry.kunReadings.contains(where: { Kana.hiraganized($0).contains(kanaQuery) }) { score = 90 }
            else if entry.chineseGloss.contains(trimmed) { score = 80 }
            else if entry.meanings.contains(where: { $0.lowercased().contains(lowered) }) { score = 60 }
            if score > 0 { scored.append((entry, score)) }
        }
        scored.sort { $0.score == $1.score ? $0.entry.frequency < $1.entry.frequency : $0.score > $1.score }
        return scored.prefix(limit).map(\.entry)
    }

    // MARK: Example words

    /// Words from the bundled dictionary that contain this kanji.
    /// Ordered by level, then frequency, then brevity.
    func exampleWords(
        for entry: KanjiEntry,
        dictionary: DictionaryStore,
        limit: Int = 4
    ) -> [KanjiExampleWord] {
        if let cached = exampleCache[entry.literal] { return Array(cached.prefix(limit)) }

        var candidates: [KanjiExampleWord] = []
        for word in dictionary.entries where word.word.contains(entry.literal) {
            guard !word.meanings.isEmpty else { continue }
            candidates.append(
                KanjiExampleWord(
                    word: word.word,
                    reading: word.reading,
                    meaning: word.primaryMeaning,
                    level: word.level
                )
            )
        }
        candidates.sort { lhs, rhs in
            let leftLevel = lhs.level?.rank ?? 9
            let rightLevel = rhs.level?.rank ?? 9
            if leftLevel != rightLevel { return leftLevel < rightLevel }
            if lhs.word.count != rhs.word.count { return lhs.word.count < rhs.word.count }
            return lhs.word < rhs.word
        }
        // Prefer multi-character words; fall back to the single character itself.
        let multi = candidates.filter { $0.word.count > 1 }
        let picked = Array((multi.isEmpty ? candidates : multi).prefix(limit))
        exampleCache[entry.literal] = picked
        return picked
    }

    // MARK: Statistics

    var count: Int { entries.count }

    func count(levelSortKey: Int) -> Int {
        entries.reduce(0) { $0 + ($1.levelSortKey == levelSortKey ? 1 : 0) }
    }
}
