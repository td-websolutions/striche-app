import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: AppStore

    var body: some View {
        Group {
            if !store.data.didOnboard {
                OnboardingView()
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            } else if store.isLoggedIn {
                MainTabView()
                    .transition(.opacity)
            } else {
                RoleSelectionView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.45), value: store.data.didOnboard)
        .animation(.smooth(duration: 0.45), value: store.isLoggedIn)
    }
}
