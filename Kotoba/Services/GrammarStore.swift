import Foundation

/// Loads the bundled OpenJLPT grammar set (CC BY-SA 4.0) for browsing.
///
/// Data only: no review integration yet. Chinese glosses stay absent by policy —
/// the source ships English meanings, so every entry keeps `zhStatus == "en-fallback"`.
final class GrammarStore {
    private(set) var entries: [GrammarEntry] = []
    private(set) var status: String = "尚未载入"
    private(set) var license: String = ""
    /// Per-entry study status; mirrored into the snapshot by `AppModel`.
    var progress = GrammarProgress()

    init() {}

    // MARK: Loading

    func loadBundled() {
        guard let url = Bundle.main.url(forResource: "Grammar", withExtension: "json") else {
            status = "缺少内置语法文件"
            return
        }
        load(url: url)
    }

    func load(url: URL) {
        do {
            try load(data: Data(contentsOf: url))
        } catch {
            status = "语法表载入失败：\(error.localizedDescription)"
        }
    }

    func load(data: Data) throws {
        let file = try JSONDecoder().decode(GrammarFile.self, from: data)
        entries = file.entries
        license = file.license ?? ""
        status = "已载入 \(entries.count) 条语法"
    }

    var isLoaded: Bool { !entries.isEmpty }

    // MARK: Progress

    /// Restores persisted marks, dropping ids that no longer exist in the bundled
    /// set (the dataset changed from 595 to 526 entries, and could change again).
    /// Unknown ids are only dropped once entries are loaded, so a load failure
    /// never wipes a user's marks.
    func install(progress newValue: GrammarProgress) {
        guard !entries.isEmpty else {
            progress = newValue
            return
        }
        let known = Set(entries.map(\.id))
        var pruned = newValue
        pruned.learning = newValue.learning.filter { known.contains($0) }
        pruned.learned = newValue.learned.filter { known.contains($0) }
        progress = pruned
    }

    func status(for entry: GrammarEntry) -> GrammarStatus {
        progress.status(for: entry.id)
    }

    func status(for id: String) -> GrammarStatus {
        progress.status(for: id)
    }

    /// Cycles 未标记 → 学习中 → 已学会 → 未标记.
    @discardableResult
    func toggleStatus(for entry: GrammarEntry) -> GrammarStatus {
        progress.cycle(entry.id)
    }

    func counts(for status: GrammarStatus) -> Int {
        switch status {
        case .unseen: return max(entries.count - progress.markedCount, 0)
        case .learning: return progress.learning.count
        case .learned: return progress.learned.count
        }
    }

    // MARK: Browsing

    /// Counts keyed by level label, in N5 → N1 order.
    var countsByLevel: [(level: JLPTLevel, count: Int)] {
        JLPTLevel.allCases.map { level in
            (level, entries.filter { $0.level == level }.count)
        }
    }

    func entries(for level: JLPTLevel?) -> [GrammarEntry] {
        guard let level else { return entries }
        return entries.filter { $0.level == level }
    }

    /// Matches pattern, romaji, formation, tags and the English meaning.
    func search(_ query: String, level: JLPTLevel? = nil) -> [GrammarEntry] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pool = entries(for: level)
        guard !trimmed.isEmpty else { return pool }
        let lowered = trimmed.lowercased()
        let folded = KanjiStore.fold(trimmed)

        return pool.filter { entry in
            entry.pattern.contains(trimmed)
                || (entry.romaji ?? "").lowercased().contains(folded)
                || entry.formation.contains(trimmed)
                || entry.meaningEN.lowercased().contains(lowered)
                || entry.tags.contains { $0.lowercased().contains(lowered) }
        }
    }

    /// Other entries sharing at least one tag, ranked by shared-tag count, then
    /// by level (easier first), then by pattern.
    func related(to entry: GrammarEntry, limit: Int = 8) -> [GrammarEntry] {
        let tags = Set(entry.tags)
        guard !tags.isEmpty else { return [] }
        let scored: [(entry: GrammarEntry, shared: Int)] = entries.compactMap { candidate in
            guard candidate.id != entry.id else { return nil }
            let shared = Set(candidate.tags).intersection(tags).count
            return shared > 0 ? (candidate, shared) : nil
        }
        return scored
            .sorted { left, right in
                if left.shared != right.shared { return left.shared > right.shared }
                let leftRank = left.entry.level?.rank ?? 9
                let rightRank = right.entry.level?.rank ?? 9
                if leftRank != rightRank { return leftRank < rightRank }
                return left.entry.pattern < right.entry.pattern
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// English is the only reliable language here, so the UI must label it.
    static func meaningLabel(for entry: GrammarEntry) -> String {
        entry.hasCheckedChinese ? "中文" : "英文原文"
    }
}
