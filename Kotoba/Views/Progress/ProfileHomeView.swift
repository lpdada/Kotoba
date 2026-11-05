import SwiftUI

struct ProfileHomeView: View {
    @EnvironmentObject private var app: AppModel
    @State private var showResetConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    profileCard
                    statsGrid
                    achievementsSection
                    menuSection
                    footerNote
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var profileCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Theme.accent.opacity(0.14))
                        .frame(width: 52, height: 52)
                    Text(String(app.profile.displayName.prefix(1)))
                        .font(.system(size: 22, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.profile.displayName)
                        .font(.system(size: 18, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.ink)
                    Text(app.profile.goalSummary)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                LevelBadge(level: app.profile.level)
            }

            HStack(spacing: 8) {
                ProgressRing(progress: app.goalProgress, size: 54, tint: Theme.jade)
                    .overlay(
                        Text("\(Int(app.goalProgress * 100))%")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.jade)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天 \(Int(app.minutesToday)) / \(app.profile.dailyGoalMinutes) 分钟")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.ink)
                    Text("连续 \(app.streakDays) 天 ・ 观看 \(app.watchHistory.count) 次 ・ 生词 \(app.words.count) 个")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
        }
        .card()
    }

    private var statsGrid: some View {
        HStack(spacing: 8) {
            StatTile(
                title: "记忆率",
                value: String(format: "%.0f%%", app.retention * 100),
                caption: "近 30 天",
                tint: Theme.jade
            )
            StatTile(
                title: "待复习",
                value: "\(app.dueReviewCount())",
                caption: "现在到期",
                tint: Theme.rose
            )
            StatTile(
                title: "整句卡片",
                value: "\(app.sentenceCards.count)",
                caption: "从片段保存",
                tint: Theme.lilac
            )
        }
    }

    private var achievementsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "成就", subtitle: "都是本地计算，不上传")
            VStack(spacing: 0) {
                ForEach(Array(app.achievements.enumerated()), id: \.element.id) { index, achievement in
                    HStack(spacing: 12) {
                        Image(systemName: achievement.symbol)
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 30, height: 30)
                            .background(
                                (achievement.isUnlocked ? Theme.accent : Theme.secondaryText).opacity(0.12),
                                in: Circle()
                            )
                            .foregroundStyle(achievement.isUnlocked ? Theme.accent : Theme.secondaryText)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(achievement.title)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(achievement.isUnlocked ? Theme.ink : Theme.secondaryText)
                            Text(achievement.detail)
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.secondaryText)
                        }
                        Spacer()
                        Text(achievement.progressText)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(achievement.isUnlocked ? Theme.jade : Theme.secondaryText)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    if index < app.achievements.count - 1 {
                        Hairline().padding(.leading, 56)
                    }
                }
            }
            .card(padded: false)
        }
    }

    private var menuSection: some View {
        VStack(spacing: 0) {
            menuRow(icon: "chart.bar.xaxis", title: "学习数据") {
                ProgressScreen()
            }
            Hairline().padding(.leading, 48)
            menuRow(icon: "film.stack", title: "内容管理") {
                ClipImporterView()
            }
            Hairline().padding(.leading, 48)
            menuRow(icon: "gearshape", title: "设置") {
                SettingsView()
            }
            Hairline().padding(.leading, 48)
            menuRow(icon: "stethoscope", title: "自检") {
                DiagnosticsView()
            }
        }
        .card(padded: false)
    }

    private func menuRow<Destination: View>(
        icon: String,
        title: String,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink(destination: destination()) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 22)
                    .foregroundStyle(Theme.accent)
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footerNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kotoba 1.0 ・ 个人学习工具")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.secondaryText)
            Text("所有学习记录只存在这台设备上。片段时间轴与字幕为你自行导入的内容，应用本身不附带任何影视素材。")
                .font(.system(size: 10))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.top, 4)
    }
}
