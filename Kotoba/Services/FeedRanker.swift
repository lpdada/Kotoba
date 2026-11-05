import Foundation

/// Orders the feed for one learner.
///
/// The ranking is deliberately explainable: level fit, interest match, novelty,
/// and a small random jitter so the order differs between sessions.
struct FeedRanker {
    struct Context {
        let profile: UserProfile
        let metrics: [String: ClipMetrics]
        let watchCounts: [String: Int]
        let savedClipIDs: Set<String>
        let knownLemmas: Set<String>
    }

    struct Score {
        let clip: Clip
        let total: Double
        let reasons: [String]
    }

    static func evaluate(_ clip: Clip, context: Context) -> Score {
        var total = 0.0
        var reasons: [String] = []

        let clipRank = (context.metrics[clip.id]?.level ?? clip.level ?? .n3).rank
        let userRank = context.profile.level.rank
        let distance = abs(Double(clipRank - userRank))
        let levelScore = max(0, 3.2 - distance * 1.1)
        total += levelScore
        if distance == 0 { reasons.append("难度正好") }
        if distance >= 2 { total -= 0.8 }

        if !context.profile.topics.isEmpty {
            let matches = Set(clip.topics).intersection(context.profile.topics).count
            if matches > 0 {
                total += min(Double(matches) * 1.4, 2.8)
                reasons.append("兴趣匹配")
            }
        }

        let watched = context.watchCounts[clip.id] ?? 0
        if watched == 0 {
            total += 1.8
            reasons.append("未看过")
        } else {
            total -= min(Double(watched) * 0.7, 2.1)
        }

        if context.savedClipIDs.contains(clip.id) {
            total -= 0.6
        }

        let unknownRatio = context.metrics[clip.id]?.unknownRatio ?? 0
        if unknownRatio > 0.45 { total -= 1.2; reasons.append("生词偏多") }
        if unknownRatio < 0.12 { total += 0.5 }

        if clip.custom { total += 0.4 }

        total += Double.random(in: -0.35...0.35)
        return Score(clip: clip, total: total, reasons: reasons)
    }

    static func ranked(_ clips: [Clip], context: Context) -> [Clip] {
        clips
            .map { evaluate($0, context: context) }
            .sorted { $0.total > $1.total }
            .map(\.clip)
    }

    static func ranked(_ clips: [Clip], context: Context, limit: Int) -> [Clip] {
        Array(ranked(clips, context: context).prefix(limit))
    }
}
