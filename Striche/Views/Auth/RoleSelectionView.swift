import SwiftUI

struct RoleSelectionView: View {
    @EnvironmentObject var store: AppStore
    @State private var showMemberLogin = false
    @State private var showAdminSetup = false
    @State private var logoTaps = 0
    @State private var eggTriggered = false

    var body: some View {
        NavigationStack {
            ZStack {
                AnimatedBackground()

                VStack(spacing: 36) {
                    Spacer()

                    // Logo / brand with hidden easter egg (tap 5x)
                    VStack(spacing: 16) {
                        Text("🍻")
                            .font(.system(size: 84))
                            .rotationEffect(.degrees(eggTriggered ? 360 : 0))
                            .scaleEffect(eggTriggered ? 1.3 : 1)
                            .animation(.spring(response: 0.6, dampingFraction: 0.5), value: eggTriggered)
                            .onTapGesture {
                                Haptics.tap()
                                logoTaps += 1
                                if logoTaps >= 5 {
                                    eggTriggered = true
                                    Haptics.success()
                                    SoundManager.shared.play(.sekt)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                                        eggTriggered = false; logoTaps = 0
                                    }
                                }
                            }
                        Text("Striche")
                            .font(.system(size: 40, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.goldGradient)
                        Text("Die digitale Strichliste für deinen Verein")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Spacer()

                    VStack(spacing: 14) {
                        Button {
                            Haptics.tap(); showMemberLogin = true
                        } label: {
                            roleLabel(icon: "person.fill", title: "Als Mitglied einloggen",
                                      subtitle: "Getränke buchen")
                        }
                        .buttonStyle(PrimaryButtonStyle())

                        Button {
                            Haptics.tap(); showAdminSetup = true
                        } label: {
                            roleLabel(icon: "crown.fill", title: "Als Administrator",
                                      subtitle: "Verein anlegen & verwalten")
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 36)
                }
            }
            .navigationDestination(isPresented: $showMemberLogin) { MemberLoginView() }
            .navigationDestination(isPresented: $showAdminSetup) { AdminSetupView() }
        }
        .onAppear { if store.pendingInviteCode != nil { showMemberLogin = true } }
        .onChange(of: store.pendingInviteCode) { _, new in
            if new != nil { showMemberLogin = true }
        }
    }

    private func roleLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .bold))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 12, weight: .medium, design: .rounded)).opacity(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
