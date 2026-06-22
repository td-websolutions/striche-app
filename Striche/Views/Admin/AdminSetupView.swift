import SwiftUI
import PhotosUI

struct AdminSetupView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession
    @EnvironmentObject var sync: SyncEngine
    @Environment(\.dismiss) private var dismiss

    @State private var step = 0
    private let totalSteps = 5

    // Step 0 – admin account
    @State private var adminName = ""
    @State private var adminEmail = ""
    @State private var adminPassword = ""

    // Step 1 – club
    @State private var clubName = ""
    @State private var tagline = ""
    @State private var logoItem: PhotosPickerItem?
    @State private var logoData: Data?

    // Step 2 – drinks
    @State private var selectedDrinks: [Drink] = DrinkCatalog.presets
    @State private var showCustomDrink = false
    @State private var editingDrink: Drink?

    // Step 3 – invites
    @State private var inviteName = ""
    @State private var inviteEmail = ""
    @State private var inviteAsAdmin = false
    @State private var pendingMembers: [Member] = []
    @State private var showImport = false
    @State private var csvText = ""
    @State private var inviteCode = Club.makeInviteCode()
    @State private var showManualAdd = false

    private var inviteLink: String { "striche://join?code=\(inviteCode)" }
    private var inviteMessage: String {
        let name = clubName.isEmpty ? "unserem Verein" : clubName
        return """
        🍻 Tritt \(name) auf Striche bei!
        Mit dieser App buchst du deine Getränke ganz einfach selbst.

        👉 \(inviteLink)

        Einfach öffnen, registrieren – fertig. Du wirst automatisch mit dem Verein verbunden.
        """
    }

    // Step 4 – location handled inline

    var body: some View {
        ZStack {
            AnimatedBackground()
            VStack(spacing: 0) {
                progressBar
                Group {
                    switch step {
                    case 0: accountStep
                    case 1: clubStep
                    case 2: drinksStep
                    case 3: invitesStep
                    default: finishStep
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(step)
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)))

                footer
            }
        }
        .navigationTitle("Verein anlegen")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showCustomDrink) {
            CustomDrinkSheet { selectedDrinks.append($0) }
        }
        .sheet(item: $editingDrink) { drink in
            DrinkEditorSheet(drink: drink) { updated in
                if let idx = selectedDrinks.firstIndex(where: { $0.id == updated.id }) {
                    selectedDrinks[idx] = updated
                }
            }
        }
        .sheet(isPresented: $showImport) {
            ImportSheet(text: $csvText) {
                let added = importCSV(csvText)
                csvText = ""
                showImport = false
                _ = added
            }
        }
        .onChange(of: logoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    logoData = data
                }
            }
        }
    }

    // MARK: Progress + footer
    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(0..<totalSteps, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Theme.gold : Color.white.opacity(0.15))
                    .frame(height: 5)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .animation(.smooth, value: step)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button {
                    Haptics.tap(); withAnimation { step -= 1 }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 54, height: 54)
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                .frame(width: 64)
            }
            Button(step == totalSteps - 1 ? "Fertig & loslegen 🎉" : "Weiter") {
                next()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(!canAdvance)
            .opacity(canAdvance ? 1 : 0.5)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .padding(.top, 8)
    }

    private var canAdvance: Bool {
        switch step {
        case 0: return adminEmail.contains("@") && adminPassword.count >= 4 && !adminName.isEmpty
        case 1: return !clubName.isEmpty
        case 2: return !selectedDrinks.isEmpty
        default: return true
        }
    }

    private func next() {
        Haptics.tap()
        if step < totalSteps - 1 {
            withAnimation { step += 1 }
        } else {
            finish()
        }
    }

    // MARK: Steps

    private var accountStep: some View {
        StepScroll(emoji: "👑", title: "Dein Admin-Konto",
                   subtitle: "Du verwaltest den Verein und buchst selbst Getränke.") {
            VStack(spacing: 14) {
                SetupField(icon: "person.fill", placeholder: "Dein Name", text: $adminName)
                SetupField(icon: "envelope.fill", placeholder: "E-Mail", text: $adminEmail, keyboard: .emailAddress)
                SetupField(icon: "lock.fill", placeholder: "Passwort (min. 4 Zeichen)", text: $adminPassword, secure: true)
            }
            .padding(18)
            .glassCard()
        }
    }

    private var clubStep: some View {
        StepScroll(emoji: "🏛️", title: "Dein Verein",
                   subtitle: "Name & Logo erscheinen überall in der App.") {
            VStack(spacing: 18) {
                PhotosPicker(selection: $logoItem, matching: .images) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.06)).frame(width: 120, height: 120)
                        Circle().stroke(Theme.gold.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [6])).frame(width: 120, height: 120)
                        if let logoData, let ui = UIImage(data: logoData) {
                            Image(uiImage: ui).resizable().scaledToFill()
                                .frame(width: 120, height: 120).clipShape(Circle())
                        } else {
                            VStack(spacing: 6) {
                                Image(systemName: "photo.badge.plus").font(.system(size: 28))
                                Text("Logo").font(.system(size: 13, weight: .semibold, design: .rounded))
                            }.foregroundStyle(Theme.gold)
                        }
                    }
                }
                VStack(spacing: 14) {
                    SetupField(icon: "building.2.fill", placeholder: "Vereinsname", text: $clubName)
                    SetupField(icon: "text.quote", placeholder: "Slogan (optional)", text: $tagline)
                }
                .padding(18)
                .glassCard()
            }
        }
    }

    private var drinksStep: some View {
        StepScroll(emoji: "🍺", title: "Getränke & Snacks",
                   subtitle: "Tippe ein Getränk an, um Preis & Varianten (z. B. 0,3 / 0,5 / Flasche) anzupassen. Mit – entfernen, eigene Produkte jederzeit möglich.") {
            VStack(spacing: 12) {
                ForEach(DrinkCategory.allCases) { cat in
                    let drinks = selectedDrinks.filter { $0.category == cat }
                    if !drinks.isEmpty {
                        HStack {
                            Label(cat.rawValue, systemImage: cat.icon)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                            Spacer()
                        }
                        ForEach(drinks) { drink in
                            drinkRow(drink)
                        }
                    }
                }
                Button {
                    Haptics.tap(); showCustomDrink = true
                } label: {
                    Label("Eigenes Produkt anlegen", systemImage: "plus.circle.fill")
                }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                .padding(.top, 6)
            }
        }
    }

    private func drinkRow(_ drink: Drink) -> some View {
        Button {
            Haptics.tap(); editingDrink = drink
        } label: {
            HStack(spacing: 12) {
                Text(drink.emoji).font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(drink.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    HStack(spacing: 6) {
                        Text(priceText(drink)).font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                        if !drink.sizes.isEmpty {
                            Text("· \(drink.sizes.count) Varianten")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.gold.opacity(0.8))
                        }
                    }
                }
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.gold)
                    .frame(width: 30, height: 30)
                    .background(Theme.gold.opacity(0.12), in: Circle())
                Button {
                    Haptics.tap()
                    selectedDrinks.removeAll { $0.id == drink.id }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func priceText(_ drink: Drink) -> String {
        if drink.sizes.isEmpty {
            return String(format: "%.2f €", drink.price)
        }
        let prices = drink.sizes.map { drink.price + $0.priceModifier }
        let min = prices.min() ?? drink.price
        let max = prices.max() ?? drink.price
        return String(format: "%.2f – %.2f €", min, max)
    }

    private var invitesStep: some View {
        StepScroll(emoji: "✉️", title: "Mitglieder einladen",
                   subtitle: "Teile einfach den Einladungslink in eurer WhatsApp-Gruppe – alle treten mit einem Tipp bei.") {
            VStack(spacing: 16) {
                InviteLinkCard(link: inviteLink, message: inviteMessage)

                // Secondary: add individually / import
                DisclosureGroup(isExpanded: $showManualAdd) {
                    VStack(spacing: 16) {
                        VStack(spacing: 12) {
                            SetupField(icon: "person.fill", placeholder: "Name", text: $inviteName)
                            SetupField(icon: "envelope.fill", placeholder: "E-Mail", text: $inviteEmail, keyboard: .emailAddress)
                            Toggle(isOn: $inviteAsAdmin) {
                                Label("Als Administrator", systemImage: "crown.fill")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white)
                            }
                            .tint(Theme.gold)
                            Button {
                                addInvite()
                            } label: {
                                Label("Hinzufügen", systemImage: "plus")
                            }
                            .buttonStyle(PrimaryButtonStyle(filled: false))
                            .disabled(!inviteEmail.contains("@"))
                        }
                        .padding(18)
                        .glassCard()

                        Button {
                            Haptics.tap(); showImport = true
                        } label: {
                            Label("Excel / CSV importieren", systemImage: "tablecells")
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    }
                    .padding(.top, 12)
                } label: {
                    Label("Oder einzeln per E-Mail einladen", systemImage: "envelope.badge")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                }
                .tint(Theme.gold)
                .padding(.horizontal, 4)

                if !pendingMembers.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(pendingMembers) { m in
                            HStack {
                                Text(m.emoji)
                                VStack(alignment: .leading) {
                                    Text(m.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                    Text(m.email).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if m.isAdmin {
                                    Image(systemName: "crown.fill").foregroundStyle(Theme.gold).font(.caption)
                                }
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
    }

    private var finishStep: some View {
        StepScroll(emoji: "📍", title: "Standort des Vereinsheims",
                   subtitle: "Optional: Die App begrüßt Mitglieder am Vereinsheim und erinnert sie beim Gehen ans Buchen.") {
            VStack(spacing: 16) {
                LocationSetupCard()
                VStack(spacing: 8) {
                    Text("Bereit! 🎉").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text("Mit »Fertig« legst du den Verein an und landest direkt in der Getränkeliste.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 8)
            }
        }
    }

    // MARK: Actions
    private func addInvite() {
        Haptics.tap()
        let m = Member(name: inviteName.isEmpty ? inviteEmail : inviteName,
                       email: inviteEmail, isAdmin: inviteAsAdmin, emoji: AvatarPool.random())
        pendingMembers.append(m)
        inviteName = ""; inviteEmail = ""; inviteAsAdmin = false
    }

    private func importCSV(_ csv: String) -> Int {
        var count = 0
        for line in csv.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ",", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard !parts.isEmpty else { continue }
            if parts.count == 2, parts[1].contains("@") {
                pendingMembers.append(Member(name: parts[0], email: parts[1], emoji: AvatarPool.random())); count += 1
            } else if parts.count == 1, parts[0].contains("@") {
                pendingMembers.append(Member(name: parts[0], email: parts[0], emoji: AvatarPool.random())); count += 1
            }
        }
        return count
    }

    private func finish() {
        Haptics.success()
        SoundManager.shared.play(.sekt)

        store.createClub(name: clubName, tagline: tagline, logo: logoData, inviteCode: inviteCode)
        store.setSeedDrinks(selectedDrinks)

        // Persist invited members.
        for m in pendingMembers {
            store.inviteMember(name: m.name, email: m.email, isAdmin: m.isAdmin)
        }

        // Create + login the admin themselves.
        let admin = store.inviteMember(name: adminName, email: adminEmail, isAdmin: true)
        _ = store.register(email: admin.email, password: adminPassword, name: adminName)

        NotificationManager.shared.requestAuthorization()

        // Mirror onto the backend (best-effort, offline-safe): register the admin
        // user and create the club via the privileged hook, which also grants the
        // admin membership the schema rules forbid clients from creating.
        let email = adminEmail, password = adminPassword, name = adminName
        let code = inviteCode, club = clubName, line = tagline
        let openInvite = store.club?.openInvite ?? true
        Task {
            let ok = await backend.register(email: email, password: password,
                                            name: name, emoji: store.currentMember?.emoji ?? "")
            guard ok, let uid = backend.userID else { return }
            store.setCurrentMemberRemoteID(uid)
            if let result = await backend.createClub(
                name: club, tagline: line, inviteCode: code,
                openInvite: openInvite, planID: "free", getraenkewartEmail: nil) {
                store.setClubRemoteID(result.club)
            }
            // Push drinks + the rest now that the club exists remotely.
            await sync.sync()
        }
    }
}

// MARK: - Shared building blocks

struct StepScroll<Content: View>: View {
    let emoji: String
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 10) {
                    Text(emoji).font(.system(size: 52))
                    Text(title).font(.system(size: 24, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Text(subtitle).font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                .padding(.top, 16)
                content
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
}

struct SetupField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    var secure = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Theme.gold).frame(width: 22)
            Group {
                if secure {
                    SecureField(placeholder, text: $text)
                } else {
                    TextField(placeholder, text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                        .autocorrectionDisabled(keyboard == .emailAddress)
                }
            }
            .font(.system(size: 16, weight: .medium, design: .rounded))
            .foregroundStyle(.white)
        }
        .padding(.vertical, 14).padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ImportSheet: View {
    @Binding var text: String
    var onImport: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                VStack(spacing: 16) {
                    Text("Füge Zeilen im Format ein:\n»Name, email@verein.de«")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                    TextEditor(text: $text)
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(height: 220)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
                        .foregroundStyle(.white)
                    Button("Importieren") { Haptics.success(); onImport() }
                        .buttonStyle(PrimaryButtonStyle())
                    Spacer()
                }
                .padding(24)
            }
            .navigationTitle("CSV-Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
