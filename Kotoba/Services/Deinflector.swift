import Foundation

/// A dictionary form candidate produced by stripping a conjugated ending.
struct Deinflection: Hashable {
    let lemma: String
    let formation: String
    let kind: WordKind

    enum WordKind: Hashable {
        case verb
        case adjective
        case other
    }
}

/// Reverse conjugation for Japanese verbs and adjectives.
///
/// The analyser does not try to be a full morphological engine: it generates
/// plausible dictionary forms for a surface string and lets the dictionary
/// confirm which ones actually exist. That keeps precision high without a
/// 30 MB verb table.
enum Deinflector {
    private enum Transform {
        /// Replace the ending with each literal candidate.
        case literal([String])
        /// Map the final kana of the remaining stem from its current row to the
        /// u-row (dictionary form). Extra literal candidates are appended too so
        /// ichidan verbs (`食べ` + `る`) are covered.
        case rowU(extra: [String])
        /// Map the final kana of the stem from one row to the u-row.
        case rowToU(row: KanaRow)
    }

    private enum KanaRow {
        case a, i, e, o
    }

    private struct Rule {
        let suffix: String
        let formation: String
        let kind: Deinflection.WordKind
        let transform: Transform
    }

    private static let rules: [Rule] = [
        // Polite forms
        Rule(suffix: "ませんでした", formation: "敬体・过去否定", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ません", formation: "敬体・否定", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ました", formation: "敬体・过去", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ましょう", formation: "敬体・意志", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ます", formation: "敬体", kind: .verb, transform: .rowU(extra: ["る"])),

        // Te / past forms (godan sound changes + ichidan)
        Rule(suffix: "って", formation: "て形", kind: .verb, transform: .literal(["う", "つ", "る", "く"])),
        Rule(suffix: "んで", formation: "て形", kind: .verb, transform: .literal(["ぬ", "ぶ", "む"])),
        Rule(suffix: "いて", formation: "て形", kind: .verb, transform: .literal(["く"])),
        Rule(suffix: "いで", formation: "て形", kind: .verb, transform: .literal(["ぐ"])),
        Rule(suffix: "して", formation: "て形", kind: .verb, transform: .literal(["す"])),
        Rule(suffix: "て", formation: "て形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "った", formation: "过去式", kind: .verb, transform: .literal(["う", "つ", "る", "く"])),
        Rule(suffix: "んだ", formation: "过去式", kind: .verb, transform: .literal(["ぬ", "ぶ", "む"])),
        Rule(suffix: "いた", formation: "过去式", kind: .verb, transform: .literal(["く"])),
        Rule(suffix: "いだ", formation: "过去式", kind: .verb, transform: .literal(["ぐ"])),
        Rule(suffix: "した", formation: "过去式", kind: .verb, transform: .literal(["す"])),
        Rule(suffix: "た", formation: "过去式", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "だ", formation: "过去式", kind: .verb, transform: .rowU(extra: ["る"])),

        // Progressive / contraction
        Rule(suffix: "ている", formation: "进行体", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ています", formation: "进行体（敬体）", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "てる", formation: "进行体", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "いてる", formation: "进行体", kind: .verb, transform: .literal(["く"])),
        Rule(suffix: "ってる", formation: "进行体", kind: .verb, transform: .literal(["う", "つ", "る"])),

        // Negation
        Rule(suffix: "なかった", formation: "过去否定", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "なくて", formation: "否定て形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ないで", formation: "否定て形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ずに", formation: "否定（ず）", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ない", formation: "否定形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ず", formation: "否定（ず）", kind: .verb, transform: .rowU(extra: ["る"])),

        // Ability / passive / causative
        Rule(suffix: "られる", formation: "可能・被动形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "れる", formation: "可能・被动形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "させる", formation: "使役形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "せる", formation: "使役形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "させられる", formation: "使役被动", kind: .verb, transform: .rowU(extra: ["る"])),

        // Desire / condition / volition
        Rule(suffix: "たかった", formation: "过去愿望", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "たい", formation: "愿望（たい）", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "たがる", formation: "愿望（たがる）", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "れば", formation: "假定形", kind: .verb, transform: .rowToU(row: .e)),
        Rule(suffix: "けば", formation: "假定形", kind: .verb, transform: .literal(["く"])),
        Rule(suffix: "せば", formation: "假定形", kind: .verb, transform: .literal(["す"])),
        Rule(suffix: "おう", formation: "意志形", kind: .verb, transform: .rowToU(row: .o)),
        Rule(suffix: "よう", formation: "意志形", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ながら", formation: "同时进行", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "たり", formation: "列举", kind: .verb, transform: .literal(["た"])),
        Rule(suffix: "そう", formation: "样态", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "すぎる", formation: "过度", kind: .verb, transform: .rowU(extra: ["る"])),

        // Progressive + request compounds (strip the tail, then the te-form table applies once more).
        Rule(suffix: "っています", formation: "进行体（敬体）", kind: .verb, transform: .literal(["う", "つ", "る"])),
        Rule(suffix: "んでいます", formation: "进行体（敬体）", kind: .verb, transform: .literal(["ぬ", "ぶ", "む"])),
        Rule(suffix: "いています", formation: "进行体（敬体）", kind: .verb, transform: .literal(["く"])),
        Rule(suffix: "いでいます", formation: "进行体（敬体）", kind: .verb, transform: .literal(["ぐ"])),
        Rule(suffix: "しています", formation: "进行体（敬体）", kind: .verb, transform: .literal(["す"])),
        Rule(suffix: "てください", formation: "请求（てください）", kind: .verb, transform: .rowU(extra: ["る"])),
        Rule(suffix: "ってください", formation: "请求（てください）", kind: .verb, transform: .literal(["う", "つ", "る"])),
        Rule(suffix: "んでください", formation: "请求（てください）", kind: .verb, transform: .literal(["ぬ", "ぶ", "む"])),
        Rule(suffix: "いてください", formation: "请求（てください）", kind: .verb, transform: .literal(["く"])),
        Rule(suffix: "いでください", formation: "请求（てください）", kind: .verb, transform: .literal(["ぐ"])),
        Rule(suffix: "してください", formation: "请求（てください）", kind: .verb, transform: .literal(["す"])),

        // な-adjective and copula forms
        Rule(suffix: "だった", formation: "な形容词・过去", kind: .adjective, transform: .literal(["", "だ"])),
        Rule(suffix: "じゃない", formation: "な形容词・否定", kind: .adjective, transform: .literal(["", "だ"])),
        Rule(suffix: "ではない", formation: "な形容词・否定", kind: .adjective, transform: .literal(["", "だ"])),
        Rule(suffix: "でしょう", formation: "推测", kind: .other, transform: .literal(["", "だ"])),
        Rule(suffix: "だろう", formation: "推测", kind: .other, transform: .literal(["", "だ"])),
        Rule(suffix: "なさい", formation: "命令", kind: .verb, transform: .rowU(extra: ["る"])),

        // Adjectives
        Rule(suffix: "くなかった", formation: "过去否定", kind: .adjective, transform: .literal(["い"])),
        Rule(suffix: "くない", formation: "否定形", kind: .adjective, transform: .literal(["い"])),
        Rule(suffix: "かった", formation: "过去式", kind: .adjective, transform: .literal(["い"])),
        Rule(suffix: "くて", formation: "て形", kind: .adjective, transform: .literal(["い"])),
        Rule(suffix: "ければ", formation: "假定形", kind: .adjective, transform: .literal(["い"])),
        Rule(suffix: "く", formation: "连用形（副词用法）", kind: .adjective, transform: .literal(["い"])),
        Rule(suffix: "さ", formation: "名词化", kind: .adjective, transform: .literal(["い"]))
    ]

    private static let rowA: [Character: Character] = [
        "あ": "う", "か": "く", "が": "ぐ", "さ": "す", "ざ": "ず", "た": "つ",
        "だ": "づ", "な": "ぬ", "は": "ふ", "ば": "ぶ", "ぱ": "ぷ", "ま": "む",
        "や": "う", "ら": "る", "わ": "う", "ぁ": "う"
    ]
    private static let rowI: [Character: Character] = [
        "い": "う", "き": "く", "ぎ": "ぐ", "し": "す", "じ": "ず", "ち": "つ",
        "に": "ぬ", "ひ": "ふ", "び": "ぶ", "ぴ": "ぷ", "み": "む", "り": "る"
    ]
    private static let rowE: [Character: Character] = [
        "え": "う", "け": "く", "げ": "ぐ", "せ": "す", "ぜ": "ず", "て": "つ",
        "で": "づ", "ね": "ぬ", "へ": "ふ", "べ": "ぶ", "ぺ": "ぷ", "め": "む",
        "れ": "る"
    ]
    private static let rowO: [Character: Character] = [
        "お": "う", "こ": "く", "ご": "ぐ", "そ": "す", "ぞ": "ず", "と": "つ",
        "ど": "づ", "の": "ぬ", "ほ": "ふ", "ぼ": "ぶ", "ぽ": "ぷ", "も": "む",
        "ろ": "る", "よ": "う"
    ]

    /// Dictionary form candidates for a surface string, most likely first.
    static func candidates(for surface: String) -> [Deinflection] {
        guard surface.count >= 2 else { return [] }
        var results: [Deinflection] = []
        var seen = Set<String>()

        func append(_ lemma: String, _ formation: String, _ kind: Deinflection.WordKind) {
            guard lemma.count >= 1, lemma != surface else { return }
            let key = lemma + "|" + formation
            guard !seen.contains(key) else { return }
            seen.insert(key)
            results.append(Deinflection(lemma: lemma, formation: formation, kind: kind))
        }

        for rule in rules where surface.hasSuffix(rule.suffix) {
            let stem = String(surface.dropLast(rule.suffix.count))
            guard !stem.isEmpty else { continue }
            switch rule.transform {
            case .literal(let ends):
                for end in ends { append(stem + end, rule.formation, rule.kind) }
            case .rowU(let extra):
                if let mapped = mapLast(stem, row: .a)
                    ?? mapLast(stem, row: .i)
                    ?? mapLast(stem, row: .e) {
                    append(mapped, rule.formation, rule.kind)
                }
                for end in extra { append(stem + end, rule.formation, rule.kind) }
            case .rowToU(let row):
                if let mapped = mapLast(stem, row: row) {
                    append(mapped, rule.formation, rule.kind)
                }
            }
        }

        // する/来る compounds are covered by the suffix table plus dictionary
        // verification, so no catch-all irregular rewrites are needed here: an
        // unbounded "ends with いい" rule would happily rewrite whole sentences.

        return results
    }

    private static func mapLast(_ stem: String, row: KanaRow) -> String? {
        guard let last = stem.last else { return nil }
        let table: [Character: Character]
        switch row {
        case .a: table = rowA
        case .i: table = rowI
        case .e: table = rowE
        case .o: table = rowO
        }
        guard let mapped = table[last] else { return nil }
        return String(stem.dropLast()) + String(mapped)
    }
}
