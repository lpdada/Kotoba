import Foundation

// MARK: - JLPT level

/// JLPT difficulty band. `rank` grows with difficulty: N5 = 1 ... N1 = 5.
enum JLPTLevel: String, Codable, CaseIterable, Identifiable, Comparable {
    case n5, n4, n3, n2, n1

    var id: String { rawValue }

    /// Display label such as "N3".
    var label: String { rawValue.uppercased() }

    var rank: Int {
        switch self {
        case .n5: return 1
        case .n4: return 2
        case .n3: return 3
        case .n2: return 4
        case .n1: return 5
        }
    }

    var title: String { "JLPT \(label)" }

    var summary: String {
        switch self {
        case .n5: return "入门：假名、基础寒暄与日常名词"
        case .n4: return "初级：日常会话、基础时态与常用动词"
        case .n3: return "中级：生活场景对话、较复杂的句尾变化"
        case .n2: return "中高级：新闻与影视对白的自然语速"
        case .n1: return "高级：抽象表达、书面语与方言口音"
        }
    }

    static func fromLabel(_ label: String?) -> JLPTLevel? {
        guard let label, !label.isEmpty else { return nil }
        return JLPTLevel(rawValue: label.lowercased())
    }

    /// Nearest level for a continuous difficulty estimate (1..5).
    static func nearest(rank: Double) -> JLPTLevel {
        let clamped = min(max(rank.rounded(), 1), 5)
        switch Int(clamped) {
        case 1: return .n5
        case 2: return .n4
        case 3: return .n3
        case 4: return .n2
        default: return .n1
        }
    }

    static func < (lhs: JLPTLevel, rhs: JLPTLevel) -> Bool { lhs.rank < rhs.rank }

    // Accepts "N5" or "n5" from bundled or imported JSON.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = JLPTLevel(rawValue: raw.lowercased()) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown JLPT level: \(raw)"
            )
        }
        self = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Dictionary entry

struct DictExample: Codable, Hashable, Identifiable {
    let japanese: String
    /// Furigana markup, e.g. `{会|あ}う`.
    let furigana: String
    let english: String

    var id: String { japanese + english }

    enum CodingKeys: String, CodingKey {
        case japanese = "ja", furigana = "fur", english = "en"
    }

    init(japanese: String, furigana: String = "", english: String) {
        self.japanese = japanese
        self.furigana = furigana.isEmpty ? Self.autoFurigana(japanese) : furigana
        self.english = english
    }

    private static func autoFurigana(_ text: String) -> String { text }
}

struct DictEntry: Codable, Hashable, Identifiable {
    let id: String
    let word: String
    let reading: String
    let romaji: String
    let level: JLPTLevel?
    let partsOfSpeech: [String]
    let meanings: [String]
    let examples: [DictExample]
    /// 1 = extremely common ... 5 = rare. Used by the tokenizer and the feed ranker.
    let frequencyBand: Int

    enum CodingKeys: String, CodingKey {
        case id, word = "w", reading = "r", romaji = "rm"
        case level = "lv", partsOfSpeech = "p", meanings = "m"
        case examples = "ex", frequencyBand = "fb"
    }

    init(
        id: String,
        word: String,
        reading: String,
        romaji: String,
        level: JLPTLevel?,
        partsOfSpeech: [String],
        meanings: [String],
        examples: [DictExample] = [],
        frequencyBand: Int = 3
    ) {
        self.id = id
        self.word = word
        self.reading = reading
        self.romaji = romaji
        self.level = level
        self.partsOfSpeech = partsOfSpeech
        self.meanings = meanings
        self.examples = examples
        self.frequencyBand = frequencyBand
    }

    /// Kana spelling normalised to hiragana, used for lookups of katakana loans.
    var kanaKey: String { Kana.hiraganized(reading.isEmpty ? word : reading) }

    var hasKanji: Bool { word.contains { Kana.isKanji($0) } }

    var primaryMeaning: String { meanings.first ?? "" }

    var posLabel: String { PartsOfSpeech.describe(partsOfSpeech) }

    var isParticle: Bool { partsOfSpeech.contains("prt") }

    var isFunctionWord: Bool {
        !Set(partsOfSpeech).isDisjoint(with: ["prt", "cop", "aux", "aux-v", "aux-adj", "conj"])
    }
}

struct DictionaryFile: Codable {
    let version: Int
    let generatedAt: String?
    let license: String?
    let sources: [String]?
    let entries: [DictEntry]
}

// MARK: - Word class descriptors

enum PartsOfSpeech {
    private static let names: [String: String] = [
        "n": "名词", "pn": "代名词", "adj-i": "い形容词", "adj-na": "な形容词",
        "adj-no": "の形容词", "adj-pn": "连体词", "v1": "一段动词", "v5u": "五段动词",
        "v5k": "五段动词", "v5g": "五段动词", "v5s": "五段动词", "v5t": "五段动词",
        "v5n": "五段动词", "v5b": "五段动词", "v5m": "五段动词", "v5r": "五段动词",
        "vs": "サ变动词", "vi": "自动词", "vt": "他动词", "vk": "カ变动词",
        "adv": "副词", "prt": "助词", "conj": "接续词", "int": "感叹词",
        "exp": "惯用表达", "aux": "助动词", "aux-v": "助动词", "aux-adj": "补助形容词",
        "cop": "系词", "num": "数词", "ctr": "量词", "pref": "前缀", "suf": "后缀"
    ]

    static func describe(_ tags: [String]) -> String {
        let mapped = tags.compactMap { names[$0] }
        let unique = Array(NSOrderedSet(array: mapped)) as? [String] ?? mapped
        return unique.prefix(3).joined(separator: "・")
    }

    static func isVerb(_ tags: [String]) -> Bool {
        tags.contains { $0.hasPrefix("v") && $0 != "vi" && $0 != "vt" }
    }
}

// MARK: - Kana helpers

enum Kana {
    private static let katakanaStart: UInt32 = 0x30A1
    private static let katakanaEnd: UInt32 = 0x30F6
    private static let hiraganaOffset: UInt32 = 0x60

    static func hiraganized(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let value = scalar.value
            if value >= katakanaStart && value <= katakanaEnd,
               let converted = UnicodeScalar(value - hiraganaOffset) {
                scalars.append(converted)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }

    static func isKanji(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value)
            || (0x3400...0x4DBF).contains(value)
            || value == 0x3005 // 々
    }

    static func isKana(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x3041...0x309F).contains(value) || (0x30A0...0x30FF).contains(value)
    }

    static func isPunctuation(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        if (0x3000...0x303F).contains(value) || (0xFF01...0xFF0F).contains(value) { return true }
        return "、。，．！？…「」『』（）()!?.,;:—-~〜・　 ".contains(character)
    }

    static func isDigit(_ character: Character) -> Bool {
        if character.isNumber { return true }
        guard let scalar = character.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0xFF10...0xFF19).contains(value)
    }

    /// Romaji fallback for kana-only strings (used when the dictionary has no romaji).
    static func romaji(_ kana: String) -> String {
        let table: [String: String] = [
            "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
            "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
            "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
            "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
            "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
            "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
            "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
            "や": "ya", "ゆ": "yu", "よ": "yo",
            "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
            "わ": "wa", "を": "o", "ん": "n", "が": "ga", "ぎ": "gi", "ぐ": "gu",
            "げ": "ge", "ご": "go", "ざ": "za", "じ": "ji", "ず": "zu", "ぜ": "ze",
            "ぞ": "zo", "だ": "da", "ぢ": "ji", "づ": "zu", "で": "de", "ど": "do",
            "ば": "ba", "び": "bi", "ぶ": "bu", "べ": "be", "ぼ": "bo",
            "ぱ": "pa", "ぴ": "pi", "ぷ": "pu", "ぺ": "pe", "ぽ": "po",
            "ぁ": "a", "ぃ": "i", "ぅ": "u", "ぇ": "e", "ぉ": "o",
            "ゃ": "ya", "ゅ": "yu", "ょ": "yo", "っ": "", "ー": "-"
        ]
        var result = ""
        for character in hiraganized(kana) {
            result += table[String(character)] ?? String(character)
        }
        return result
    }
}

// MARK: - Shared helpers

extension Array {
    /// Bounds-checked access used by tokenizers, subtitle import and the UI.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
