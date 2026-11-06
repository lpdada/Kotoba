import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var app: AppModel
    @State private var step = 0

    private let minutesOptions = [5, 10, 20, 30]
    private let newWordOptions = [5, 8, 12, 20]

    var body: some View {
        ZStack {
            Theme.screenBackground.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        switch step {
                        case 0: levelStep
                        case 1: goalStep
                        default: interestStep
                        }
                    }
                    .padding(20)
                }
                footer
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Kotoba")
                    .font(Theme.font(size: 15, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("第 \(step + 1) / 3 步")
                    .font(Theme.font(size: 12))
                    .foregroundStyle(Theme.secondaryText)
            }
            HStack(spacing: 6) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index <= step ? Theme.accent : Theme.hairline)
                        .frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: Steps

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("先从你的日语水平开始")
                .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("我会按这个水平推荐片段与生词难度，之后在设置里随时能改。")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.secondaryText)

            VStack(spacing: 8) {
                ForEach(JLPTLevel.allCases, id: \.self) { level in
                    Button {
                        app.updateProfile { $0.level = level }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            LevelBadge(level: level)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(level.title)
                                    .font(Theme.font(size: 15, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Text(level.summary)
                                    .font(Theme.font(size: 12))
                                    .foregroundStyle(Theme.secondaryText)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer()
                            if app.profile.level == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(12)
                        .background(
                            app.profile.level == level ? Theme.accentSoft : Theme.card,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(app.profile.level == level ? Theme.accent.opacity(0.4) : Theme.hairline, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("每天想花多少时间？")
                .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("短视频学习的关键是频率而不是时长，10 分钟往往比周末补两小时更有效。")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.secondaryText)

            VStack(alignment: .leading, spacing: 8) {
                Text("每日目标")
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 8) {
                    ForEach(minutesOptions, id: \.self) { value in
                        Chip(
                            text: "\(value) 分钟",
                            isSelected: app.profile.dailyGoalMinutes == value
                        ) {
                            app.updateProfile { $0.dailyGoalMinutes = value }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("每天引入新词")
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 8) {
                    ForEach(newWordOptions, id: \.self) { value in
                        Chip(
                            text: "\(value) 个",
                            isSelected: app.profile.dailyNewWords == value
                        ) {
                            app.updateProfile {
                                $0.dailyNewWords = value
                                $0.dailyReviewLimit = max(value * 6, 30)
                            }
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("字幕显示")
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Toggle("显示振假名", isOn: Binding(
                    get: { app.profile.furiganaEnabled },
                    set: { value in app.updateProfile { $0.furiganaEnabled = value } }
                ))
                .font(Theme.font(size: 13))
                Toggle("显示罗马字", isOn: Binding(
                    get: { app.profile.romajiEnabled },
                    set: { value in app.updateProfile { $0.romajiEnabled = value } }
                ))
                .font(Theme.font(size: 13))
            }
            .tint(Theme.accent)
        }
    }

    private var interestStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("想看哪类素材？")
                .font(Theme.font(size: 22, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.ink)
            Text("只影响推荐排序。之后导入自己的片段也能自定义标签。")
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.secondaryText)

            FlowChips(
                items: UserProfile.interestCatalog,
                selected: app.profile.topics
            ) { topic in
                app.updateProfile { profile in
                    if let index = profile.topics.firstIndex(of: topic) {
                        profile.topics.remove(at: index)
                    } else {
                        profile.topics.append(topic)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("音频朗读速度")
                    .font(Theme.font(size: 12, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                HStack(spacing: 8) {
                    ForEach([0.35, 0.45, 0.55], id: \.self) { rate in
                        Chip(
                            text: rate < 0.4 ? "慢" : (rate < 0.5 ? "标准" : "偏快"),
                            isSelected: abs(app.profile.speechRate - rate) < 0.01
                        ) {
                            app.updateProfile { $0.speechRate = rate }
                        }
                    }
                }
            }
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            PrimaryActionButton(
                title: step < 2 ? "下一步" : "开始学习",
                systemImage: step < 2 ? "arrow.right" : "play.fill"
            ) {
                if step < 2 {
                    withAnimation(.easeInOut(duration: 0.2)) { step += 1 }
                } else {
                    app.updateProfile { $0.onboardingCompleted = true }
                    app.flushSave()
                }
            }
            if step > 0 {
                Button("返回上一步") {
                    withAnimation(.easeInOut(duration: 0.2)) { step -= 1 }
                }
                .font(Theme.font(size: 13))
                .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.screenBackground)
    }
}

// MARK: - Wrap chips

struct FlowChips: View {
    let items: [String]
    let selected: [String]
    let onToggle: (String) -> Void

    var body: some View {
        TokenFlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(items, id: \.self) { item in
                Chip(text: item, isSelected: selected.contains(item)) {
                    onToggle(item)
                }
            }
        }
    }
}
