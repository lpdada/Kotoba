import SwiftUI

struct RootView: View {
    @EnvironmentObject private var app: AppModel

    var body: some View {
        Group {
            if !app.isReady {
                SplashView(message: app.bootstrapMessage)
            } else if !app.profile.onboardingCompleted {
                OnboardingView()
            } else {
                MainTabView()
            }
        }
        .task {
            await app.bootstrap()
        }
    }
}

// MARK: - Splash

struct SplashView: View {
    let message: String

    var body: some View {
        ZStack {
            Theme.screenBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .fill(Theme.accent.opacity(0.12))
                        .frame(width: 96, height: 96)
                    Text("こ")
                        .scaledFont(44, relativeTo: .title, weight: .semibold, design: .serif)
                        .foregroundStyle(Theme.accent)
                }
                Text("Kotoba")
                    .font(Theme.font(size: 24, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.ink)
                Text(message)
                    .font(Theme.font(size: 13))
                    .foregroundStyle(Theme.secondaryText)
                ProgressView()
                    .tint(Theme.accent)
            }
        }
    }
}

// MARK: - Tabs

struct MainTabView: View {
    @EnvironmentObject private var app: AppModel
    @State private var selection: Tab = .feed

    enum Tab: Hashable {
        case feed, vocabulary, review, profile
    }

    var body: some View {
        TabView(selection: $selection) {
            FeedView()
                .tabItem { Label("片段", systemImage: "play.rectangle.fill") }
                .accessibilityLabel(Text("片段，滚动学习"))
                .tag(Tab.feed)

            VocabularyView()
                .tabItem { Label("生词", systemImage: "square.stack") }
                .accessibilityLabel(Text("生词本"))
                .tag(Tab.vocabulary)

            ReviewView(session: app.reviewSession)
                .tabItem { Label("复习", systemImage: "arrow.triangle.2.circlepath") }
                .badge(app.dueReviewCount())
                .accessibilityLabel(Text("复习，今天到期 \(app.dueReviewCount()) 张"))
                .tag(Tab.review)

            ProfileHomeView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
                .accessibilityLabel(Text("我的，设置与数据"))
                .tag(Tab.profile)
        }
        .tint(Theme.accent)
        .toast($app.toast)
    }
}
