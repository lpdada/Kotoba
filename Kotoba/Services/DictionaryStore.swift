import Foundation

/// In-memory index over the bundled JLPT / JMdict dictionary.
final class DictionaryStore {
    private(set) var entries: [DictEntry] = []
    private var surfaceIndex: [String: [DictEntry]] = [:]
    private var kanaIndex: [String: [DictEntry]] = [:]
    private var kanaToEntry: [String: [DictEntry]] = [:]
    private(set) var maxSurfaceLength: Int = 1
    private(set) var status: String = "尚未载入"

    var isLoaded: Bool { !entries.isEmpty }

    init() {}

    // MARK: Loading

    func loadBundled() {
        guard let url = Bundle.main.url(forResource: "Dictionary", withExtension: "json") else {
            status = "缺少内置词典文件"
            return
        }
        load(url: url)
    }

    func load(url: URL) {
        do {
            let data = try Data(contentsOf: url)
            try load(data: data)
        } catch {
            status = "词典载入失败：\(error.localizedDescription)"
        }
    }

    func load(data: Data) throws {
        let file = try JSONDecoder().decode(DictionaryFile.self, from: data)
        install(file.entries)
        status = "已载入 \(entries.count) 条词条"
    }

    func install(_ newEntries: [DictEntry]) {
        entries = newEntries
        surfaceIndex.removeAll(keepingCapacity: true)
        kanaIndex.removeAll(keepingCapacity: true)
        kanaToEntry.removeAll(keepingCapacity: true)
        maxSurfaceLength = 1

        for entry in newEntries {
            surfaceIndex[entry.word, default: []].append(entry)
            let key = entry.kanaKey
            kanaToEntry[key, default: []].append(entry)
            if entry.reading != entry.word {
                kanaIndex[entry.reading, default: []].append(entry)
            }
            maxSurfaceLength = max(maxSurfaceLength, entry.word.count)
        }
        for key in surfaceIndex.keys {
            surfaceIndex[key]?.sort(by: Self.preference)
        }
        for key in kanaToEntry.keys {
            kanaToEntry[key]?.sort(by: Self.preference)
        }
    }

    /// Ordering used when several entries share a surface form.
    ///
    /// Frequency comes first, then grammatical words, because a bare kana like
    /// の is overwhelmingly the particle in running text, even though a noun
    /// reading of it also exists in the dictionary.
    private static func preference(_ lhs: DictEntry, _ rhs: DictEntry) -> Bool {
        if lhs.frequencyBand != rhs.frequencyBand { return lhs.frequencyBand < rhs.frequencyBand }
        if lhs.isFunctionWord != rhs.isFunctionWord { return lhs.isFunctionWord }
        if (lhs.level != nil) != (rhs.level != nil) { return lhs.level != nil }
        if lhs.meanings.count != rhs.meanings.count { return lhs.meanings.count < rhs.meanings.count }
        return lhs.word.count > rhs.word.count
    }

    // MARK: Lookup

    func exact(_ surface: String) -> [DictEntry] {
        if let hits = surfaceIndex[surface], !hits.isEmpty { return hits }
        let normalized = Kana.hiraganized(surface)
        if let hits = kanaToEntry[normalized], !hits.isEmpty { return hits }
        if let hits = kanaIndex[normalized], !hits.isEmpty { return hits }
        return []
    }

    func best(_ surface: String) -> DictEntry? {
        exact(surface).first
    }

    /// Exact match first, then reverse conjugation. Returns the matched entry and
    /// the grammatical description of the surface form.
    func resolve(surface: String) -> (entry: DictEntry?, formation: String?) {
        if let hit = best(surface) {
            return (hit, nil)
        }
        guard let resolved = resolveBest(surface: surface) else { return (nil, nil) }
        return (resolved.entry, resolved.formation)
    }

    /// Best dictionary form for an inflected surface.
    ///
    /// Several dictionary forms can legitimately exist (行って → 行く / 行う), so
    /// candidates are ranked by how common the resulting word is rather than by
    /// rule order.
    func resolveBest(surface: String) -> (entry: DictEntry, formation: String)? {
        var bestMatch: (entry: DictEntry, formation: String)?
        var visited = Set<String>()

        func consider(_ text: String, formation: String, depth: Int) {
            guard depth < 2, !visited.contains(text) else { return }
            visited.insert(text)
            for candidate in Deinflector.candidates(for: text) {
                if let entry = best(candidate.lemma) {
                    let label = formation.isEmpty
                        ? candidate.formation
                        : "\(candidate.formation)（原形 \(entry.word)）"
                    if let current = bestMatch {
                        if preference(entry, betterThan: current.entry) {
                            bestMatch = (entry, label)
                        }
                    } else {
                        bestMatch = (entry, label)
                    }
                } else if depth == 0 {
                    consider(candidate.lemma, formation: candidate.formation, depth: depth + 1)
                }
            }
        }

        consider(surface, formation: "", depth: 0)
        return bestMatch
    }

    private func preference(_ lhs: DictEntry, betterThan rhs: DictEntry) -> Bool {
        if lhs.frequencyBand != rhs.frequencyBand { return lhs.frequencyBand < rhs.frequencyBand }
        if lhs.isFunctionWord != rhs.isFunctionWord { return lhs.isFunctionWord }
        let leftRank = lhs.level?.rank ?? 99
        let rightRank = rhs.level?.rank ?? 99
        if leftRank != rightRank { return leftRank < rightRank }
        return lhs.word.count > rhs.word.count
    }

    func entry(withID id: String) -> DictEntry? {
        entries.first { $0.id == id }
    }

    /// Prefix / substring search used by the dictionary screen.
    func search(_ query: String, limit: Int = 60) -> [DictEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let normalized = Kana.hiraganized(trimmed)
        var scored: [(entry: DictEntry, score: Int)] = []
        for entry in entries {
            var score = 0
            if entry.word == trimmed || entry.kanaKey == normalized { score = 100 }
            else if entry.word.hasPrefix(trimmed) || entry.kanaKey.hasPrefix(normalized) { score = 80 }
            else if entry.reading.hasPrefix(trimmed) { score = 70 }
            else if entry.meanings.contains(where: { $0.lowercased().contains(trimmed.lowercased()) }) { score = 40 }
            else if entry.word.contains(trimmed) || entry.kanaKey.contains(normalized) { score = 20 }
            if score > 0 {
                scored.append((entry, score + (6 - entry.frequencyBand)))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            return lhs.entry.word.count < rhs.entry.word.count
        }
        return scored.prefix(limit).map(\.entry)
    }

    func entries(forLevel level: JLPTLevel) -> [DictEntry] {
        entries.filter { $0.level == level }
    }

    // MARK: Statistics

    var levelCounts: [JLPTLevel: Int] {
        var counts: [JLPTLevel: Int] = [:]
        for entry in entries {
            guard let level = entry.level else { continue }
            counts[level, default: 0] += 1
        }
        return counts
    }
}
