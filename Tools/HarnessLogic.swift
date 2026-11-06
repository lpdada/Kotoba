import Foundation

/// Behavioural checks for the app's decision layer, executed on Linux through
/// `Tools/verify_logic.sh` (platform services are replaced by `Tools/stubs`).
///
/// These are assertions about *behaviour*, not snapshots: deck budgets, the
/// scheduler ladder, rating effects, undo and daily activity.
@main
struct HarnessLogic {
    static func main() {
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  PASS  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            } else {
                failures += 1
                print("  FAIL  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            }
        }

        MainActor.assumeIsolated {
            let dictionaryPath = CommandLine.arguments.count > 1
                ? CommandLine.arguments[1]
                : "Kotoba/Resources/Dictionary.json"

            let app = AppModel()
            app.dictionary.load(url: URL(fileURLWithPath: dictionaryPath))

            print("\n== dictionary ==")
            check("entries loaded", app.dictionary.entries.count > 10_000, "\(app.dictionary.entries.count) entries")
            check("exact lookup 映画", app.dictionary.best("映画")?.reading == "えいが")
            check("deinflection 食べました", app.dictionary.resolve(surface: "食べました").entry?.word == "食べる")
            check("deinflection 行って → 行く", app.dictionary.resolve(surface: "行って").entry?.word == "行く")

            print("\n== tokenizer ==")
            let tokens = app.tokenizer.tokenize("昨日友達と映画を見に行きました")
            check("round trip", tokens.map(\.text).joined() == "昨日友達と映画を見に行きました")
            check("keeps 映画 whole", tokens.contains { $0.lemma == "映画" })
            check("marks を as particle", tokens.contains { $0.text == "を" && $0.kind == .particle })

            print("\n== deck budgets ==")
            app.decks = [
                Deck(id: "d1", name: "A", newPerDay: 2, reviewLimit: 3),
                Deck(id: "d2", name: "B", newPerDay: 1, reviewLimit: 1)
            ]
            app.profile.dailyNewWords = 10
            app.profile.dailyReviewLimit = 100
            app.words = []
            for index in 0..<5 {
                app.words.append(Self.newWord(id: "new-d1-\(index)", deck: "d1"))
                app.words.append(Self.newWord(id: "new-d2-\(index)", deck: "d2"))
            }
            let newQueue = app.makeReviewQueue(includeNew: true)
            let fromDeckOne = newQueue.filter { item in
                guard case .word(let identifier) = item.kind else { return false }
                return identifier.hasSuffix("-d1-\(identifier.suffix(1))") || identifier.contains("-d1-")
            }
            check("new cards respect per-deck budget", newQueue.count == 3, "\(newQueue.count) cards")
            check("deck A contributed its 2", fromDeckOne.count == 2, "\(fromDeckOne.count) from d1")

            print("\n== due reviews ==")
            app.words = []
            app.decks = [Deck(id: "r1", name: "R", newPerDay: 0, reviewLimit: 3)]
            for index in 0..<6 {
                var word = Self.newWord(id: "due-\(index)", deck: "r1")
                word.scheduling.intervalDays = 10
                word.scheduling.reviewCount = 2
                word.scheduling.dueAt = Date().addingTimeInterval(-3600)
                app.words.append(word)
            }
            let reviewQueue = app.makeReviewQueue(includeNew: false)
            check("due reviews capped by deck limit", reviewQueue.count == 3, "\(reviewQueue.count) cards")

            print("\n== scheduler through the model ==")
            app.words = [Self.newWord(id: "sched", deck: "r1")]
            let firstRating = app.applyWordRating(.good, wordID: "sched")
            let firstGap = (firstRating?.scheduling.dueAt.timeIntervalSinceNow ?? 0) / 60
            check("first good ≈ 1 minute", firstGap > 0.4 && firstGap < 2, String(format: "%.1f min", firstGap))
            _ = app.applyWordRating(.good, wordID: "sched")
            let second = app.word(id: "sched")
            let secondGap = (second?.scheduling.dueAt.timeIntervalSinceNow ?? 0) / 60
            check("second good ≈ 10 minutes", secondGap > 8 && secondGap < 12, String(format: "%.1f min", secondGap))
            _ = app.applyWordRating(.good, wordID: "sched")
            let third = app.word(id: "sched")
            check("graduation to 1 day", (third?.scheduling.intervalDays ?? 0) > 0.9)
            let lapse = app.applyWordRating(.again, wordID: "sched")
            check("again resets interval", lapse?.scheduling.intervalDays == 0)
            check("again lowers ease", (lapse?.scheduling.easeFactor ?? 9) < 2.5)
            check("again keeps pre-lapse interval", lapse?.scheduling.preLapseInterval != nil)
            check("lapsed card is not immediately due", lapse?.scheduling.isDue() == false)

            print("\n== session + undo ==")
            let session = app.reviewSession
            app.decks = [Deck(id: "u-deck", name: "U", newPerDay: 5, reviewLimit: 20)]
            app.words = [
                Self.newWord(id: "u1", deck: "u-deck"),
                Self.newWord(id: "u2", deck: "u-deck")
            ]
            app.profile.dailyNewWords = 5
            session.start(includeNew: true)
            check("session built", session.queue.count == 2, "\(session.queue.count) items")
            if case .word(let identifier)? = session.current?.kind {
                session.flip()
                session.rate(.good)
                let afterRating = app.word(id: identifier)
                check("rating moved the card forward", (afterRating?.scheduling.reviewCount ?? 0) == 1)
                session.undo()
                let afterUndo = app.word(id: identifier)
                check("undo restored the card", (afterUndo?.scheduling.reviewCount ?? -1) == 0)
                check("undo rewound the index", session.index == 0)
            } else {
                check("session exposes a card", false)
            }

            print("\n== activity totals ==")
            let today = app.today
            check("reviews recorded today", today.reviews >= 2, "\(today.reviews) reviews")
            check("today counts every rating", today.reviews >= 4, "\(today.reviews) ratings")
            check("streak counted today", app.streakDays >= 1, "\(app.streakDays) day(s)")
        }

        print("\n\(failures == 0 ? "ALL CHECKS PASSED" : "\(failures) CHECK(S) FAILED")")
        exit(failures == 0 ? 0 : 1)
    }

    private static func newWord(id: String, deck: String) -> SavedWord {
        SavedWord(
            id: id,
            word: "詞" + id.suffix(2),
            reading: "し",
            meanings: ["test"],
            level: .n5,
            deckIDs: [deck]
        )
    }
}
