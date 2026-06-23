import SwiftUI

// MARK: - Meine Vereine (switch / join / create)
//
// Reached from the profile. Lets the logged-in person switch between the
// Vereine they belong to, join another via an invite code, and – as an admin –
// found a brand-new club right from the app. Joining/founding is mirrored to the
// backend when signed in (best-effort); locally it always succeeds.

struct MyClubsSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var joinCode = ""
    @State private var newClubName = ""
    @State private var isWorking = false
    @State private var errorText: String?

    private var trimmedCode: String {
        joinCode.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private var trimmedName: String {
        newClubName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        clubList
                        if let errorText {
                            hintCard(errorText)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        joinCard
                        createCard
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Meine Vereine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .animation(.smooth, value: errorText)
        }
    }

    private var clubList: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Wechseln").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            ForEach(store.myClubs) { club in
                Button { select(club) } label: {
                    HStack(spacing: 14) {
                        clubBadge(club)
                        Text(club.name)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Spacer()
                        if club.id == store.club?.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.mint).font(.system(size: 20))
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard(corner: 16)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var joinCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Verein beitreten").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            HStack(spacing: 12) {
                Image(systemName: "ticket.fill").foregroundStyle(Theme.gold).frame(width: 22)
                TextField("Einladungscode", text: $joinCode)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(isWorking ? "Bitte warten …" : "Beitreten") { join() }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(trimmedCode.count < 4 || isWorking)
                .opacity(trimmedCode.count < 4 || isWorking ? 0.5 : 1)
        }
        .padding(16).glassCard()
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Neuen Verein gründen").font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            HStack(spacing: 12) {
                Image(systemName: "building.2.fill").foregroundStyle(Theme.gold).frame(width: 22)
                TextField("Vereinsname", text: $newClubName)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(14)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button(isWorking ? "Bitte warten …" : "Verein gründen") { create() }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                .disabled(trimmedName.count < 2 || isWorking)
                .opacity(trimmedName.count < 2 || isWorking ? 0.5 : 1)

            Text("Du wirst Administrator des neuen Vereins. Getränke kannst du anschließend anpassen.")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(16).glassCard()
    }

    @ViewBuilder
    private func clubBadge(_ club: Club) -> some View {
        if let ui = club.logoImage {
            Image(uiImage: ui).resizable().scaledToFill()
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Theme.goldGradient)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(club.name.prefix(1)).uppercased())
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.bg0)
                )
        }
    }

    private func hintCard(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.accent).font(.system(size: 18))
            Text(text)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func select(_ club: Club) {
        Haptics.tap()
        store.switchClub(club.id)
        dismiss()
    }

    private func join() {
        let code = trimmedCode
        errorText = nil
        isWorking = true
        Haptics.tap()
        Task {
            defer { isWorking = false }
            guard backend.isLoggedIn else {
                errorText = "Zum Beitreten eines weiteren Vereins musst du online angemeldet sein."
                return
            }
            guard let result = await backend.joinClub(inviteCode: code) else {
                Haptics.warning()
                errorText = "Dieser Code ist ungültig oder der Verein nimmt aktuell keine neuen Mitglieder auf."
                return
            }
            await sync.sync()
            if let club = store.clubByRemoteID(result.club) {
                store.switchClub(club.id)
                Haptics.success()
                SoundManager.shared.play(.beer)
                dismiss()
            } else {
                errorText = "Beitritt hat geklappt, aber der Verein konnte nicht geladen werden. Prüfe deine Internetverbindung."
            }
        }
    }

    private func create() {
        let name = trimmedName
        errorText = nil
        isWorking = true
        Haptics.tap()
        Task {
            defer { isWorking = false }
            store.createAdditionalClub(name: name)
            // Mirror to the backend when signed in (best-effort; local already done).
            if backend.isLoggedIn { await sync.sync() }
            Haptics.success()
            SoundManager.shared.play(.beer)
            dismiss()
        }
    }
}
