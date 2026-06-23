import SwiftUI

struct MainTabView: View {
    @EnvironmentObject var store: AppStore
    @State private var tab = 0

    var isAdmin: Bool { store.currentMember?.isAdmin ?? false }

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Theme.bg0).withAlphaComponent(0.92)
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $tab) {
            DrinksView(selectedTab: $tab)
                .tag(0)
                .tabItem { Label("Buchen", systemImage: "mug.fill") }

            MyBookingsView()
                .tag(1)
                .tabItem { Label("Meine", systemImage: "list.bullet.rectangle.fill") }

            if isAdmin {
                KassenwartView()
                    .tag(2)
                    .tabItem { Label("Kasse", systemImage: "eurosign.circle.fill") }
            }

            ProfileView()
                .tag(3)
                .tabItem { Label("Profil", systemImage: "person.crop.circle.fill") }
        }
        .tint(Theme.gold)
    }
}
