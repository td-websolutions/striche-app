import SwiftUI

// MARK: - Club chooser
//
// Shown after login when the logged-in person belongs to MORE THAN ONE Verein
// (e.g. Tennis + Sportverein). Picking a club sets it as the active one and
// RootView swaps in the booking view. A single-club user never sees this –
// RootView auto-selects (see AppStore.autoSelectClubIfSingle).

struct ClubPickerView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession

    var body: some View {
        ZStack {
            AnimatedBackground()
            ScrollView {
                VStack(spacing: 22) {
                    header

                    VStack(spacing: 14) {
                        ForEach(store.myClubs) { club in
                            Button { select(club) } label: { clubRow(club) }
                                .buttonStyle(.plain)
                        }
                    }

                    Button("Abmelden") { logout() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 6)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("🍻").font(.system(size: 56))
            Text("Welcher Verein?")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Du bist in mehreren Vereinen. Wähle den Verein, den du öffnen möchtest – du kannst später jederzeit wechseln.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.bottom, 4)
    }

    private func clubRow(_ club: Club) -> some View {
        HStack(spacing: 16) {
            clubBadge(club)
            VStack(alignment: .leading, spacing: 3) {
                Text(club.name)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                if !club.tagline.isEmpty {
                    Text(club.tagline)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Theme.gold)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    @ViewBuilder
    private func clubBadge(_ club: Club) -> some View {
        if let ui = club.logoImage {
            Image(uiImage: ui)
                .resizable().scaledToFill()
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.goldGradient)
                .frame(width: 48, height: 48)
                .overlay(
                    Text(String(club.name.prefix(1)).uppercased())
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.bg0)
                )
        }
    }

    private func select(_ club: Club) {
        Haptics.tap()
        store.switchClub(club.id)
        SoundManager.shared.play(.beer)
    }

    private func logout() {
        Haptics.tap()
        store.logout()
        backend.logout()
    }
}
