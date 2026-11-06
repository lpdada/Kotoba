import Foundation

/// One bundled kanji record.
///
/// Data comes from KANJIDIC2 (EDRDG, CC BY-SA 4.0). KANJIDIC2 carries English
/// meanings only, so `chineseGloss` is a small hand-checked layer covering the
/// N5/N4 characters; everything else shows the licensed English glosses.
struct KanjiEntry: Identifiable, Codable, Hashable {
    let literal: String
    let strokes: Int
    let radicalNumber: Int
    let radicalGlyph: String
    let onReadings: [String]
    let kunReadings: [String]
    let pinyin: String
    let meanings: [String]
    let chineseGloss: String
    let grade: Int
    /// KANJIDIC2 numbering: 4 = easiest (N5) … 1 = hardest (N2/N1). 0 = untagged.
    let jlptLevel: Int
    let frequency: Int

    var id: String { literal }

    enum CodingKeys: String, CodingKey {
        case literal = "k"
        case strokes = "s"
        case radicalNumber = "r"
        case radicalGlyph = "rg"
        case onReadings = "on"
        case kunReadings = "kun"
        case pinyin = "py"
        case meanings = "m"
        case chineseGloss = "zh"
        case grade = "g"
        case jlptLevel = "j"
        case frequency = "f"
    }

    var hasChineseGloss: Bool { !chineseGloss.isEmpty }

    var levelLabel: String {
        switch jlptLevel {
        case 4: return "N5"
        case 3: return "N4"
        case 2: return "N3"
        case 1: return "N2/N1"
        default: return "—"
        }
    }

    /// 1 = N5 … 5 = N2/N1, 9 = untagged. Used for sorting and grouping.
    var levelSortKey: Int {
        switch jlptLevel {
        case 4: return 1
        case 3: return 2
        case 2: return 3
        case 1: return 4
        default: return 9
        }
    }

    var gradeLabel: String {
        switch grade {
        case 1...6: return "小学 \(grade) 年"
        case 8: return "常用"
        case 9, 10: return "人名用"
        default: return "—"
        }
    }

    /// "day / sun" for compact rows.
    var meaningSummary: String {
        if hasChineseGloss, let first = chineseGloss.components(separatedBy: "；").first {
            return first
        }
        return meanings.first ?? ""
    }
}

struct KanjiFile: Codable {
    let version: Int
    let license: String?
    let sources: [String]?
    let entries: [KanjiEntry]
}

/// A kanji that joined the review queue. Scheduling is the same value type the
/// vocabulary cards use, so there is no second scheduler.
struct KanjiCard: Identifiable, Codable, Hashable {
    let literal: String
    var familiarity: Int
    var scheduling: SchedulingState
    var note: String
    let createdAt: Date

    var id: String { literal }

    init(
        literal: String,
        familiarity: Int = 1,
        scheduling: SchedulingState = SchedulingState(),
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.literal = literal
        self.familiarity = familiarity
        self.scheduling = scheduling
        self.note = note
        self.createdAt = createdAt
    }

    var isDue: Bool { scheduling.isDue() }
}

/// One JLPT band of the bundled kanji.
struct KanjiLevelGroup: Identifiable, Hashable {
    let key: Int
    let label: String
    let count: Int
    var id: Int { key }
}

/// One radical bucket.
struct KanjiRadicalGroup: Identifiable, Hashable {
    let radical: String
    let count: Int
    var id: String { radical }
}

/// Kanji statistics per JLPT band, used by the progress screen.
struct KanjiLevelStat: Identifiable, Hashable {
    let key: Int
    let label: String
    let total: Int
    let saved: Int
    let learned: Int
    var id: Int { key }
}

/// One example word for a kanji, resolved from the app's own dictionary.
struct KanjiExampleWord: Identifiable, Hashable {
    let word: String
    let reading: String
    let meaning: String
    let level: JLPTLevel?

    var id: String { word + reading }
}
