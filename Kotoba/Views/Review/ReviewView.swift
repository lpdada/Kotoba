import SwiftUI

struct ReviewView: View {
    @ObservedObject var session: ReviewSessionModel
    @EnvironmentObject private var app: AppModel
    @State private var showBulkIntervalHelp = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.screenBackground.ignoresSafeArea()
                switch session.phase {
                case .reviewing:
                    sessionBody
                case .finished:
                    if session.queue.isEmpty {
                        overview
                    } else {
                        summary
                    }
                case .idle:
                    overview
                }
            }
            .navigationTitle("复习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if session.phase == .reviewing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("结束") {
                            session.end()
                        }
                        .font(Theme.font(size: 13, weight: .semibold))
                    }
                }
            }
        }
    }

    // MARK: Overview

    private var overview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                heroCard
                statsRow
                forecastCard
                queuePreview
                sentenceCardsSection
                if !showBulkIntervalHelp {
                    Button {
                        showBulkIntervalHelp = true
                    } label: {
                        Text("间隔是怎么算的？")
                            .font(Theme.font(size: 12))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("新卡先经过 1 分钟、10 分钟两个阶梯；毕业到 1 天，之后每次按难度系数（初始 2.5）放大间隔。评分「忘记」会回到学习阶段，并把系数下调 0.22；「记得 / 简单」会小幅上调系数并分别按 1.0x / 1.35x 放大。间隔上下浮动 5%，最长两年。")
                            .font(Theme.font(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                        Text("熟悉度（1–5）由当前间隔反推：<1天=生疏，<3天=眼熟，<7天=有印象，<21天=熟悉，≥21天=掌握。")
                            .font(Theme.font(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .card()
                }
            }
            .padding(18)
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(app.dueReviewCount())")
                        .scaledFont(46, relativeTo: .title, weight: .semibold, design: .rounded)
                        .foregroundStyle(Theme.ink)
                    Text("张卡片等待复习")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                ProgressRing(progress: app.goalProgress, size: 66, tint: Theme.accent)
                    .overlay(
                        Text("\(Int(app.minutesToday))分")
                            .font(Theme.font(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.accent)
                    )
            }

            if app.kanjiDueCount > 0 || !app.kanjiCards.isEmpty {
                Text("其中汉字卡 \(app.kanjiCards.count) 张，今天到期 \(app.kanjiDueCount) 张")
                    .font(Theme.font(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityLabel(Text("汉字卡 \(app.kanjiCards.count) 张，今天到期 \(app.kanjiDueCount) 张"))
            }

            PrimaryActionButton(
                title: app.dueReviewCount() > 0 ? "开始复习" : "先练习新词",
                systemImage: "play.fill",
                isEnabled: !app.words.isEmpty
            ) {
                session.start(includeNew: true)
            }

            if app.words.isEmpty {
                Text("生词本还是空的：先去片段里点几个词保存起来。")
                    .font(Theme.font(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .card()
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            StatTile(title: "连续天数", value: "\(app.streakDays)", caption: "每天至少 1 分钟", tint: Theme.amber)
            StatTile(title: "30 天记忆率", value: String(format: "%.0f%%", app.retention * 100), caption: "非「忘记」占比", tint: Theme.jade)
            StatTile(title: "新词库存", value: "\(app.newWordCount())", caption: "尚未复习", tint: Theme.lilac)
        }
    }

    private var forecastCard: some View {
        let forecast = app.reviewForecast(days: 7)
        let peak = max(forecast.map(\.due).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                SectionHeader(title: "未来 7 天", subtitle: "每天预计到期的卡片数")
                if app.overdueCount > 0 {
                    TagLabel(text: "逾期 \(app.overdueCount)", tint: Theme.rose)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(forecast) { day in
                    VStack(spacing: 4) {
                        Text("\(day.due)")
                            .font(Theme.font(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(day.due > 0 ? Theme.ink : Theme.secondaryText)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(day.isToday ? Theme.accent : Theme.accent.opacity(0.42))
                            .frame(height: max(CGFloat(day.due) / CGFloat(peak) * 72, 3))
                        Text(day.shortLabel)
                            .font(Theme.font(size: 9))
                            .foregroundStyle(day.isToday ? Theme.accent : Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(day.isToday ? "今天" : day.shortLabel))
                    .accessibilityValue(Text("\(day.due) 张到期"))
                }
            }
            .frame(height: 108, alignment: .bottom)

            Text("逾期卡片已并入今天；想降低压力就调小分组的「每日复习上限」。")
                .font(Theme.font(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .card()
    }

    private var queuePreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "接下来", subtitle: "按到期时间排序")
            if app.words.isEmpty {
                Text("没有排队中的词。").font(Theme.font(size: 12)).foregroundStyle(Theme.secondaryText).card()
            } else {
                VStack(spacing: 0) {
                    let upcoming = app.words
                        .filter { !$0.isIgnored }
                        .sorted { $0.scheduling.dueAt < $1.scheduling.dueAt }
                        .prefix(5)
                    ForEach(Array(upcoming)) { word in
                        HStack(spacing: 10) {
                            Text(word.word)
                                .font(Theme.font(size: 15, design: .serif))
                                .foregroundStyle(Theme.ink)
                            LevelBadge(level: word.level)
                            Spacer()
                            Text(word.scheduling.isNew ? "新词" : SpacedRepetition.describe(seconds: word.scheduling.dueAt.timeIntervalSinceNow) + "后")
                                .font(Theme.font(size: 10))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                    }
                }
                .card(padded: false)
            }
        }
    }

    private var sentenceCardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "整句卡片", subtitle: "\(app.sentenceCards.count) 张")
            if app.sentenceCards.isEmpty {
                Text("在片段里点「整句」把喜欢的对白存成卡片。")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(app.sentenceCards.prefix(4))) { card in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.text)
                                    .font(Theme.font(size: 14, design: .serif))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(2)
                                Text(card.translation)
                                    .font(Theme.font(size: 10))
                                    .foregroundStyle(Theme.secondaryText)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Button {
                                app.speech.speak(card.text, rate: app.profile.speechRate)
                            } label: {
                                Image(systemName: "speaker.wave.2")
                                    .foregroundStyle(Theme.accent)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                }
                .card(padded: false)
            }
        }
    }

    // MARK: Session

    private var sessionBody: some View {
        VStack(spacing: 16) {
            progressHeader
            Spacer(minLength: 0)
            cardSurface
            Spacer(minLength: 0)
            if session.isFlipped {
                ratingBar
            } else {
                flipButton
            }
            footerControls
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var progressHeader: some View {
        VStack(spacing: 6) {
            HStack {
                Text("\(session.index + 1) / \(session.queue.count)")
                    .font(Theme.font(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.secondaryText)
                Spacer()
                if let word = session.word {
                    LevelBadge(level: word.level)
                } else if let kanji = session.kanjiCard {
                    TagLabel(text: "汉字 \(kanji.literal)", tint: Theme.lilac)
                } else {
                    TagLabel(text: "整句")
                }
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairline)
                    Capsule()
                        .fill(Theme.accent)
                        .frame(width: max(geometry.size.width * session.progress, 4))
                }
            }
            .frame(height: 5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("复习进度"))
        .accessibilityValue(Text("第 \(min(session.index + 1, max(session.queue.count, 1))) 张，共 \(session.queue.count) 张"))
    }

    private var cardSurface: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Theme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.05), radius: 14, y: 8)

            FlashcardFace(
                word: session.word,
                sentence: session.sentence,
                isFlipped: session.isFlipped,
                furiganaEnabled: app.profile.furiganaEnabled,
                speechRate: app.profile.speechRate,
                onSpeak: { text in
                    app.speech.speak(text, rate: app.profile.speechRate)
                }
            )
            .padding(20)
        }
        .frame(maxHeight: 420)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.85), value: session.isFlipped)
        .onTapGesture {
            session.flip()
        }
    }

    private var flipButton: some View {
        PrimaryActionButton(title: "显示答案", systemImage: "arrow.triangle.2.circlepath") {
            session.flip()
        }
    }

    private var ratingBar: some View {
        HStack(spacing: 8) {
            ForEach(ReviewRating.allCases) { rating in
                Button {
                    session.rate(rating)
                } label: {
                    VStack(spacing: 4) {
                        Text(rating.title)
                            .font(Theme.font(size: 14, weight: .semibold))
                        Text(previewText(for: rating))
                            .font(Theme.font(size: 9))
                            .foregroundStyle(Theme.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        Theme.ratingColor(rating).opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .foregroundStyle(Theme.ratingColor(rating))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("评分：\(rating.title)"))
                .accessibilityHint(Text("\(rating.hint)，下次约 \(previewText(for: rating))后"))
            }
        }
    }

    private var footerControls: some View {
        HStack {
            Button {
                session.undo()
            } label: {
                Label("撤销", systemImage: "arrow.uturn.backward")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(session.logs.isEmpty ? Theme.secondaryText.opacity(0.4) : Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(session.logs.isEmpty)
            .accessibilityLabel(Text("撤销上一次评分"))
            .accessibilityHint(Text(session.logs.isEmpty ? "还没有评分" : "把上一张卡放回队列并还原状态"))

            Spacer()

            Text("记住 \(session.goodCount) ・ 忘记 \(session.againCount)")
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 4)
    }

    private func previewText(for rating: ReviewRating) -> String {
        if let word = session.word {
            return SpacedRepetition.previewInterval(state: word.scheduling, rating: rating)
        }
        if let sentence = session.sentence {
            return SpacedRepetition.previewInterval(state: sentence.scheduling, rating: rating)
        }
        if let kanji = session.kanjiCard {
            return SpacedRepetition.previewInterval(state: kanji.scheduling, rating: rating)
        }
        return ""
    }

    // MARK: Summary

    private var summary: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("这一轮完成了")
                        .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text("用时 \(Int(session.elapsed / 60)) 分 \(Int(session.elapsed.truncatingRemainder(dividingBy: 60))) 秒")
                        .font(Theme.font(size: 12))
                        .foregroundStyle(Theme.secondaryText)
                }
                .card()

                HStack(spacing: 8) {
                    StatTile(title: "评分次数", value: "\(session.logs.count)", caption: nil, tint: Theme.accent)
                    StatTile(
                        title: "记忆率",
                        value: String(format: "%.0f%%", session.accuracy * 100),
                        caption: "记得 + 简单",
                        tint: Theme.jade
                    )
                    StatTile(title: "忘记", value: "\(session.againCount)", caption: "会重新排队", tint: Theme.rose)
                }

                PrimaryActionButton(title: "再练一轮", systemImage: "arrow.clockwise") {
                    session.restart()
                }
                SecondaryActionButton(title: "回到概览", systemImage: "list.bullet") {
                    session.reset()
                }
            }
            .padding(18)
        }
    }
}
