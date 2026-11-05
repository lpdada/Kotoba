import Foundation

// MARK: - Scheduling state

/// Everything the scheduler needs to keep about one reviewable item.
struct SchedulingState: Codable, Hashable {
    var easeFactor: Double = 2.5
    var intervalDays: Double = 0
    var learningStep: Int = 0
    var preLapseInterval: Double?
    var dueAt: Date = Date()
    var reviewCount: Int = 0
    var lapseCount: Int = 0
    var lastReviewedAt: Date?

    var isNew: Bool { reviewCount == 0 }
    var isLearning: Bool { intervalDays < 1 }

    func isDue(at date: Date = Date()) -> Bool { dueAt <= date }

    /// 0 ... 1 progress inside the current interval.
    func progress(at date: Date = Date()) -> Double {
        guard let last = lastReviewedAt else { return 1 }
        let total = dueAt.timeIntervalSince(last)
        guard total > 0 else { return 1 }
        return min(max(date.timeIntervalSince(last) / total, 0), 1)
    }
}

// MARK: - Rating

enum ReviewRating: String, Codable, CaseIterable, Identifiable {
    case again, hard, good, easy

    var id: String { rawValue }

    var title: String {
        switch self {
        case .again: return "忘记"
        case .hard: return "困难"
        case .good: return "记得"
        case .easy: return "简单"
        }
    }

    var hint: String {
        switch self {
        case .again: return "重新学习"
        case .hard: return "勉强想起"
        case .good: return "正常想起"
        case .easy: return "脱口而出"
        }
    }

    var keyboardKey: String {
        switch self {
        case .again: return "1"
        case .hard: return "2"
        case .good: return "3"
        case .easy: return "4"
        }
    }
}

// MARK: - Scheduler

/// A compact SM-2 family scheduler tuned for many very short sessions.
///
/// Design decisions (independent of any other app):
/// * New cards walk a two step ladder (1 min, 10 min) before graduating.
/// * A graduation lands on 1 day; `easy` graduates straight to 4 days.
/// * Review cards multiply their interval by the ease factor (2.5 by default).
/// * `hard` grows the interval only 1.2x and slightly lowers ease,
///   `easy` grows 1.35x on top of ease, `again` is a lapse.
/// * Intervals are fuzzed by ±5% so cards don't pile up on the same day,
///   and are capped at two years.
/// * Familiarity (1...5) is derived from the interval, so the vocabulary list
///   reflects real retention instead of a separate counter.
enum SpacedRepetition {
    static let learningStepsMinutes: [Double] = [1, 10]
    static let graduatingIntervalDays: Double = 1
    static let easyIntervalDays: Double = 4
    static let minimumEase: Double = 1.3
    static let maximumEase: Double = 2.8
    static let easeBonus: Double = 0.08
    static let easyEaseBonus: Double = 0.14
    static let easePenalty: Double = 0.22
    static let hardEasePenalty: Double = 0.12
    static let hardGrowth: Double = 1.2
    static let easyGrowth: Double = 1.35
    static let intervalCapDays: Double = 730
    static let fuzzFraction: Double = 0.05

    struct Result {
        let state: SchedulingState
        let familiarity: Int
    }

    // MARK: Public API

    static func review(
        state: SchedulingState,
        familiarity: Int,
        rating: ReviewRating,
        now: Date = Date(),
        random: inout Double
    ) -> Result {
        var next = state
        next.reviewCount += 1
        next.lastReviewedAt = now

        switch rating {
        case .again:
            next.lapseCount += 1
            next.preLapseInterval = max(state.preLapseInterval ?? state.intervalDays, graduatingIntervalDays)
            next.intervalDays = 0
            next.learningStep = 0
            next.easeFactor = max(minimumEase, state.easeFactor - easePenalty)
            next.dueAt = now.addingTimeInterval(learningStepsMinutes[0] * 60)

        case .hard, .good, .easy:
            if state.intervalDays < graduatingIntervalDays {
                advanceLearning(&next, from: state, rating: rating, now: now)
            } else {
                advanceReview(&next, from: state, rating: rating, now: now, random: &random)
            }
        }

        let derived = familiarityLevel(forIntervalDays: next.intervalDays)
        let clamped = min(max(derived, 1), 5)
        return Result(state: next, familiarity: clamped)
    }

    /// Convenience overload for callers that do not care about the fuzz source.
    static func review(
        state: SchedulingState,
        familiarity: Int,
        rating: ReviewRating,
        now: Date = Date()
    ) -> Result {
        var random = Double.random(in: 0...1)
        return review(state: state, familiarity: familiarity, rating: rating, now: now, random: &random)
    }

    /// Human readable interval that `rating` would produce, e.g. "约 10 分钟".
    static func previewInterval(
        state: SchedulingState,
        rating: ReviewRating,
        now: Date = Date()
    ) -> String {
        let result = review(state: state, familiarity: 1, rating: rating, now: now)
        let seconds = result.state.dueAt.timeIntervalSince(now)
        return "约 " + describe(seconds: seconds)
    }

    static func describe(seconds: TimeInterval) -> String {
        let minutes = seconds / 60
        if minutes < 1 { return "不到 1 分钟" }
        if minutes < 60 { return "\(Int(minutes.rounded())) 分钟" }
        let hours = minutes / 60
        if hours < 24 { return "\(Int(hours.rounded())) 小时" }
        let days = seconds / 86_400
        if days < 1.5 { return "1 天" }
        if days < 30 { return "\(Int(days.rounded())) 天" }
        if days < 365 { return "\(Int((days / 30).rounded())) 个月" }
        return "\(Int((days / 365).rounded())) 年"
    }

    static func familiarityLevel(forIntervalDays days: Double) -> Int {
        switch days {
        case ..<0.5: return 1
        case ..<3: return 2
        case ..<7: return 3
        case ..<21: return 4
        default: return 5
        }
    }

    static func familiarityTitle(_ level: Int) -> String {
        switch level {
        case 1: return "生疏"
        case 2: return "眼熟"
        case 3: return "有印象"
        case 4: return "熟悉"
        default: return "掌握"
        }
    }

    // MARK: Internals

    private static func advanceLearning(
        _ next: inout SchedulingState,
        from state: SchedulingState,
        rating: ReviewRating,
        now: Date
    ) {
        // `learningStep` counts how many ladder rungs are already done:
        // 0 = brand new, 1 = sat the 1 minute rung, 2 = ready to graduate.
        let steps = learningStepsMinutes
        var completed = state.learningStep

        switch rating {
        case .again:
            completed = 0
        case .hard:
            completed = max(completed, 1)
        case .good:
            break
        case .easy:
            completed = steps.count
        }

        if completed < steps.count {
            next.learningStep = completed + 1
            next.intervalDays = 0
            next.dueAt = now.addingTimeInterval(steps[completed] * 60)
            return
        }

        // Graduation.
        next.learningStep = 0
        var interval: Double
        switch rating {
        case .easy:
            interval = easyIntervalDays
        case .hard:
            interval = max(graduatingIntervalDays, (state.preLapseInterval ?? graduatingIntervalDays) * 0.5)
        case .good, .again:
            interval = max(graduatingIntervalDays, state.preLapseInterval ?? graduatingIntervalDays)
        }
        if rating != .easy, state.reviewCount > 1 {
            interval = max(interval, state.preLapseInterval ?? interval)
        }
        interval = min(interval, intervalCapDays)
        next.intervalDays = interval
        next.preLapseInterval = nil
        next.dueAt = now.addingTimeInterval(interval * 86_400)
    }

    private static func advanceReview(
        _ next: inout SchedulingState,
        from state: SchedulingState,
        rating: ReviewRating,
        now: Date,
        random: inout Double
    ) {
        var growth: Double
        switch rating {
        case .hard:
            growth = hardGrowth
            next.easeFactor = max(minimumEase, state.easeFactor - hardEasePenalty)
        case .good:
            growth = state.easeFactor
            next.easeFactor = min(maximumEase, state.easeFactor + easeBonus)
        case .easy:
            growth = state.easeFactor * easyGrowth
            next.easeFactor = min(maximumEase, state.easeFactor + easyEaseBonus)
        case .again:
            growth = 1
        }

        var interval = state.intervalDays * growth
        interval = max(interval, state.intervalDays + 1)
        interval = fuzz(interval, random: &random)
        interval = min(max(interval, graduatingIntervalDays), intervalCapDays)
        next.intervalDays = interval
        next.learningStep = 0
        next.preLapseInterval = nil
        next.dueAt = now.addingTimeInterval(interval * 86_400)
    }

    private static func fuzz(_ days: Double, random: inout Double) -> Double {
        let factor = 1 + (random * 2 - 1) * fuzzFraction
        let value = (days * factor * 10).rounded() / 10
        return max(graduatingIntervalDays, value)
    }
}
