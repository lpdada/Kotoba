import Foundation

/// Decoded shape of `Kotoba/Resources/Grammar.json` (OpenJLPT, CC BY-SA 4.0).
///
/// Data only — no UI or review integration yet. Chinese glosses stay absent by
/// policy: OpenJLPT ships English meanings, so `meaningZH` is nil and
/// `zhStatus` is `en-fallback` until a gloss is hand-checked.
struct GrammarExample: Codable, Hashable {
    let ja: String
    let furigana: String?
    let en: String
    /// Hand-checked Chinese; nil means the English is shown instead.
    let zh: String?

    init(ja: String, furigana: String? = nil, en: String, zh: String? = nil) {
        self.ja = ja
        self.furigana = furigana
        self.en = en
        self.zh = zh
    }

    var hasChinese: Bool {
        guard let zh else { return false }
        return !zh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case ja, furigana, en, zh
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ja = try container.decode(String.self, forKey: .ja)
        furigana = try container.decodeIfPresent(String.self, forKey: .furigana)
        en = try container.decodeIfPresent(String.self, forKey: .en) ?? ""
        zh = try container.decodeIfPresent(String.self, forKey: .zh)
    }
}

struct GrammarEntry: Codable, Hashable, Identifiable {
    let id: String
    let level: JLPTLevel?
    let pattern: String
    let romaji: String?
    let reading: String?
    let meaningEN: String
    let formation: String
    let notesEN: String?
    let tags: [String]
    let examples: [GrammarExample]
    let meaningZH: String?
    let notesZH: String?
    let zhStatus: String

    /// Chinese when it exists, English otherwise — never blank.
    var displayMeaning: String {
        if let meaningZH, !meaningZH.isEmpty { return meaningZH }
        return meaningEN
    }

    var displayNotes: String? {
        if let notesZH, !notesZH.isEmpty { return notesZH }
        return notesEN
    }

    /// True only when a hand-checked Chinese gloss has been added.
    var hasCheckedChinese: Bool {
        guard let meaningZH else { return false }
        return !meaningZH.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private enum CodingKeys: String, CodingKey {
        case id, level, pattern, romaji, reading, formation, tags, examples
        case meaningEN = "meaning_en"
        case notesEN = "notes_en"
        case meaningZH = "meaning_zh"
        case notesZH = "notes_zh"
        case zhStatus = "zh_status"
    }
}

/// File-level envelope plus grouping helpers.
struct GrammarFile: Codable {
    struct Source: Codable, Hashable {
        let name: String?
        let repo: String?
        let commit: String?
    }

    let version: Int?
    let license: String?
    let source: Source?
    let counts: [String: Int]?
    let total: Int?
    let entries: [GrammarEntry]

    /// Counts keyed by the printed level label ("N5" … "N1").
    func countsByLevel() -> [String: Int] {
        var result: [String: Int] = [:]
        for entry in entries {
            result[entry.level?.label ?? "UNKNOWN", default: 0] += 1
        }
        return result
    }

    func entries(for level: JLPTLevel) -> [GrammarEntry] {
        entries.filter { $0.level == level }
    }
}

// MARK: - Progress

/// Per-entry study status. Grammar has no SM-2 scheduling yet (that arrives with
/// the review queue), so this is a simple three-state marker.
enum GrammarStatus: String, Codable, CaseIterable, Identifiable {
    case unseen
    case learning
    case learned

    var id: String { rawValue }

    var title: String {
        switch self {
        case .unseen: return "未标记"
        case .learning: return "学习中"
        case .learned: return "已学会"
        }
    }

    /// Pick a status by tapping: 未标记 → 学习中 → 已学会 → 未标记.
    var next: GrammarStatus {
        switch self {
        case .unseen: return .learning
        case .learning: return .learned
        case .learned: return .unseen
        }
    }
}

/// Persisted in `AppSnapshot.grammarProgress`, the same way kanji cards are kept.
struct GrammarProgress: Codable, Hashable {
    var learning: Set<String> = []
    var learned: Set<String> = []

    func status(for id: String) -> GrammarStatus {
        if learned.contains(id) { return .learned }
        if learning.contains(id) { return .learning }
        return .unseen
    }

    mutating func set(_ status: GrammarStatus, for id: String) {
        // Keep the two sets mutually exclusive.
        learning.remove(id)
        learned.remove(id)
        switch status {
        case .unseen: break
        case .learning: learning.insert(id)
        case .learned: learned.insert(id)
        }
    }

    mutating func cycle(_ id: String) -> GrammarStatus {
        let next = status(for: id).next
        set(next, for: id)
        return next
    }

    var markedCount: Int { learning.count + learned.count }
}
