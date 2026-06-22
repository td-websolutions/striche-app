import SwiftUI

@main
struct StricheApp: App {
    @StateObject private var store: AppStore
    @StateObject private var backend: BackendSession
    @StateObject private var sync: SyncEngine
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Force dark, premium look everywhere.
        UINavigationBar.appearance().tintColor = UIColor(Theme.gold)

        let store = AppStore()
        let backend = BackendSession()
        _store = StateObject(wrappedValue: store)
        _backend = StateObject(wrappedValue: backend)
        _sync = StateObject(wrappedValue: SyncEngine(store: store, backend: backend))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(backend)
                .environmentObject(sync)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
                .onOpenURL { url in
                    store.handleInviteURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    // Universal Links (https://striche-app.de/join?code=...) arrive here.
                    if let url = activity.webpageURL { store.handleInviteURL(url) }
                }
                .task {
                    // Validate/refresh any stored backend token on launch, then push.
                    await backend.restore()
                    await sync.sync()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { sync.syncNow() }
                }
        }
    }
}
