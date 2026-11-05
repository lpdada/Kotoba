import Foundation

// Standalone harness that exercises the Foundation-only core (dictionary,
// tokenizer, deinflector, scheduler) outside of iOS. Not part of the app target.
//
//   swiftc -swift-version 5 -Onone Kotoba/Model/*.swift Tools/verify_core.swift \
//     Kotoba/Services/{Deinflector,DictionaryStore,Tokenizer}.swift \
//     -o /tmp/verify_core && /tmp/verify_core Kotoba/Resources/Dictionary.json

func section(_ title: String) {
    print("\n=== \(title) ===")
}

@main
struct VerifyCore {
    static func main() {
        let path = CommandLine.arguments.count > 1
            ? CommandLine.arguments[1]
            : "Kotoba/Resources/Dictionary.json"
        let store = DictionaryStore()
        store.load(url: URL(fileURLWithPath: path))

        section("dictionary")
        print("entries: \(store.entries.count), status: \(store.status), maxSurfaceLength: \(store.maxSurfaceLength)")
        let levelCounts = store.levelCounts
        for level in JLPTLevel.allCases.sorted() {
            print("  \(level.label): \(levelCounts[level] ?? 0)")
        }

        section("exact lookup")
        for word in ["映画", "食べる", "友達", "は", "を", "です"] {
            if let entry = store.best(word) {
                print("  \(word) -> \(entry.reading) [\(entry.level?.label ?? "—")] \(entry.posLabel) :: \(entry.meanings.prefix(2).joined(separator: "; "))")
            } else {
                print("  \(word) -> MISS")
            }
        }

        section("deinflection")
        for surface in ["食べました", "書いて", "高かった", "行って", "読まなかった", "起きられる", "静かだった"] {
            let resolved = store.resolve(surface: surface)
            print("  \(surface) -> \(resolved.entry?.word ?? "???") \(resolved.entry?.reading ?? "") \(resolved.formation ?? "")")
        }

        section("tokenizer")
        let tokenizer = Tokenizer(dictionary: store)
        let sentences = [
            "昨日友達と映画を見に行きました",
            "すみません、これ、ください。",
            "この店のラーメン、すごくおいしいよ。",
            "最近、時間が足りない気がする。",
            "カードで払えますか。",
            "会議は三時からです。",
            "まだです。今から作ります。",
            "天気がいいといいね。",
            "誰か来たのかな。",
            "スープが濃すぎない？",
            "無理しないでね。"
        ]
        for sentence in sentences {
            let tokens = tokenizer.tokenize(sentence)
            let rendered = tokens.map { token -> String in
                let reading = token.reading.map { "(\($0))" } ?? ""
                let mark = token.entryID == nil ? "?" : "="
                return token.text + reading + mark
            }.joined(separator: " | ")
            let rejoined = tokens.map(\.text).joined()
            print("  \(sentence)")
            print("    -> \(rendered)")
            print("    roundtrip: \(rejoined == sentence ? "ok" : "MISMATCH: \(rejoined)")")
        }

        section("clip analysis")
        let clip = Clip(
            id: "test",
            title: "test",
            series: "test",
            transcript: "すみません、これ、ください。\nはい、二百円です。",
            translation: "不好意思，请给我这个。\n好的，两百日元。",
            level: nil,
            topics: ["日常会话"],
            durationSeconds: 8,
            media: .generated
        )
        let analysis = tokenizer.analyze(clip)
        let unknownPercent = String(format: "%.0f", analysis.metrics.unknownRatio * 100)
        let rank = String(format: "%.2f", analysis.metrics.levelRank)
        print("  tokens: \(analysis.allTokens.count), level=\(analysis.metrics.level.label) rank=\(rank) unknown=\(unknownPercent)% unique=\(analysis.metrics.uniqueWordCount)")

        section("scheduler ladder")
        var state = SchedulingState()
        for step in 1...4 {
            let result = SpacedRepetition.review(state: state, familiarity: 1, rating: .good)
            state = result.state
            let minutes = Int(state.dueAt.timeIntervalSinceNow / 60)
            print("  good #\(step): interval=\(String(format: "%.3f", state.intervalDays))d due in \(minutes)min ease=\(String(format: "%.2f", state.easeFactor)) familiarity=\(result.familiarity)")
        }
        print("  preview(good): \(SpacedRepetition.previewInterval(state: state, rating: .good))")

        section("scheduler lapse & growth")
        var mature = SchedulingState()
        mature.intervalDays = 30
        mature.easeFactor = 2.5
        mature.reviewCount = 6
        for rating in ReviewRating.allCases {
            let result = SpacedRepetition.review(state: mature, familiarity: 4, rating: rating)
            let interval = String(format: "%.1f", result.state.intervalDays)
            let ease = String(format: "%.2f", result.state.easeFactor)
            print("  \(rating.rawValue): interval=\(interval)d ease=\(ease) due=\(SpacedRepetition.describe(seconds: result.state.dueAt.timeIntervalSinceNow))")
        }

        section("familiarity mapping")
        for interval in [0.0, 0.5, 2.0, 5.0, 10.0, 30.0] {
            let level = SpacedRepetition.familiarityLevel(forIntervalDays: interval)
            print("  \(interval)d -> \(SpacedRepetition.familiarityTitle(level))")
        }

        print("\nDONE")
    }
}
