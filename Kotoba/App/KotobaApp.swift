import SwiftUI

@main
struct KotobaApp: App {
    @StateObject private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .tint(Theme.accent)
        }
    }
}
