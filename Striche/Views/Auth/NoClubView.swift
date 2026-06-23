import SwiftUI

// MARK: - Logged-in but no club yet
//
// Reached after a backend login (e.g. Google SSO) when the user belongs to no
// club: there's a session (currentMember != nil) but `store.club == nil`. Lets
// them join an existing club via an invite code, or sign out again.

struct NoClubView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession
    @EnvironmentObject var sync: SyncEngine

    @State private var code = ""
    @State private var isJoining = false
    @State private var errorText: String?

    private var trimmedCode: String {
        code.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ZStack {
            AnimatedBackground()
            ScrollView {
                VStack(spacing: 24) {
                    header

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Einladungscode")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        HStack(spacing: 12) {
                            Image(systemName: "ticket.fill")
                                .foregroundStyle(Theme.gold).frame(width: 22)
                            TextField("z. B. 7QK4PD", text: $code)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .textInputAutocapitalization(.characters)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                        }
                        .padding(.vertical, 14).padding(.horizontal, 14)
                        .background(Color.white.opacity(0.06),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .padding(18)
                    .glassCard()

                    if let errorText {
                        hintCard(errorText)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    Button(isJoining ? "Trete bei …" : "Verein beitreten") { join() }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(trimmedCode.count < 4 || isJoining)
                        .opacity(trimmedCode.count < 4 || isJoining ? 0.5 : 1)

                    foundHint

                    Button("Abmelden") { logout() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.accent)
                        .padding(.top, 4)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .animation(.smooth, value: errorText)
    }

    private var header: some View {
        VStack(spacing: 12) {
            Text("🪑").font(.system(size: 56))
            Text("Fast geschafft!")
                .font(.system(size: 24, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Du bist angemeldet, aber noch keinem Verein zugeordnet. Gib den Einladungscode deines Vereins ein, um beizutreten.")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 16)
    }

    private var foundHint: some View {
        Text("Du willst einen **neuen Verein gründen**? Melde dich ab und wähle auf dem Startbildschirm »Verein gründen«.")
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
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
        .background(Theme.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
    }

    private func join() {
        let inviteCode = trimmedCode
        errorText = nil
        isJoining = true
        Haptics.tap()
        Task {
            defer { isJoining = false }
            guard await backend.joinClub(inviteCode: inviteCode) != nil else {
                Haptics.warning()
                errorText = "Dieser Code ist ungültig oder der Verein nimmt aktuell keine neuen Mitglieder auf."
                return
            }
            // Pull brings the club + roster + drinks down; RootView then swaps in.
            await sync.sync()
            if store.club == nil {
                errorText = "Beitritt hat geklappt, aber der Verein konnte nicht geladen werden. Prüfe deine Internetverbindung."
                return
            }
            Haptics.success()
            SoundManager.shared.play(.beer)
        }
    }

    private func logout() {
        Haptics.tap()
        store.logout()
        backend.logout()
    }
}
