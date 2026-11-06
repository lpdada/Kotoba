import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Behavioural checks for the app's decision layer, executed on Linux through
/// `Tools/verify_logic.sh` (platform services are replaced by `Tools/stubs`).
///
/// These are assertions about *behaviour*, not snapshots: deck budgets, the
/// scheduler ladder, rating effects, undo and daily activity.
@main
struct HarnessLogic {
    @MainActor
    static func main() async {
        var failures = 0

        func check(_ name: String, _ condition: Bool, _ detail: String = "") {
            if condition {
                print("  PASS  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            } else {
                failures += 1
                print("  FAIL  \(name)\(detail.isEmpty ? "" : "  — \(detail)")")
            }
        }

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

            print("\n== subtitle import ==")
            let srt = [
                "1", "00:00:01,000 --> 00:00:03,000", "<i>すみません、</i>これ、ください。", "",
                "2", "00:00:03,200 --> 00:00:05,000", "はい、二百円です。", "",
                "3", "00:00:05,200 --> 00:00:06,000", "はい、二百円です。", "",
                "4", "00:00:06,200 --> 00:00:08,400", "{\\an8}カードで払えますか。", ""
            ].joined(separator: "\r\n")
            let srtResult = (try? SubtitleParser.parse(srt)) ?? SubtitleParseResult(format: .srt, cues: [], skippedBlocks: 0)
            check("srt parsed", srtResult.format == .srt && srtResult.cues.count == 3, "\(srtResult.cues.count) cues")
            check("tags stripped", srtResult.cues.first?.text == "すみません、これ、ください。")
            check("override blocks stripped", srtResult.cues.last?.text == "カードで払えますか。")
            check("duplicate scrolling cue dropped", srtResult.cues.filter { $0.text == "はい、二百円です。" }.count == 1)
            check("timestamp with comma", SubtitleParser.parseTimestamp("00:01:02,500") == 62.5)
            check("short timestamp", SubtitleParser.parseTimestamp("01:02.500") == 62.5)

            let vtt = [
                "\u{FEFF}WEBVTT", "",
                "NOTE generated by a tool", "",
                "cue-1", "00:01.000 --> 00:02.500 align:start position:10%",
                "<b>これ</b>、ください。", "",
                "00:03.000 --> 00:04.000", "二百円&amp;です。", ""
            ].joined(separator: "\n")
            let vttResult = (try? SubtitleParser.parse(vtt)) ?? SubtitleParseResult(format: .vtt, cues: [], skippedBlocks: 0)
            check("vtt detected", vttResult.format == .vtt)
            check("vtt cue settings ignored", vttResult.cues.count == 2, "\(vttResult.cues.count) cues")
            check("vtt first cue cleaned", vttResult.cues.first?.text == "これ、ください。")
            check("vtt entity decoded", vttResult.cues.last?.text == "二百円&です。")
            check("empty subtitle rejected", (try? SubtitleParser.parse("  \n\n ")) == nil)

            var builder = SubtitleClipBuilder()
            builder.linesPerClip = 2
            builder.maxSeconds = 6
            let builtClips = builder.build(
                cues: vttResult.cues,
                mediaFileName: "ep01.mp4",
                series: "第 1 话",
                level: .n5
            )
            check("builder groups cues", builtClips.count == 1, "\(builtClips.count) clips")
            check("builder keeps media", builtClips.first?.media == .localFile("ep01.mp4"))
            check("builder id is stable", builtClips.first?.id == "sub-ep01-mp4-1", builtClips.first?.id ?? "nil")
            check("builder joins lines", builtClips.first?.lines.count == 2)
            check(
                "builder records the cue offset",
                builtClips.first?.startSeconds == 1.0,
                String(format: "%.1f s", builtClips.first?.startSeconds ?? -1)
            )

            let legacyJSON = """
            {"version":1,"clips":[{"id":"legacy","title":"t","series":"s","episode":"",
            "transcript":"はい","translation":"是","translation_en":"yes","level":"n5","topics":[],
            "duration_seconds":5,"media":{"kind":"generated"},"attribution":"","custom":false}]}
            """
            var legacyOK = false
            if let data = legacyJSON.data(using: .utf8),
               let collection = try? JSONDecoder().decode(ClipCollection.self, from: data),
               let clip = collection.clips.first {
                legacyOK = clip.startSeconds == 0 && clip.durationSeconds == 5
            }
            check("clip json without start_seconds still decodes", legacyOK)

            var bundledOK = false
            if let url = URL(fileURLWithPath: "Kotoba/Resources/SampleClips.json") as URL?,
               let data = try? Data(contentsOf: url),
               let collection = try? JSONDecoder().decode(ClipCollection.self, from: data) {
                bundledOK = collection.clips.count == 10 && collection.clips.allSatisfy { $0.startSeconds == 0 }
            }
            check("bundled sample clips decode", bundledOK)

            let imported = app.importSubtitleCues(
                vttResult,
                mediaFileName: "ep01.mp4",
                series: "测试话",
                level: .n5,
                linesPerClip: 2,
                maxSeconds: 6
            )
            check("importSubtitleCues adds clips", imported == 1, "\(imported) added")
            let reimported = app.importSubtitleCues(
                vttResult,
                mediaFileName: "ep01.mp4",
                series: "测试话",
                level: .n5,
                linesPerClip: 2,
                maxSeconds: 6
            )
            check("repeat import is idempotent", reimported == 0, "\(reimported) added")

            print("\n== backup and interoperability ==")
            var backupWord = SavedWord(
                id: "bk-1",
                word: "映画",
                reading: "えいが",
                meanings: ["movie", "film"],
                level: .n5,
                sourceSentence: "映画を見た。",
                deckIDs: [Deck.defaultDeckID]
            )
            backupWord.note = "第一行\n第二行"
            let tsv = BackupService.ankiTSV(words: [backupWord], decks: [Deck.makeDefault()])
            let tsvRows = tsv.components(separatedBy: "\n")
            let columns = tsvRows.first?.components(separatedBy: "\t") ?? []
            check("tsv single row", tsvRows.count == 1, "\(tsvRows.count) rows")
            check("tsv has five columns", columns.count == 5, "\(columns.count) columns")
            check("tsv keeps level tag", columns.count == 5 && columns[4].contains("N5"), columns.count == 5 ? columns[4] : "-")
            var messy = backupWord
            messy.meanings = ["movie\tfilm"]
            messy.sourceSentence = "映画を\n見た。"
            let messyTSV = BackupService.ankiTSV(words: [messy], decks: [Deck.makeDefault()])
            let messyRows = messyTSV.components(separatedBy: "\n").count
            let messyColumns = messyTSV.components(separatedBy: "\t").count
            check(
                "tsv sanitizes tabs and newlines",
                messyRows == 1 && messyColumns == 5,
                "\(messyRows) row(s), \(messyColumns) column(s)"
            )

            var snapshot = AppSnapshot()
            snapshot.words = [backupWord]
            snapshot.decks = [Deck.makeDefault()]
            snapshot.activity[DayKey.key(for: Date())] = DayActivity(dayKey: DayKey.key(for: Date()))
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var roundTripOK = false
            if let data = try? encoder.encode(snapshot),
               let decoded = try? BackupService.decodeSnapshot(from: data) {
                roundTripOK = decoded.words.count == 1
                    && decoded.words.first?.word == "映画"
                    && decoded.activity.count == 1
            }
            check("backup round trip", roundTripOK)

            var emptyRejected = false
            do { try BackupService.validate(AppSnapshot()) } catch { emptyRejected = true }
            check("empty backup rejected", emptyRejected)

            var future = AppSnapshot()
            future.schemaVersion = BackupService.schemaVersion + 1
            future.words = [backupWord]
            var futureRejected = false
            do { try BackupService.validate(future) } catch { futureRejected = true }
            check("newer schema rejected", futureRejected)

            let report = BackupService.report(for: snapshot)
            check("restore report counts", report.words == 1 && report.decks == 1, report.summary)

            print("\n== review load forecast ==")
            app.reviewSession.reset()
            let forecastNow = Date()
            var todayWord = Self.newWord(id: "f-1", deck: "u-deck")
            todayWord.scheduling.intervalDays = 3
            todayWord.scheduling.reviewCount = 1
            todayWord.scheduling.dueAt = forecastNow.addingTimeInterval(3600)
            var laterWord = Self.newWord(id: "f-2", deck: "u-deck")
            laterWord.scheduling.intervalDays = 5
            laterWord.scheduling.reviewCount = 2
            laterWord.scheduling.dueAt = forecastNow.addingTimeInterval(86_400 * 2)
            var overdueWord = Self.newWord(id: "f-3", deck: "u-deck")
            overdueWord.scheduling.intervalDays = 40
            overdueWord.scheduling.reviewCount = 5
            overdueWord.scheduling.dueAt = forecastNow.addingTimeInterval(-86_400 * 3)
            app.words = [todayWord, laterWord, overdueWord]

            let forecast = app.reviewForecast(days: 7, now: forecastNow)
            check("forecast has seven days", forecast.count == 7, "\(forecast.count)")
            check("today folds overdue cards", forecast[0].due == 2, "\(forecast[0].due) today")
            check("day after tomorrow counted", forecast[2].due == 1, "\(forecast[2].due) on day 3")
            check("overdue counted separately", app.overdueCount == 1, "\(app.overdueCount) overdue")

            print("\n== intensive listening: sentences ==")
            let timedClip = Clip(
                id: "int-1",
                title: "timed",
                series: "test",
                transcript: "すみません、これ、ください。\nはい。いいえ。",
                translation: "不好意思，请给我这个。\n是。不是。",
                level: .n5,
                durationSeconds: 4,
                mediaStartSeconds: 1,
                lineTimings: [
                    ClipLineTiming(start: 1, end: 3),
                    ClipLineTiming(start: 3, end: 5)
                ],
                media: .generated
            )
            let timedSentences = IntensiveSentenceBuilder.build(for: timedClip)
            check("sentences split by punctuation", timedSentences.count == 3, "\(timedSentences.count) sentences")
            check("first sentence keeps cue start", timedSentences.first?.start == 1.0, String(format: "%.1f", timedSentences.first?.start ?? -1))
            check(
                "second cue starts the split line",
                timedSentences.count == 3
                    && abs((timedSentences[1].start) - 3.0) < 0.001
                    && abs(timedSentences[2].end - 5.0) < 0.001,
                String(format: "s1 %.2f → s2 end %.2f", timedSentences[safe: 1]?.start ?? -1, timedSentences[safe: 2]?.end ?? -1)
            )
            check("translation follows the line", timedSentences.first?.translation == "不好意思，请给我这个。")
            check("split helper keeps punctuation", IntensiveSentenceBuilder.split("はい。いいえ！").count == 2)

            let untimedClip = Clip(
                id: "int-2",
                title: "untimed",
                series: "test",
                transcript: "あああ\nいいいい",
                translation: "a\nb",
                level: .n5,
                durationSeconds: 10,
                media: .generated
            )
            let untimedSentences = IntensiveSentenceBuilder.build(for: untimedClip)
            check("untimed clip divides the window", untimedSentences.count == 2 && untimedSentences[1].start == 5.0,
                  String(format: "%.1f", untimedSentences[safe: 1]?.start ?? -1))

            print("\n== intensive listening: state machine ==")
            var engine = IntensiveEngine(
                sentences: timedSentences,
                repeatTarget: 2,
                autoPauseAtEnd: false,
                loopCurrent: false
            )
            check("starts on the first sentence", engine.current?.index == 0)
            check("repeat 1/3 replays", engine.handleSentenceEnd() == .replay, "\(engine.repeatLabel)")
            check("repeat 2/2 advances", engine.handleSentenceEnd() == .advance(1), "\(engine.currentIndex)")
            check("index moved to sentence two", engine.currentIndex == 1)

            var loopEngine = IntensiveEngine(sentences: timedSentences, repeatTarget: 1, autoPauseAtEnd: false, loopCurrent: true)
            check("A-B loop replays", loopEngine.handleSentenceEnd() == .replay)
            check("A-B loop keeps the sentence", loopEngine.handleSentenceEnd() == .replay && loopEngine.currentIndex == 0)

            var pauseEngine = IntensiveEngine(sentences: timedSentences, repeatTarget: 1, autoPauseAtEnd: true, loopCurrent: false)
            check("auto-pause pauses", pauseEngine.handleSentenceEnd() == .pause)
            check("auto-pause marks waiting", pauseEngine.isAwaitingUser)
            pauseEngine.resume()
            check("resume clears waiting", pauseEngine.isAwaitingUser == false)

            var finishEngine = IntensiveEngine(sentences: timedSentences, repeatTarget: 1, autoPauseAtEnd: false, loopCurrent: false)
            _ = finishEngine.select(timedSentences.count - 1)
            check("last sentence finishes", finishEngine.handleSentenceEnd() == .finished)

            check("auto-pause toggle stores state", {
                var toggleEngine = IntensiveEngine(sentences: timedSentences, autoPauseAtEnd: true)
                toggleEngine.setAutoPause(false)
                let off = toggleEngine.autoPauseAtEnd == false
                toggleEngine.setAutoPause(true)
                return off && toggleEngine.autoPauseAtEnd
            }())
            check("repeat count is clamped", {
                var clampEngine = IntensiveEngine(sentences: timedSentences, repeatTarget: 1)
                clampEngine.setRepeat(9)
                let high = clampEngine.repeatTarget == 3
                clampEngine.setRepeat(0)
                return high && clampEngine.repeatTarget == 1
            }())
            check("next respects the end", {
                var navEngine = IntensiveEngine(sentences: timedSentences)
                _ = navEngine.select(timedSentences.count - 1)
                return navEngine.next() == nil && navEngine.currentIndex == timedSentences.count - 1
            }())
            check("previous respects the start", {
                var navEngine = IntensiveEngine(sentences: timedSentences)
                return navEngine.previous() == nil && navEngine.currentIndex == 0
            }())

            print("\n== intensive listening: shadowing records ==")
            app.shadowingRecords = []
            for index in 1...5 {
                app.saveShadowingRecord(
                    clipID: "int-1",
                    sentenceIndex: 0,
                    japanese: "すみません、これ、ください。",
                    fileName: "take-\(index).m4a",
                    duration: Double(index),
                    rating: index == 5 ? .gotIt : .practiceAgain
                )
            }
            check("shadowing keeps the newest three", app.shadowingRecords.count == 3, "\(app.shadowingRecords.count) kept")
            check("shadowing keeps the latest take", app.shadowingRecords.first?.fileName == "take-5.m4a")
            check("shadowing keeps the rating", app.shadowingRecords.first?.rating == .gotIt)
            app.saveShadowingRecord(
                clipID: "int-1",
                sentenceIndex: 1,
                japanese: "はい。",
                fileName: "other.m4a",
                duration: 0.8,
                rating: .practiceAgain
            )
            check("records are scoped per sentence", app.records(forClip: "int-1", sentence: 1).count == 1)
            check("latest lookup works", app.latestRecord(forClip: "int-1", sentence: 0)?.fileName == "take-5.m4a")

            var shadowSnapshot = AppSnapshot()
            shadowSnapshot.shadowingRecords = app.shadowingRecords
            let shadowEncoded = JSONEncoder()
            shadowEncoded.dateEncodingStrategy = .iso8601
            var shadowRoundTrip = false
            if let data = try? shadowEncoded.encode(shadowSnapshot),
               let decoded = try? BackupService.decodeSnapshot(from: data) {
                shadowRoundTrip = (decoded.shadowingRecords ?? []).count == app.shadowingRecords.count
            }
            check("shadowing survives a backup round trip", shadowRoundTrip)

            print("\n== kanji layer ==")
            var kanjiLoaded = false
            if let data = try? Data(contentsOf: URL(fileURLWithPath: "Kotoba/Resources/Kanji.json")) {
                try? app.kanji.load(data: data)
                kanjiLoaded = app.kanji.isLoaded
            }
            check("kanji data parses", kanjiLoaded && app.kanji.count > 2_000, "\(app.kanji.count) kanji")
            check(
                "every entry has strokes, radical and meaning",
                app.kanji.entries.allSatisfy { $0.strokes > 0 && $0.radicalNumber > 0 && !$0.meanings.isEmpty },
                "\(app.kanji.entries.count) checked"
            )
            check(
                "every entry has Japanese readings",
                app.kanji.entries.allSatisfy { !$0.onReadings.isEmpty || !$0.kunReadings.isEmpty }
            )
            check(
                "levels cover N5-N1",
                Set(app.kanji.entries.map(\.levelSortKey)).isSuperset(of: [1, 2, 3, 4])
            )

            let sun = app.kanji.entry(for: "日")
            check(
                "detail fields for 日",
                sun?.strokes == 4
                    && sun?.onReadings.contains("ニチ") == true
                    && sun?.chineseGloss == "日；太阳"
                    && sun?.pinyin == "rì"
                    && sun?.levelLabel == "N5",
                sun.map { "\($0.strokes)画 \($0.pinyin) \($0.chineseGloss)" } ?? "missing"
            )
            check("Chinese gloss covers N5+N4", app.kanji.entries.filter { $0.jlptLevel == 4 || $0.jlptLevel == 3 }.allSatisfy(\.hasChineseGloss))

            if let sun {
                let examples = app.exampleWords(for: sun, limit: 4)
                check("example words picked", !examples.isEmpty && examples.count <= 4, "\(examples.count) words")
                check("example words contain the kanji", examples.allSatisfy { $0.word.contains("日") })
                check(
                    "example words carry reading and meaning",
                    examples.allSatisfy { !$0.reading.isEmpty && !$0.meaning.isEmpty }
                )
                check("example words prefer compounds", examples.allSatisfy { $0.word.count > 1 })
                check(
                    "example words are ordered by level",
                    zip(examples, examples.dropFirst()).allSatisfy { ($0.level?.rank ?? 9) <= ($1.level?.rank ?? 9) }
                )
            }

            app.kanjiCards = []
            if let entry = app.kanji.entry(for: "日") {
                _ = app.saveKanjiCard(entry)
                check("kanji card saved", app.kanjiCards.count == 1)
                let firstStep = app.applyKanjiRating(.good, literal: "日")
                let firstGap = (firstStep?.scheduling.dueAt.timeIntervalSinceNow ?? 0) / 60
                check("kanji card reuses the 1-minute step", firstGap > 0.4 && firstGap < 2, String(format: "%.1f min", firstGap))
                _ = app.applyKanjiRating(.good, literal: "日")
                _ = app.applyKanjiRating(.good, literal: "日")
                check("kanji card graduates to a day", (app.kanjiCard("日")?.scheduling.intervalDays ?? 0) > 0.9)
                check("kanji rating counts as a review", app.today.reviews >= 3, "\(app.today.reviews) reviews")
            }

            app.decks = [Deck(id: "k-deck", name: "K", newPerDay: 5, reviewLimit: 20)]
            app.profile.dailyNewWords = 5
            app.profile.dailyReviewLimit = 20
            app.words = []
            if let moon = app.kanji.entry(for: "月") { _ = app.saveKanjiCard(moon) }
            let mixedQueue = app.makeReviewQueue(includeNew: true)
            check(
                "kanji cards join the review queue",
                mixedQueue.contains { item in
                    if case .kanji = item.kind { return true }
                    return false
                },
                "\(mixedQueue.count) cards"
            )
            check("kanji stats per level", app.kanjiLevelStats.contains { $0.label == "N5" && $0.total > 90 })
            if var learnedCard = app.kanjiCard("日") {
                learnedCard.scheduling.intervalDays = 21
                learnedCard.familiarity = 4
                app.updateKanjiCard(learnedCard)
            }
            check("learned kanji counted", app.kanjiLearnedCount >= 1, "\(app.kanjiLearnedCount) learned")

            var kanjiSnapshot = AppSnapshot()
            kanjiSnapshot.kanjiCards = app.kanjiCards
            let kanjiEncoder = JSONEncoder()
            kanjiEncoder.dateEncodingStrategy = .iso8601
            var kanjiRoundTrip = false
            if let data = try? kanjiEncoder.encode(kanjiSnapshot),
               let decoded = try? BackupService.decodeSnapshot(from: data) {
                kanjiRoundTrip = (decoded.kanjiCards ?? []).count == app.kanjiCards.count
            }
            check("kanji cards survive a backup round trip", kanjiRoundTrip)

            print("\n== accessibility: typography scale ==")
            check(
                "small sizes map to caption styles",
                FontScale.textStyle(for: 9) == .caption2
                    && FontScale.textStyle(for: 11) == .caption2
                    && FontScale.textStyle(for: 12) == .caption
                    && FontScale.textStyle(for: 13) == .footnote
            )
            check("body size maps to body", FontScale.textStyle(for: 17) == .body)
            check(
                "large display sizes map to title styles",
                FontScale.textStyle(for: 22) == .title2
                    && FontScale.textStyle(for: 28) == .title
                    && FontScale.textStyle(for: 40) == .largeTitle
            )
            check(
                "mapping never decreases as size grows",
                {
                    var previous = 0.0
                    var monotonic = true
                    for size in stride(from: 8.0, through: 80.0, by: 0.5) {
                        let value = FontScale.defaultSize(for: FontScale.textStyle(for: size))
                        if value < previous { monotonic = false }
                        previous = value
                    }
                    return monotonic
                }()
            )
            check(
                "display sizes use @ScaledMetric path",
                FontScale.usesDisplayScaling(64)
                    && FontScale.usesDisplayScaling(27)
                    && !FontScale.usesDisplayScaling(26)
                    && !FontScale.usesDisplayScaling(17),
                "threshold \(FontScale.displayThreshold)"
            )
            check(
                "every text style has a default size",
                FontScale.TextStyle.allCases.allSatisfy { FontScale.defaultSize(for: $0) > 0 }
            )
            check(
                "styles cover the sizes used by the UI",
                [9.0, 10, 11, 12, 13, 14, 15, 16, 17, 20, 22].allSatisfy { size in
                    FontScale.defaultSize(for: FontScale.textStyle(for: size)) > 0
                }
            )
            print("\n== youtube captions ==")
            let watchHTML = """
            {"playabilityStatus":{"status":"OK"},"captions":{"playerCaptionsTracklistRenderer":{"captionTracks":[
            {"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=ja&kind=asr&x=1","name":{"simpleText":"Japanese (auto)"},"languageCode":"ja","kind":"asr"},
            {"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=ja","name":{"simpleText":"Japanese"},"languageCode":"ja"},
            {"baseUrl":"https://www.youtube.com/api/timedtext?v=abc&lang=en","languageCode":"en"}
            ]}}}
            """
            let tracks = (try? YouTubeCaptionService.tracks(fromWatchHTML: watchHTML)) ?? []
            check("caption tracks parsed", tracks.count == 3, "\(tracks.count) tracks")
            check("japanese manual track exists", tracks.contains { $0.languageCode == "ja" && !$0.isAutomatic })
            let preferred = tracks.isEmpty ? nil : YouTubeCaptionService.preferredTrack(tracks)
            check("prefers manual japanese over ASR", preferred?.kind == "" && preferred?.languageCode == "ja")

            let json3 = """
            {"events":[{"tStartMs":1000,"dDurationMs":2000,"segs":[{"utf8":"すみません、"}]},
            {"tStartMs":3000,"dDurationMs":1500,"segs":[{"utf8":"これ、ください。"}]},
            {"tStartMs":4500,"dDurationMs":0}]}
            """
            let jsonCues = YouTubeCaptionService.cues(fromJSON3: Data(json3.utf8))
            check("json3 captions parsed", jsonCues.count == 2, "\(jsonCues.count) cues")
            check("json3 timing kept", abs(jsonCues[0].start - 1.0) < 0.001 && abs(jsonCues[1].start - 3.0) < 0.001)
            check("json3 text joined", jsonCues[1].text == "これ、ください。")

            let xml = "<transcript><text start=\"0.5\" dur=\"2.1\">&#39;&lt;i&gt;はい&lt;/i&gt;&#39; &amp;amp; いいえ</text><text start=\"3.0\" dur=\"1.0\">はい</text></transcript>"
            let xmlCues = YouTubeCaptionService.cues(fromXML: xml)
            check("legacy XML captions parsed", xmlCues.count == 2, "\(xmlCues.count) cues")
            check("XML entities and tags stripped", xmlCues.first?.text.contains("<i>") == false && xmlCues.first?.text.contains("&amp;") == false, xmlCues.first?.text ?? "-")

            print("\n== youtube import with captions ==")
            let captionService = YouTubeCaptionService { url in
                if url.absoluteString.contains("fmt=json3") { return Data(json3.utf8) }
                return Data(watchHTML.utf8)
            }
            var fetched: (track: YouTubeCaptionTrack, cues: [SubtitleCue])?
            do { fetched = try await captionService.fetchCues(videoID: "abc") } catch { fetched = nil }
            check("caption fetch pipeline works offline", fetched?.cues.count == 2)
            if let fetched {
                let captionClip = app.importYouTubeClip(
                    videoID: "abc",
                    title: "抓取测试",
                    cues: fetched.cues,
                    translation: "",
                    level: .n5
                )
                check("caption clip imported", captionClip?.lines.count == 2)
                check("caption clip keeps timings", captionClip?.lineTimings?.count == 2 && captionClip?.startSeconds == 1.0)
                check("caption clip is a youtube clip", { if case .youtube = captionClip?.media { return true } else { return false } }())
            }

            print("\n== echo session ==")
            let echoSentences = IntensiveSentenceBuilder.build(for: timedClip)
            var echo = EchoSession(sentences: echoSentences)
            check("echo starts at listen", echo.step == .listen && echo.index == 0)
            check("echo reaches understand", { echo.advance(); return echo.step == .understand }())
            check("echo reaches imitate", { echo.advance(); return echo.step == .imitate }())
            check("echo reaches compare", { echo.advance(); return echo.step == .compare }())
            let movedOn = echo.advance()
            check("echo wraps to next sentence", movedOn && echo.index == 1 && echo.step == .listen, "\(echo.index)/\(echo.step.title)")
            var lastEcho = EchoSession(sentences: echoSentences, index: echoSentences.count - 1)
            _ = lastEcho.advance(); _ = lastEcho.advance(); _ = lastEcho.advance()
            _ = lastEcho.advance()
            check("echo finishes after the last sentence", lastEcho.isFinished)
            check("echo progress is bounded", echo.progress >= 0 && echo.progress <= 1)

            print("\n== word states ==")
            if let movieEntry = app.dictionary.best("映画") {
                app.words.removeAll { $0.word == "映画" }
                check("unsaved word is unseen", app.wordState(entryID: movieEntry.id) == .unseen)
                let known = app.setWordState(.known, entry: movieEntry, surface: "映画")
                check("known state saved the word", known != nil && known?.familiarity == 5)
                check("known state derives known", app.wordState(entryID: movieEntry.id) == .known)
                let learning = app.setWordState(.learning, entry: movieEntry, surface: "映画")
                check("learning state resets scheduling", learning?.familiarity == 1 && learning?.scheduling.intervalDays == 0)
                check("learning state derives learning", app.wordState(entryID: movieEntry.id) == .learning)
                _ = app.setWordState(.unseen, entry: movieEntry, surface: "映画")
                check("unseen removes the word", app.wordState(entryID: movieEntry.id) == .unseen && app.words.isEmpty)
            }

            print("\n== clip library filters ==")
            if let ytClip = app.customClips.first(where: { if case .youtube = $0.media { return true } else { return false } }) {
                check("library finds youtube clips", app.libraryClips(source: .youtube).contains { $0.id == ytClip.id })
                check("library filters by query", app.libraryClips(query: "抓取测试").contains { $0.id == ytClip.id })
                check("library query misses unrelated text", app.libraryClips(query: "zzzz").isEmpty)
            }
            check("library all-source is a superset", app.libraryClips(source: .all).count >= app.libraryClips(source: .youtube).count)

            check("state file without the new key still decodes", {
                var full = AppSnapshot()
                full.words = [backupWord]
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                guard let data = try? encoder.encode(full),
                      var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
                object.removeValue(forKey: "shadowingRecords")
                guard let stripped = try? JSONSerialization.data(withJSONObject: object),
                      let decoded = try? BackupService.decodeSnapshot(from: stripped) else { return false }
                return decoded.words.count == 1 && (decoded.shadowingRecords ?? []).isEmpty
            }())
        print("\n== self-hosted transcription settings ==")
        let defaults = TranscriptionSettings()
        check("transcription is off by default", defaults.isEnabled == false && defaults.isConfigured == false)
        check(
            "default address is the personal deployment",
            defaults.serverURL == ServerDefaults.baseURL && ServerDefaults.baseURL == "https://asr.ysloving.com",
            defaults.serverURL
        )
        check("clearing the address disables server features", {
            var cleared = defaults
            cleared.serverURL = ""
            return cleared.endpointURL == nil && cleared.isConfigured == false
        }())

        var configured = TranscriptionSettings()
        configured.isEnabled = true
        configured.serverURL = "https://asr.example.test/"
        configured.timeoutSeconds = 45
        check("trailing slash normalised", configured.normalizedServerURL == "https://asr.example.test")
        check("endpoint gets /transcribe", configured.endpointURL?.absoluteString == "https://asr.example.test/transcribe")
        check("configured only when enabled", configured.isConfigured)
        check("timeout clamped", TranscriptionSettings(isEnabled: true, serverURL: "https://a.test", timeoutSeconds: 5).timeoutInterval == 15)

        var bad = TranscriptionSettings()
        bad.isEnabled = true
        bad.serverURL = "ftp://nope"
        check("non-http address rejected", bad.endpointURL == nil && bad.isConfigured == false)
        bad.serverURL = "not a url"
        check("garbage address rejected", bad.isConfigured == false)

        var full = configured
        full.serverURL = "https://asr.example.test/transcribe"
        check("full endpoint kept as is", full.endpointURL?.absoluteString == "https://asr.example.test/transcribe")

        print("\n== transcription request shape ==")
        guard let request = try? Self.configuredRequest(configured, videoID: "dQw4w9WgXcQ") else {
            check("request built", false)
            return
        }
        check("request is POST", request.httpMethod == "POST")
        check("request sets timeout", abs(request.timeoutInterval - 45) < 0.5, "\(request.timeoutInterval)")
        check("request sends JSON", request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = (try? JSONSerialization.jsonObject(with: request.httpBody ?? Data())) as? [String: Any] ?? [:]
        check("body carries video id", body["video_id"] as? String == "dQw4w9WgXcQ")
        check("body asks for Chinese", body["translate_to"] as? String == "zh")
        check("no secret header set", request.value(forHTTPHeaderField: "Authorization") == nil)

        print("\n== transcription response decoding ==")
        let payload = """
        {"language":"ja","provider":"sherpa-onnx","lines":[
        {"start":3.0,"end":4.2,"japanese":"これ、ください。","chinese":"请给我这个。"},
        {"start":1.0,"end":2.0,"ja":"すみません","zh":"不好意思"},
        {"start":5.0,"text":"はい","translation":"好"},
        {"start":6.0,"end":7.0,"japanese":"   "}]}
        """
        guard let decoded = try? TranscriptionClient.decode(Data(payload.utf8)) else {
            check("transcription payload decodes", false)
            return
        }
        check("decoding keeps three lines and sorts", decoded.lines.count == 3 && decoded.lines[0].start == 1.0, "\(decoded.lines.count)")
        check("decoding accepts ja/zh aliases", decoded.lines[0].chinese == "不好意思" && decoded.lines[1].japanese == "これ、ください。")
        check("decoding keeps provider", decoded.provider == "sherpa-onnx")
        check("chinese column built", decoded.chineseText?.components(separatedBy: "\n").count == 3)
        var reject = false
        do { _ = try TranscriptionClient.decode(Data("{\"lines\":[]}".utf8)) } catch { reject = true }
        check("empty transcript rejected", reject)
        var decodeFail = false
        do { _ = try TranscriptionClient.decode(Data("<html>".utf8)) } catch { decodeFail = true }
        check("html body rejected", decodeFail)
        check("cue end is clamped", decoded.lines[0].subtitleCue.end >= decoded.lines[0].subtitleCue.start + 0.3)

        print("\n== transcription retry policy ==")
        let box = AttemptBox()
        let goodBody = """
        {"lines":[{"start":0,"end":1,"japanese":"はい","chinese":"好"}]}
        """
        let retrying = TranscriptionClient(
            settings: configured,
            send: { request in
                box.attempts += 1
                let code = box.attempts < 3 ? 500 : 200
                let data = code == 200 ? Data(goodBody.utf8) : Data("boom".utf8)
                return (data, code)
            },
            sleep: { seconds in box.slept.append(seconds) }
        )
        let retried = try? await retrying.transcribe(videoID: "abc")
        check("retries 5xx then succeeds", box.attempts == 3 && (retried?.lines.count ?? 0) == 1, "\(box.attempts) attempts")
        check("backoff is 1s then 3s", box.slept == [1, 3], "\(box.slept)")

        let badBox = AttemptBox()
        let noRetry = TranscriptionClient(
            settings: configured,
            send: { request in
                badBox.attempts += 1
                return (Data(), 400)
            },
            sleep: { seconds in badBox.slept.append(seconds) }
        )
        var sawBadRequest = false
        do { _ = try await noRetry.transcribe(videoID: "abc") } catch let error as TranscriptionError {
            if case .http(let status, _) = error, status == 400 { sawBadRequest = true }
        } catch { }
        check("4xx is not retried", sawBadRequest && badBox.attempts == 1 && badBox.slept.isEmpty, "\(badBox.attempts) attempts")

        let offlineBox = AttemptBox()
        let offline = TranscriptionClient(
            settings: configured,
            send: { _ in
                offlineBox.attempts += 1
                throw URLError(.timedOut)
            },
            sleep: { _ in }
        )
        var offlineFailed = false
        do { _ = try await offline.transcribe(videoID: "abc") } catch let error as TranscriptionError {
            if case .network = error { offlineFailed = true }
        } catch { }
        check("network failure surfaces after retries", offlineFailed && offlineBox.attempts == 3, "\(offlineBox.attempts) attempts")

        let disabledBox = AttemptBox()
        let disabledClient = TranscriptionClient(
            settings: .disabled,
            send: { _ in disabledBox.attempts += 1; throw URLError(.badURL) },
            sleep: { _ in }
        )
        var disabledThrew = false
        do { _ = try await disabledClient.transcribe(videoID: "abc") } catch let error as TranscriptionError {
            if case .notConfigured = error { disabledThrew = true }
        } catch { }
        check("disabled client never hits the network", disabledThrew && disabledBox.attempts == 0)

        print("\n== transcription integration ==")
        app.transcription = .disabled
        var appRefused = false
        do { _ = try await app.transcribeYouTube(videoID: "abc") } catch let error as TranscriptionError {
            if case .notConfigured = error { appRefused = true }
        } catch { }
        check("AppModel refuses without configuration", appRefused)

        app.transcription = configured
        let transcribed = TranscriptionResult(
            lines: [
                TranscriptionLine(start: 1.0, end: 2.5, japanese: "すみません", chinese: "不好意思"),
                TranscriptionLine(start: 2.6, end: 4.0, japanese: "これ、ください", chinese: "请给我这个")
            ],
            language: "ja",
            provider: "sherpa-onnx"
        )
        let transcribedClip = app.importTranscribedClip(videoID: "srv123", title: "服务器转写", result: transcribed, level: .n5)
        check("server transcript becomes a clip", transcribedClip?.lines.count == 2 && transcribedClip?.translationLines.count == 2)
        check("server clip keeps timings", transcribedClip?.lineTimings?.count == 2 && transcribedClip?.startSeconds == 1.0)
        check("server clip records provider", transcribedClip?.attribution.contains("sherpa-onnx") == true)
        check("server clip is a youtube clip", { if case .youtube = transcribedClip?.media { return true } else { return false } }())

        var settingsSnapshot = AppSnapshot()
        settingsSnapshot.transcription = configured
        let settingsEncoder = JSONEncoder()
        settingsEncoder.dateEncodingStrategy = .iso8601
        var settingsRoundTrip = false
        if let data = try? settingsEncoder.encode(settingsSnapshot),
           let restored = try? BackupService.decodeSnapshot(from: data) {
            settingsRoundTrip = restored.transcription == configured
        }
        check("transcription settings survive a backup", settingsRoundTrip)
        check("old backups without the key stay off", {
            guard let data = try? settingsEncoder.encode(AppSnapshot()) else { return false }
            guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            object.removeValue(forKey: "transcription")
            guard let stripped = try? JSONSerialization.data(withJSONObject: object),
                  let restored = try? BackupService.decodeSnapshot(from: stripped) else { return false }
            return (restored.transcription ?? .disabled).isEnabled == false
        }())

        print("\n== edge tts protocol ==")
        let ssml = EdgeTTSProtocol.ssml(
            text: "すみません & <これ> \"ください\"",
            voiceID: "ja-JP-NanamiNeural",
            ratePercent: 20
        )
        check("ssml carries the voice", ssml.contains("name=\"ja-JP-NanamiNeural\""))
        check("ssml carries prosody rate", ssml.contains("rate=\"+20%\""), ssml.prefix(120).description)
        check("ssml escapes xml", ssml.contains("&amp;") && ssml.contains("&lt;これ&gt;") && !ssml.contains("<これ>"))
        check("ssml declares japanese", ssml.contains("xml:lang=\"ja-JP\""))

        check("rate 0.45 is neutral", EdgeTTSProtocol.ratePercent(forSpeechRate: 0.45) == 0)
        check("rate 0.30 is slower", EdgeTTSProtocol.ratePercent(forSpeechRate: 0.30) == -30)
        check("rate 0.62 is faster", EdgeTTSProtocol.ratePercent(forSpeechRate: 0.62) == 34)
        check("rate clamps at edges", EdgeTTSProtocol.ratePercent(forSpeechRate: 0.1) == -50 && EdgeTTSProtocol.ratePercent(forSpeechRate: 0.9) == 50)

        let audioPayload = Data([0xFF, 0xF3, 0x64, 0xC4, 0x00, 0x01])
        let audioFrame = EdgeTTSFrame.parse(EdgeTTSFrame.make(path: "audio", payload: audioPayload))
        check("audio frame parsed", audioFrame?.isAudio == true && audioFrame?.payload == audioPayload)
        let endFrame = EdgeTTSFrame.parse(EdgeTTSFrame.make(path: "turn.end", payload: Data()))
        check("turn.end frame parsed", endFrame?.isTurnEnd == true)
        check("truncated frame rejected", EdgeTTSFrame.parse(Data([0x00])) == nil)
        check("mp3 sniffing", EdgeTTSProtocol.looksLikeMP3(Data([0xFF, 0xF3, 0x00])) && !EdgeTTSProtocol.looksLikeMP3(Data("hello".utf8)))

        print("\n== edge tts cache keys ==")
        check(
            "sha256 known vectors",
            SHA256Hex.digest(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
                && SHA256Hex.digest(Data()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
        let keyA = EdgeTTSCacheKey.make(voiceID: "ja-JP-NanamiNeural", ratePercent: 0, text: "こんにちは")
        let keyB = EdgeTTSCacheKey.make(voiceID: "ja-JP-NanamiNeural", ratePercent: 0, text: "こんにちは  \n")
        let keyC = EdgeTTSCacheKey.make(voiceID: "ja-JP-KeitaNeural", ratePercent: 0, text: "こんにちは")
        let keyD = EdgeTTSCacheKey.make(voiceID: "ja-JP-NanamiNeural", ratePercent: 20, text: "こんにちは")
        check("cache key is stable and trims", keyA == keyB && keyA.count == 64)
        check("cache key varies by voice and rate", keyA != keyC && keyA != keyD)

        print("\n== edge tts fallback ==")
        check("disabled prefers system", EdgeTTSRouter.decide(preferEdge: false, voiceUsable: true, online: true, secondsSinceLastFailure: nil) == .useSystem(reason: "已在设置里关闭 Edge TTS"))
        check("missing voice id falls back", EdgeTTSRouter.decide(preferEdge: true, voiceUsable: false, online: true, secondsSinceLastFailure: nil).shouldUseEdge == false)
        check("offline goes straight to system", EdgeTTSRouter.decide(preferEdge: true, voiceUsable: true, online: false, secondsSinceLastFailure: nil).shouldUseEdge == false)
        check("recent failure cools down", EdgeTTSRouter.decide(preferEdge: true, voiceUsable: true, online: true, secondsSinceLastFailure: 10).shouldUseEdge == false)
        check("cooldown expires", EdgeTTSRouter.decide(preferEdge: true, voiceUsable: true, online: true, secondsSinceLastFailure: 700).shouldUseEdge)
        check("online with no failures uses edge", EdgeTTSRouter.decide(preferEdge: true, voiceUsable: true, online: true, secondsSinceLastFailure: nil).shouldUseEdge)
        check("timeout clamped", EdgeTTSRouter.clampTimeout(1) == 5 && EdgeTTSRouter.clampTimeout(15) == 15 && EdgeTTSRouter.clampTimeout(99) == 30)

        print("\n== edge tts cache eviction ==")
        let cacheRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kottoba-edge-tts-" + UUID().uuidString)
        let cache = EdgeTTSCache(directory: cacheRoot, limitBytes: 1_500)
        for index in 1...3 {
            let url = cache.fileURL(forKey: "k\(index)")
            try? Data(repeating: 0x41, count: 600).write(to: url)
            try? FileManager.default.setAttributes(
                [.modificationDate: Date().addingTimeInterval(Double(-100 * (4 - index)))],
                ofItemAtPath: url.path
            )
        }
        check("cache starts over the cap", cache.currentSize() == 1_800, "\(cache.currentSize()) bytes")
        let removed = cache.evictIfNeeded()
        check("eviction brings it under the cap", cache.currentSize() <= 1_500, "\(cache.currentSize()) bytes")
        check("oldest entries evicted first", removed == 1 && !FileManager.default.fileExists(atPath: cache.fileURL(forKey: "k1").path))
        try? FileManager.default.removeItem(at: cacheRoot)

        print("\n== edge tts voice options ==")
        var options = VoiceOptions.default
        check("edge preferred by default", options.preferEdge)
        check("nanami is the default voice", options.effectiveVoiceID == "ja-JP-NanamiNeural")
        options.voice = .keita
        check("keita maps to its neural id", options.effectiveVoiceID == "ja-JP-KeitaNeural")
        options.voice = .custom
        options.customVoiceID = "  ja-JP-AoiNeural "
        check("custom voice is trimmed", options.effectiveVoiceID == "ja-JP-AoiNeural")
        options.customVoiceID = ""
        check("empty custom voice is unusable", options.isUsable == false)

        var voiceSnapshot = AppSnapshot()
        voiceSnapshot.voiceOptions = VoiceOptions(preferEdge: false, voice: .keita, customVoiceID: "")
        let voiceEncoder = JSONEncoder()
        voiceEncoder.dateEncodingStrategy = .iso8601
        var voiceRoundTrip = false
        if let data = try? voiceEncoder.encode(voiceSnapshot),
           let restored = try? BackupService.decodeSnapshot(from: data) {
            voiceRoundTrip = restored.voiceOptions?.voice == .keita && restored.voiceOptions?.preferEdge == false
        }
        check("voice options survive a backup", voiceRoundTrip)

        print("\n== read-aloud mode selection ==")
        let bare = VoiceOptions()
        check("no address anywhere → edge direct", bare.effectiveMode(transcriptionURL: "") == .edgeDirect)
        check("transcription address enables server mode", bare.effectiveMode(transcriptionURL: "https://asr.test") == .server)
        var explicitSystem = bare
        explicitSystem.mode = .systemOnly
        check("system-only wins over addresses", explicitSystem.effectiveMode(transcriptionURL: "https://asr.test") == .systemOnly)
        var legacyOff = bare
        legacyOff.preferEdge = false
        check("legacy preferEdge=false maps to system only", legacyOff.effectiveMode(transcriptionURL: "") == .systemOnly)
        var serverNoAddress = bare
        serverNoAddress.mode = .server
        check("server mode without address degrades to edge", serverNoAddress.effectiveMode(transcriptionURL: "") == .edgeDirect)
        check("server mode with transcription address stays server", serverNoAddress.effectiveMode(transcriptionURL: "https://asr.test") == .server)
        var ownAddress = bare
        ownAddress.serverURL = "https://tts.own.test"
        check("own address wins for resolution", ownAddress.resolvedServerURL(transcriptionURL: "https://asr.test") == "https://tts.own.test")
        check("transcription address used when own is empty", bare.resolvedServerURL(transcriptionURL: "https://asr.test") == "https://asr.test")
        check("resolution trims whitespace", bare.resolvedServerURL(transcriptionURL: "  https://asr.test  ") == "https://asr.test")

        print("\n== server synthesis request ==")
        let serverClient = ServerTTSService(baseURL: "https://tts.example.test", send: { request in (Data(), 200) })
        check("endpoint appends /tts", serverClient.endpointURL?.absoluteString == "https://tts.example.test/tts")
        let trailing = ServerTTSService(baseURL: "https://tts.example.test/", send: { _ in (Data(), 200) })
        check("trailing slash normalised", trailing.endpointURL?.absoluteString == "https://tts.example.test/tts")
        let fullEndpoint = ServerTTSService(baseURL: "https://tts.example.test/tts", send: { _ in (Data(), 200) })
        check("full endpoint kept", fullEndpoint.endpointURL?.absoluteString == "https://tts.example.test/tts")
        let badEndpoint = ServerTTSService(baseURL: "ftp://nope", send: { _ in (Data(), 200) })
        check("non-http base rejected", badEndpoint.endpointURL == nil)

        guard let ttsRequest = try? serverClient.makeRequest(text: "こんにちは", voiceID: "ja-JP-NanamiNeural", ratePercent: -20, timeout: 15) else {
            check("server request built", false)
            return
        }
        check("server request is POST", ttsRequest.httpMethod == "POST")
        check("server request sets timeout", abs(ttsRequest.timeoutInterval - 15) < 0.5, "\(ttsRequest.timeoutInterval)")
        check("server request sends JSON", ttsRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")
        check("server request expects mpeg", ttsRequest.value(forHTTPHeaderField: "Accept") == "audio/mpeg")
        let ttsBody = (try? JSONSerialization.jsonObject(with: ttsRequest.httpBody ?? Data())) as? [String: Any] ?? [:]
        check("server body carries text", ttsBody["text"] as? String == "こんにちは")
        check("server body carries voice", ttsBody["voice"] as? String == "ja-JP-NanamiNeural")
        check("server body carries rate", ttsBody["rate_percent"] as? Int == -20)
        check("server request has no auth header", ttsRequest.value(forHTTPHeaderField: "Authorization") == nil)

        print("\n== server synthesis response handling ==")
        let mp3 = Data([0xFF, 0xF3, 0x64, 0xC4] + Data(repeating: 0x11, count: 600))
        let okClient = ServerTTSService(baseURL: "https://tts.test", send: { _ in (mp3, 200) })
        let okData = try? await okClient.audio(text: "はい", voiceID: "ja-JP-NanamiNeural", ratePercent: 0)
        check("200 + mp3 accepted", okData == mp3)

        let textClient = ServerTTSService(baseURL: "https://tts.test", send: { _ in (Data("oops".utf8), 200) })
        var rejectedNonMP3 = false
        do { _ = try await textClient.audio(text: "はい", voiceID: "v", ratePercent: 0) }
        catch let error as ServerTTSService.Failure { if case .malformedAudio = error { rejectedNonMP3 = true } } catch { }
        check("non-mp3 body rejected", rejectedNonMP3)

        let emptyClient = ServerTTSService(baseURL: "https://tts.test", send: { _ in (Data(), 200) })
        var rejectedEmpty = false
        do { _ = try await emptyClient.audio(text: "はい", voiceID: "v", ratePercent: 0) }
        catch let error as ServerTTSService.Failure { if case .emptyAudio = error { rejectedEmpty = true } } catch { }
        check("empty body rejected", rejectedEmpty)

        let errorClient = ServerTTSService(baseURL: "https://tts.test", send: { _ in (Data("boom".utf8), 500) })
        var sawServerError = false
        do { _ = try await errorClient.audio(text: "はい", voiceID: "v", ratePercent: 0) }
        catch let error as ServerTTSService.Failure {
            if case .http(let status, _) = error, status == 500 { sawServerError = true }
        } catch { }
        check("5xx surfaces as http error", sawServerError)

        let offlineClient = ServerTTSService(baseURL: "https://tts.test", send: { _ in throw URLError(.notConnectedToInternet) })
        var sawNetwork = false
        do { _ = try await offlineClient.audio(text: "はい", voiceID: "v", ratePercent: 0) }
        catch let error as ServerTTSService.Failure { if case .network = error { sawNetwork = true } } catch { }
        check("transport failure surfaces as network", sawNetwork)

        print("\n== server audio cache reuse ==")
        let serverCacheRoot = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("kottoba-server-tts-" + UUID().uuidString)
        let serverCache = EdgeTTSCache(directory: serverCacheRoot, limitBytes: 5_000_000)
        let serverKey = EdgeTTSCacheKey.make(voiceID: "ja-JP-NanamiNeural", ratePercent: 0, text: "こんにちは")
        try? serverCache.store(mp3, forKey: serverKey)
        check("server audio lands in the shared cache", serverCache.existing(forKey: serverKey) != nil)
        check("cache key is source independent", serverKey == EdgeTTSCacheKey.make(voiceID: "ja-JP-NanamiNeural", ratePercent: 0, text: "こんにちは"))
        try? FileManager.default.removeItem(at: serverCacheRoot)

        print("\n== long text chunking ==")
        check("short text stays whole", TextChunker.chunks(of: "こんにちは。") == ["こんにちは。"])
        let longText = String(repeating: "今日はいい天気ですね。", count: 200)
        let chunks = TextChunker.chunks(of: longText)
        check("long text is split under the limit", chunks.count > 1 && chunks.allSatisfy { $0.count <= TextChunker.limit }, "\(chunks.count) chunks")
        check("no text is lost when chunking", chunks.joined().count == longText.count, "\(chunks.joined().count) vs \(longText.count)")
        check("chunks break on sentence punctuation", chunks.dropLast().allSatisfy { $0.hasSuffix("。") })
        let giantSentence = String(repeating: "あ", count: 2_500)
        let hardSplit = TextChunker.chunks(of: giantSentence)
        check("runaway sentence is hard split", hardSplit.allSatisfy { $0.count <= TextChunker.limit } && hardSplit.joined().count == 2_500)
        check("empty text yields nothing", TextChunker.chunks(of: "   ").isEmpty)

        var overLimitRejected = false
        do {
            _ = try serverClient.makeRequest(
                text: String(repeating: "あ", count: ServerTTSService.maxTextLength + 1),
                voiceID: "v",
                ratePercent: 0,
                timeout: 15
            )
        } catch let error as ServerTTSService.Failure {
            if case .textTooLong(let limit) = error, limit == 1_000 { overLimitRejected = true }
        } catch { }
        check("client refuses over-limit text before sending", overLimitRejected)

        print("\n== 400 handling ==")
        let badRequest = ServerTTSService(baseURL: "https://tts.test", send: { _ in (Data("{\"detail\":\"String should have at most 1000 characters\"}".utf8), 400) })
        var saw400 = false
        do { _ = try await badRequest.audio(text: "はい", voiceID: "v", ratePercent: 0) }
        catch let error as ServerTTSService.Failure {
            if case .http(let status, _) = error, status == 400 { saw400 = true }
        } catch { }
        check("400 is surfaced as an http failure (silent fallback)", saw400)
        check("no 422-specific branch anywhere", {
            let marker = "42" + "2"
            let files = ["Kotoba/Services/ServerTTSService.swift", "Kotoba/Services/SpeechService.swift"]
            return files.allSatisfy { path in
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
                return !text.contains(marker)
            }
        }())

        print("\n== app wiring for read-aloud ==")
        // "No address anywhere" now means explicitly cleared, since this build
        // ships a pre-filled default.
        app.transcription = TranscriptionSettings(isEnabled: false, serverURL: "", timeoutSeconds: 90, translateToChinese: true)
        app.voiceOptions = VoiceOptions(mode: .server, serverURL: "")
        app.updateVoiceOptions { _ in }
        check("no address → speech configured as edge", app.speech.configuredMode == .edgeDirect)

        app.transcription = TranscriptionSettings(isEnabled: false, serverURL: "", timeoutSeconds: 90, translateToChinese: true)
        app.voiceOptions = VoiceOptions()
        app.updateVoiceOptions { _ in }
        check("empty everywhere → edge direct (old behaviour)", app.speech.configuredMode == .edgeDirect)

        app.updateTranscription { $0.serverURL = "https://asr.test" }
        check("transcription address promotes server mode", app.speech.configuredMode == .server)
        check("server base resolves to transcription address", app.speech.configuredServer == "https://asr.test")

        app.updateVoiceOptions { $0.serverURL = "https://tts.own.test" }
        check("own read-aloud address overrides", app.speech.configuredServer == "https://tts.own.test")

        app.updateVoiceOptions { $0.mode = .systemOnly }
        check("system-only reaches the speech service", app.speech.configuredMode == .systemOnly)
        app.updateVoiceOptions { $0.mode = .edgeDirect }
        check("edge direct reaches the speech service", app.speech.configuredMode == .edgeDirect)

        var voicePayload = AppSnapshot()
        voicePayload.voiceOptions = VoiceOptions(mode: .server, serverURL: "https://tts.own.test")
        let modeEncoder = JSONEncoder()
        modeEncoder.dateEncodingStrategy = .iso8601
        var modeRoundTrip = false
        if let data = try? modeEncoder.encode(voicePayload),
           let restored = try? BackupService.decodeSnapshot(from: data) {
            modeRoundTrip = restored.voiceOptions?.mode == .server
                && restored.voiceOptions?.serverURL == "https://tts.own.test"
        }
        check("3-way mode survives a backup", modeRoundTrip)
        check("old backups without mode still decode", {
            guard let data = try? modeEncoder.encode(AppSnapshot()) else { return false }
            guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
            if var voice = object["voiceOptions"] as? [String: Any] {
                voice.removeValue(forKey: "mode")
                object["voiceOptions"] = voice
            }
            guard let stripped = try? JSONSerialization.data(withJSONObject: object),
                  let restored = try? BackupService.decodeSnapshot(from: stripped) else { return false }
            return restored.voiceOptions?.mode == nil
        }())

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

    private static func configuredRequest(_ settings: TranscriptionSettings, videoID: String) throws -> URLRequest {
        try TranscriptionClient(settings: settings, send: { _ in (Data(), 200) }, sleep: { _ in }).makeRequest(videoID: videoID)
    }
}

final class AttemptBox {
    var attempts = 0
    var slept: [Double] = []
}
