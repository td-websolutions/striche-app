import SwiftUI

@main
struct StricheApp: App {
    @StateObject private var store = AppStore()

    init() {
        // Force dark, premium look everywhere.
        UINavigationBar.appearance().tintColor = UIColor(Theme.gold)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .onOpenURL { url in
                    store.handleInviteURL(url)
                }
        }
    }
}
