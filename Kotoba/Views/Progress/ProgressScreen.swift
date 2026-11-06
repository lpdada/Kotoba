import SwiftUI

struct ProgressScreen: View {
    @EnvironmentObject private var app: AppModel
    @State private var range = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                streakCard
                heatmapCard
                distributionCard
                kanjiStatsCard
                grammarStatsCard
                totalsCard
                historyCard
                dictionaryCard
            }
            .padding(18)
        }
        .background(Theme.screenBackground)
        .navigationTitle("学习数据")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var streakCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(app.streakDays)")
                        .scaledFont(44, relativeTo: .title, weight: .semibold, design: .rounded)
                        .foregroundStyle(Theme.ink)
                    Text("连续学习天数")
                        .font(Theme.font(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "flame.fill")
                    .font(Theme.font(size: 26))
                    .foregroundStyle(Theme.amber.opacity(0.85))
            }
            HStack(spacing: 6) {
                ForEach(app.activityRange(days: 7), id: \.dayKey) { day in
                    VStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.minutes >= 1 ? Theme.accent : Theme.cardMuted)
                            .frame(height: 26)
                        Text(shortLabel(day.dayKey))
                            .font(Theme.font(size: 9))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(shortLabel(day.dayKey)))
                    .accessibilityValue(Text("\(Int(day.minutes)) 分钟"))
                }
            }
        }
        .card()
    }

    private var heatmapCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionHeader(title: "最近 30 天", subtitle: "颜色越深，当天学习越久")
                Picker("", selection: $range) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("90").tag(90)
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
            }
            ActivityHeatmap(
                activities: app.activityRange(days: range),
                goalMinutes: Double(app.profile.dailyGoalMinutes)
            )
            HStack(spacing: 6) {
                Text("少")
                    .font(Theme.font(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                ForEach(0..<4, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.accent.opacity([0.22, 0.45, 0.7, 1.0][index]))
                        .frame(width: 14, height: 8)
                }
                Text("多")
                    .font(Theme.font(size: 9))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                Text("今天 \(Int(app.minutesToday)) 分钟")
                    .font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private var distributionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "熟悉度分布", subtitle: "由间隔反推，不是手动打勾")
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(1...5, id: \.self) { level in
                    let count = app.familiarityCounts[level] ?? 0
                    let maxCount = max(app.familiarityCounts.values.max() ?? 1, 1)
                    VStack(spacing: 5) {
                        Text("\(count)")
                            .font(Theme.font(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.secondaryText)
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Theme.familiarityColor(level))
                            .frame(height: max(CGFloat(count) / CGFloat(maxCount) * 90, 3))
                        Text(SpacedRepetition.familiarityTitle(level))
                            .font(Theme.font(size: 9))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("\(SpacedRepetition.familiarityTitle(level)) \(count) 个"))
                }
            }
            .frame(height: 130)
        }
        .card()
    }

    private var kanjiStatsCard: some View {
        let stats = app.kanjiLevelStats
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "汉字",
                subtitle: "共 \(app.kanji.count) 字 ・ 复习中 \(app.kanjiCards.count) ・ 已熟悉 \(app.kanjiLearnedCount)"
            )
            VStack(spacing: 8) {
                ForEach(stats) { stat in
                    HStack(spacing: 8) {
                        Text(stat.label)
                            .font(Theme.font(size: 11, weight: .medium))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 44, alignment: .leading)
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.hairline)
                                Capsule()
                                    .fill(Theme.accent)
                                    .frame(width: max(geometry.size.width * ratio(stat), 3))
                            }
                        }
                        .frame(height: 6)
                        .accessibilityHidden(true)
                        Text("\(stat.learned)/\(stat.total)")
                            .font(Theme.font(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.secondaryText)
                            .frame(width: 62, alignment: .trailing)
                    }
                }
            }
            if app.kanjiCards.isEmpty {
                Text("生词页点「汉字」进入汉字表，挑几个字加入复习，它们会和生词一起排队。")
                    .font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func ratio(_ stat: KanjiLevelStat) -> Double {
        guard stat.total > 0 else { return 0 }
        return min(Double(stat.learned) / Double(stat.total), 1)
    }

    private var grammarStatsCard: some View {
        let learned = app.grammar.counts(for: .learned)
        let learning = app.grammar.counts(for: .learning)
        let total = app.grammar.entries.count
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(
                title: "语法",
                subtitle: total > 0
                    ? "共 \(total) 条 ・ 学习中 \(learning) ・ 已学会 \(learned)"
                    : "语法表尚未载入"
            )
            HStack(spacing: 8) {
                StatTile(
                    title: "已学会",
                    value: "\(learned)",
                    caption: "手动标记",
                    tint: Theme.jade
                )
                StatTile(
                    title: "学习中",
                    value: "\(learning)",
                    caption: "待复习",
                    tint: Theme.amber
                )
                StatTile(
                    title: "未标记",
                    value: "\(max(total - learned - learning, 0))",
                    caption: "还没看",
                    tint: Theme.secondaryText
                )
            }
            if total > 0 && learned + learning == 0 {
                Text("个人页点「语法」浏览句型，在详情里标记「学习中 / 已学会」，这里就会开始累计。")
                    .font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .a11yCombine("语法：共 \(total) 条，学习中 \(learning)，已学会 \(learned)")
    }

    private var totalsCard: some View {
        let totals = app.activity.values.reduce(into: (seconds: 0.0, reviews: 0, again: 0, clips: 0)) { partial, entry in
            partial.seconds += entry.studiedSeconds
            partial.reviews += entry.reviews
            partial.again += entry.againCount
            partial.clips += entry.clipsWatched
        }
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "累计", subtitle: nil)
            HStack(spacing: 8) {
                StatTile(title: "总时长", value: "\(Int(totals.seconds / 60)) 分", caption: "所有片段与复习", tint: Theme.accent)
                StatTile(title: "评分次数", value: "\(totals.reviews)", caption: "含忘记 \(totals.again)", tint: Theme.lilac)
                StatTile(title: "看完片段", value: "\(totals.clips)", caption: "≥60% 进度", tint: Theme.jade)
            }
        }
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "最近观看", subtitle: "\(app.watchHistory.count) 条记录")
            if app.watchHistory.isEmpty {
                Text("还没有观看记录。")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.watchHistory.suffix(8).reversed())) { record in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(app.library.clip(id: record.clipID)?.title ?? record.clipID)
                                    .font(Theme.font(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(record.watchedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(Theme.font(size: 9))
                                    .foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Text("\(Int(record.seconds))s")
                                .font(Theme.font(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                    }
                }
                .card(padded: false)
            }
        }
    }

    private var dictionaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "词典覆盖", subtitle: "内置 \(app.dictionary.entries.count) 条")
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(JLPTLevel.allCases, id: \.self) { level in
                    let count = app.dictionary.levelCounts[level] ?? 0
                    VStack(spacing: 3) {
                        Text("\(count)")
                            .font(Theme.font(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.levelColor(level))
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.levelColor(level).opacity(0.75))
                            .frame(height: 26)
                        Text(level.label)
                            .font(Theme.font(size: 9))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .card()
    }

    private func shortLabel(_ key: String) -> String {
        guard let date = DayKey.date(from: key) else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "EE"
        return formatter.string(from: date)
    }
}
