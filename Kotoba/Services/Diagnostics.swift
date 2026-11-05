import Foundation

struct DiagnosticCheck: Identifiable {
    let id: String
    let title: String
    let passed: Bool
    let detail: String
}

/// Runs real self-checks against the shipped engines. Used by the diagnostics
/// screen so the core logic can be verified on device without a test target.
@MainActor
enum Diagnostics {
    static func run(app: AppModel) -> [DiagnosticCheck] {
        var checks: [DiagnosticCheck] = []

        // 1. Dictionary
        let entryCount = app.dictionary.entries.count
        checks.append(
            check(
                id: "dictionary",
                title: "词典载入",
                passed: entryCount > 5000,
                detail: "共 \(entryCount) 条词条"
            )
        )

        // 2. Exact lookup
        if let movie = app.dictionary.best("映画") {
            checks.append(
                check(
                    id: "lookup-exact",
                    title: "精确查词「映画」",
                    passed: movie.reading == "えいが",
                    detail: "读音 \(movie.reading)，等级 \(movie.level?.label ?? "—")，释义 \(movie.primaryMeaning)"
                )
            )
        } else {
            checks.append(check(id: "lookup-exact", title: "精确查词「映画」", passed: false, detail: "未找到"))
        }

        // 3. Reverse conjugation
        let conjugated = [("食べました", "食べる"), ("書いて", "書く"), ("高かった", "高い"), ("行って", "行く")]
        let conjugationResults = conjugated.map { surface, expected -> String in
            let resolved = app.dictionary.resolve(surface: surface)
            let ok = resolved.entry?.word == expected
            return "\(surface)→\(resolved.entry?.word ?? "nil")\(ok ? "✓" : "✗")"
        }
        let conjugationOK = conjugated.allSatisfy { surface, expected in
            app.dictionary.resolve(surface: surface).entry?.word == expected
        }
        checks.append(
            check(
                id: "deinflection",
                title: "动词/形容词还原",
                passed: conjugationOK,
                detail: conjugationResults.joined(separator: "  ")
            )
        )

        // 4. Tokenizer
        let sentence = "昨日友達と映画を見に行きました"
        let tokens = app.tokenizer.tokenize(sentence)
        let surfaces = tokens.map(\.text)
        let hasParticle = tokens.contains { $0.text == "を" || $0.text == "と" }
        let hasMovie = tokens.contains { $0.lemma == "映画" }
        let covered = tokens.map(\.text).joined() == sentence
        checks.append(
            check(
                id: "tokenizer",
                title: "断词与助词识别",
                passed: tokens.count >= 5 && hasParticle && hasMovie && covered,
                detail: "\(tokens.count) 个词：\(surfaces.joined(separator: " / "))"
            )
        )

        // 5. Scheduler ladder
        var state = SchedulingState()
        let first = SpacedRepetition.review(state: state, familiarity: 1, rating: .good)
        state = first.state
        let firstMinutes = state.dueAt.timeIntervalSinceNow / 60
        let second = SpacedRepetition.review(state: state, familiarity: first.familiarity, rating: .good)
        let secondMinutes = second.state.dueAt.timeIntervalSinceNow / 60
        let third = SpacedRepetition.review(state: second.state, familiarity: second.familiarity, rating: .good)
        let graduatedDays = third.state.dueAt.timeIntervalSinceNow / 86_400
        let ladderOK = firstMinutes > 0.5 && firstMinutes < 2
            && secondMinutes > 8 && secondMinutes < 12
            && graduatedDays > 0.9 && graduatedDays < 1.1
        checks.append(
            check(
                id: "scheduler-ladder",
                title: "新卡学习阶梯",
                passed: ladderOK,
                detail: String(format: "%.0f 分 → %.0f 分 → %.1f 天", firstMinutes, secondMinutes, graduatedDays)
            )
        )

        // 6. Lapse behaviour
        var grown = SchedulingState()
        grown.intervalDays = 30
        grown.easeFactor = 2.5
        grown.reviewCount = 5
        let lapse = SpacedRepetition.review(state: grown, familiarity: 4, rating: .again)
        let lapseMinutes = lapse.state.dueAt.timeIntervalSinceNow / 60
        let lapseOK = lapse.state.intervalDays == 0
            && lapseMinutes < 2
            && lapse.state.easeFactor < 2.5
            && lapse.state.preLapseInterval != nil
        checks.append(
            check(
                id: "scheduler-lapse",
                title: "遗忘后回到学习阶段",
                passed: lapseOK,
                detail: String(format: "间隔 %.1f 天，ease %.2f", lapse.state.intervalDays, lapse.state.easeFactor)
            )
        )

        // 7. Interval growth
        var reviewState = SchedulingState()
        reviewState.intervalDays = 10
        reviewState.easeFactor = 2.5
        reviewState.reviewCount = 3
        let goodResult = SpacedRepetition.review(state: reviewState, familiarity: 4, rating: .good)
        let easyResult = SpacedRepetition.review(state: reviewState, familiarity: 4, rating: .easy)
        let growthOK = goodResult.state.intervalDays > 10
            && easyResult.state.intervalDays > goodResult.state.intervalDays
            && goodResult.state.intervalDays <= SpacedRepetition.intervalCapDays
        checks.append(
            check(
                id: "scheduler-growth",
                title: "间隔增长与封顶",
                passed: growthOK,
                detail: String(format: "记得 %.1f 天 / 简单 %.1f 天", goodResult.state.intervalDays, easyResult.state.intervalDays)
            )
        )

        // 8. Persistence round trip
        var snapshot = AppSnapshot()
        snapshot.words = app.words
        snapshot.profile = app.profile
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var roundTripOK = false
        if let data = try? encoder.encode(snapshot), let decoded = try? decoder.decode(AppSnapshot.self, from: data) {
            roundTripOK = decoded.words.count == snapshot.words.count
                && decoded.profile.level == snapshot.profile.level
        }
        checks.append(
            check(
                id: "persistence",
                title: "状态文件往返",
                passed: roundTripOK,
                detail: "生词 \(app.words.count) 个，分组 \(app.decks.count) 个"
            )
        )

        // 9. Storage writable
        let probe = app.store.mediaDirectory().appendingPathComponent("diagnostic-probe.txt")
        var storageOK = false
        do {
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            storageOK = FileManager.default.fileExists(atPath: probe.path)
            try? FileManager.default.removeItem(at: probe)
        } catch {
            storageOK = false
        }
        checks.append(
            check(id: "storage", title: "本地存储可写", passed: storageOK, detail: app.store.root.lastPathComponent)
        )

        // 10. Content library
        checks.append(
            check(
                id: "clips",
                title: "素材库",
                passed: !app.library.clips.isEmpty,
                detail: "\(app.library.clips.count) 条片段，其中自建 \(app.customClips.count) 条"
            )
        )

        return checks
    }

    private static func check(id: String, title: String, passed: Bool, detail: String) -> DiagnosticCheck {
        DiagnosticCheck(id: id, title: title, passed: passed, detail: detail)
    }
}
