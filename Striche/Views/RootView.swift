import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if !store.data.didOnboard {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            } else if store.isLoggedIn {
                if store.myClubs.isEmpty {
                    NoClubView()
                        .transition(.opacity)
                } else if store.club == nil {
                    ClubPickerView()
                        .transition(.opacity)
                } else {
                    MainTabView()
                        .transition(.opacity)
                }
            } else {
                RoleSelectionView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: store.data.didOnboard)
        .animation(.smooth(duration: 0.45), value: store.isLoggedIn)
        .animation(.smooth(duration: 0.45), value: store.club != nil)
        .animation(.smooth(duration: 0.45), value: store.myClubs.count)
        .onAppear { store.autoSelectClubIfSingle() }
        .onChange(of: store.myClubs.map(\.id)) { _, _ in store.autoSelectClubIfSingle() }
    }
}
