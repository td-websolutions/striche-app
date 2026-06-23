import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var store: AppStore
    @State private var showMembers = false
    @State private var showDrinks = false
    @State private var showWatchers = false
    @State private var showReset = false
    @State private var versionTaps = 0
    @State private var partyTrigger = 0
    @State private var showAvatarEdit = false
    @State private var showGetraenkewartEmail = false
    @State private var showEmailChange = false
    @State private var showClubs = false

    var member: Member? { store.currentMember }
    var isAdmin: Bool { member?.isAdmin ?? false }

    var body: some View {
        ZStack {
            AnimatedBackground()
            ScrollView {
                VStack(spacing: 20) {
                    profileHeader
                    statsRow

                    clubsSection
                    notificationsSection

                    if isAdmin {
                        adminSection
                    }

                    generalSection
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            ConfettiBurst(trigger: partyTrigger, emojis: ["🎉","🥳","🍻","✨","🎊","💛"])
        }
        .sheet(isPresented: $showMembers) { MembersAdminView() }
        .sheet(isPresented: $showDrinks) { DrinksAdminView() }
        .sheet(isPresented: $showWatchers) { WatchersView() }
        .sheet(isPresented: $showAvatarEdit) { AvatarEditSheet() }
        .sheet(isPresented: $showGetraenkewartEmail) { GetraenkewartEmailSheet() }
        .sheet(isPresented: $showEmailChange) { ChangeEmailSheet() }
        .sheet(isPresented: $showClubs) { MyClubsSheet() }
        .alert("Alles zurücksetzen?", isPresented: $showReset) {
            Button("Abbrechen", role: .cancel) {}
            Button("Zurücksetzen", role: .destructive) {
                Haptics.warning(); store.resetEverything()
            }
        } message: {
            Text("Verein, Mitglieder, Getränke und alle Buchungen werden gelöscht. Das kann nicht rückgängig gemacht werden.")
        }
    }

    private var profileHeader: some View {
        VStack(spacing: 12) {
            Button {
                Haptics.tap(); showAvatarEdit = true
            } label: {
                ZStack(alignment: .bottomTrailing) {
                    Group {
                        if let img = member?.avatarImage {
                            Image(uiImage: img).resizable().scaledToFill()
                                .frame(width: 96, height: 96).clipShape(Circle())
                                .overlay(Circle().stroke(Theme.gold.opacity(0.5), lineWidth: 2))
                        } else {
                            Text(member?.emoji ?? "🧑")
                                .font(.system(size: 72))
                                .frame(width: 96, height: 96)
                                .background(Color.white.opacity(0.06), in: Circle())
                        }
                    }
                    Image(systemName: "pencil.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.gold)
                        .background(Circle().fill(Theme.bg0))
                }
            }
            .buttonStyle(.plain)
            Text(member?.name ?? "Mitglied")
                .font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text(member?.email ?? "")
                .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
            if isAdmin {
                Label("Administrator", systemImage: "crown.fill")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Theme.gold.opacity(0.2), in: Capsule())
                    .foregroundStyle(Theme.gold)
            }
        }
        .padding(.top, 8)
    }

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: "\(member.map { store.bookings(for: $0).count } ?? 0)",
                     label: "Getränke", icon: "mug.fill")
            statCard(value: String(format: "%.0f €", member.map { store.bookings(for: $0).reduce(0) { $0 + $1.price } } ?? 0),
                     label: "Gesamt", icon: "eurosign.circle.fill")
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(Theme.gold)
            Text(value).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text(label).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 16).glassCard(corner: 18)
    }

    private var clubsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Meine Vereine").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            row(icon: "building.2.fill",
                title: store.club?.name ?? "Verein wählen",
                badge: store.myClubs.count > 1 ? store.myClubs.count : 0) {
                showClubs = true
            }
        }
    }

    private var notificationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Benachrichtigungen").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            row(icon: "bell.badge.fill", title: "Wer wird benachrichtigt?",
                badge: store.incomingRequestCount()) { showWatchers = true }
        }
    }

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Verwaltung").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            row(icon: "person.2.fill", title: "Mitglieder verwalten") { showMembers = true }
            row(icon: "wineglass.fill", title: "Getränke verwalten") { showDrinks = true }
            row(icon: "envelope.fill", title: "Getränkewart-E-Mail") { showGetraenkewartEmail = true }
        }
    }

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Allgemein").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            row(icon: "envelope.badge.fill", title: "E-Mail ändern") { showEmailChange = true }
            row(icon: "rectangle.portrait.and.arrow.right", title: "Abmelden", tint: Theme.accent) {
                Haptics.tap(); store.logout()
            }
            if isAdmin {
                row(icon: "trash.fill", title: "Alles zurücksetzen", tint: Theme.accent) { showReset = true }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text("🍻 Striche")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.goldGradient)
            Text("Version 1.0 · zum Wohle des Vereins")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .onTapGesture {
                    versionTaps += 1
                    Haptics.tap()
                    if versionTaps >= 7 {
                        versionTaps = 0
                        partyTrigger += 1
                        Haptics.success()
                        SoundManager.shared.play(.sekt)
                    }
                }
        }
        .padding(.top, 20)
    }

    private func row(icon: String, title: String, tint: Color = .white,
                     badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap(); action()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(tint == .white ? Theme.gold : tint).frame(width: 24)
                Text(title).font(.system(size: 16, weight: .semibold, design: .rounded)).foregroundStyle(tint)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.bg0)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Theme.accent, in: Circle())
                }
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .glassCard(corner: 16)
        }
    }
}

// MARK: - Getränkewart email setting

struct GetraenkewartEmailSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("An diese Adresse werden „Getränk leer“-Meldungen geschickt, wenn ein Mitglied ein Getränk als leer meldet.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("E-Mail-Adresse")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                            TextField("getraenkewart@verein.de", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                                .padding(16)
                                .glassCard(corner: 14)
                        }

                        Button {
                            Haptics.success()
                            store.setGetraenkewartEmail(email)
                            dismiss()
                        } label: {
                            Text("Speichern").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Getränkewart-E-Mail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear { email = store.club?.getraenkewartEmail ?? "" }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Change own e-mail address

struct ChangeEmailSheet: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var confirmation: String?
    @State private var isWorking = false

    private var isSynced: Bool { backend.isLoggedIn && store.currentMember?.remoteID != nil }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(isSynced
                             ? "Wir schicken einen Bestätigungslink an deine neue Adresse. Die Änderung wird erst aktiv, wenn du den Link anklickst."
                             : "Ändere die E-Mail-Adresse, mit der du in diesem Verein geführt wirst.")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Aktuelle E-Mail")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                            Text(store.currentMember?.email ?? "—")
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .glassCard(corner: 14)
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Neue E-Mail-Adresse")
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                            TextField("name@verein.de", text: $email)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .foregroundStyle(.white)
                                .padding(16)
                                .glassCard(corner: 14)
                        }

                        if let confirmation {
                            Text(confirmation)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.mint)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if let error = backend.lastError, isWorking == false, confirmation == nil {
                            Text(error)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            Task { await save() }
                        } label: {
                            Text(isWorking ? "Senden …" : "E-Mail ändern").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(isWorking || !isValid)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("E-Mail ändern")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var isValid: Bool {
        let clean = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.contains("@") && clean.contains(".") &&
            clean != store.currentMember?.email
    }

    private func save() async {
        let clean = email.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValid else { return }
        confirmation = nil
        if isSynced {
            isWorking = true
            let ok = await backend.requestEmailChange(newEmail: clean)
            isWorking = false
            if ok {
                Haptics.success()
                confirmation = "Bestätigungslink an \(clean) gesendet. Klicke ihn an, um die Änderung abzuschließen."
            } else {
                Haptics.warning()
            }
        } else {
            store.updateCurrentMemberEmail(clean)
            Haptics.success()
            dismiss()
        }
    }
}
