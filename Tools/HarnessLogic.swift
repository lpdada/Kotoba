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
