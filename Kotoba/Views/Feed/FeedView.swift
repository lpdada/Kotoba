import SwiftUI

struct LookupRequest: Identifiable {
    let id = UUID()
    let token: ClipToken
    let sentence: String
    let clip: Clip?
}

struct FeedView: View {
    @EnvironmentObject private var app: AppModel
    @State private var feed: [Clip] = []
    @State private var currentID: String?
    @State private var lookup: LookupRequest?
    @State private var infoClip: Clip?
    @State private var showFilters = false

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black.ignoresSafeArea()

            if feed.isEmpty {
                EmptyStateView(
                    symbol: "film",
                    title: "素材库是空的",
                    message: "在「我的 › 内容管理」里导入你的片段清单，或先检查内置示例是否随包打入。",
                    actionTitle: "重新载入",
                    action: { reload() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.screenBackground)
            } else {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(feed) { clip in
                            ClipPageView(
                                clip: clip,
                                isActive: clip.id == activeClipID,
                                onLookup: { token, sentence in
                                    lookup = LookupRequest(token: token, sentence: sentence, clip: clip)
                                },
                                onInfo: { infoClip = clip }
                            )
                            .containerRelativeFrame([.horizontal, .vertical])
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollPosition(id: $currentID)
                .scrollIndicators(.hidden)
                .ignoresSafeArea()
            }

            filterButton
        }
        .task {
            if feed.isEmpty { reload() }
        }
        .sheet(item: $lookup) { request in
            WordLookupSheet(
                token: request.token,
                sentence: request.sentence,
                clip: request.clip
            )
            .environmentObject(app)
        }
        .sheet(item: $infoClip) { clip in
            ClipInfoSheet(clip: clip)
                .environmentObject(app)
        }
        .sheet(isPresented: $showFilters) {
            FeedFilterSheet(onApply: { reload() })
                .environmentObject(app)
        }
    }

    private var activeClipID: String? {
        currentID ?? feed.first?.id
    }

    private var filterButton: some View {
        Button {
            showFilters = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "slider.horizontal.3")
                    .font(Theme.font(size: 11, weight: .semibold))
                Text(app.profile.level.label)
                    .font(Theme.font(size: 11, weight: .bold, design: .rounded))
                Text("· \(app.profile.dailyGoalMinutes) 分钟目标")
                    .font(Theme.font(size: 11))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.black.opacity(0.32), in: Capsule())
            .foregroundStyle(.white.opacity(0.9))
        }
        .buttonStyle(.plain)
        .a11yButton(
            "推荐设置，当前等级 \(app.profile.level.label)，每天 \(app.profile.dailyGoalMinutes) 分钟",
            hint: "调整难度与兴趣标签，重新推荐片段"
        )
        .padding(.leading, 16)
        .padding(.bottom, 132)
    }

    private func reload() {
        feed = app.rankedFeed()
        if currentID == nil || !feed.contains(where: { $0.id == currentID }) {
            currentID = feed.first?.id
        }
    }
}

// MARK: - Feed filters

struct FeedFilterSheet: View {
    @EnvironmentObject private var app: AppModel
    @Environment(\.dismiss) private var dismiss
    var onApply: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    SectionHeader(title: "难度", subtitle: "推荐排序会优先贴近这个等级")
                    FlowChips(items: JLPTLevel.allCases.map(\.label), selected: [app.profile.level.label]) { label in
                        if let level = JLPTLevel.fromLabel(label) {
                            app.updateProfile { $0.level = level }
                        }
                    }

                    SectionHeader(title: "兴趣标签", subtitle: "可多选，影响片段排序")
                    FlowChips(items: UserProfile.interestCatalog, selected: app.profile.topics) { topic in
                        app.updateProfile { profile in
                            if let index = profile.topics.firstIndex(of: topic) {
                                profile.topics.remove(at: index)
                            } else {
                                profile.topics.append(topic)
                            }
                        }
                    }

                    SectionHeader(title: "播放", subtitle: nil)
                    Toggle("自动播放/朗读", isOn: Binding(
                        get: { app.profile.autoplayEnabled },
                        set: { value in app.updateProfile { $0.autoplayEnabled = value } }
                    ))
                    Toggle("循环片段", isOn: Binding(
                        get: { app.profile.loopClip },
                        set: { value in app.updateProfile { $0.loopClip = value } }
                    ))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("播放速度 \(String(format: "%.1fx", app.profile.playbackRate))")
                            .font(Theme.font(size: 12))
                            .foregroundStyle(Theme.secondaryText)
                        Slider(
                            value: Binding(
                                get: { app.profile.playbackRate },
                                set: { value in app.updateProfile { $0.playbackRate = value } }
                            ),
                            in: 0.5...1.5,
                            step: 0.05
                        )
                        .tint(Theme.accent)
                    }
                }
                .padding(18)
            }
            .background(Theme.screenBackground)
            .navigationTitle("推荐设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        onApply()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
