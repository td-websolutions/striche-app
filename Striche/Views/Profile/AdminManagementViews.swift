import SwiftUI

// MARK: - Members management

struct MembersAdminView: View {
    @EnvironmentObject var store: AppStore
    @EnvironmentObject var backend: BackendSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var email = ""
    @State private var asAdmin = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        SeatPlanCard()

                        InviteLinkCard(link: store.inviteLink, message: store.inviteMessage) {
                            store.regenerateInviteCode()
                        }

                        VStack(spacing: 12) {
                            SetupField(icon: "person.fill", placeholder: "Name", text: $name)
                            SetupField(icon: "envelope.fill", placeholder: "E-Mail", text: $email, keyboard: .emailAddress)
                            Toggle(isOn: $asAdmin) {
                                Label("Als Administrator", systemImage: "crown.fill")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                            }.tint(Theme.gold)
                            Button("Einladen") {
                                Haptics.success()
                                store.inviteMember(name: name, email: email, isAdmin: asAdmin)
                                let invitee = email
                                if let clubRemoteID = store.club?.remoteID {
                                    Task { _ = await backend.sendInviteEmail(to: invitee, clubRemoteID: clubRemoteID) }
                                }
                                name = ""; email = ""; asAdmin = false
                            }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(!email.contains("@"))
                            .opacity(email.contains("@") ? 1 : 0.5)
                        }
                        .padding(18).glassCard()

                        ForEach(store.members) { m in
                            HStack(spacing: 12) {
                                Text(m.emoji).font(.system(size: 26))
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(m.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        if m.isAdmin { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(Theme.gold) }
                                    }
                                    Text(m.email).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if m.id != store.currentMember?.id {
                                    Button {
                                        Haptics.warning(); store.removeMember(m)
                                    } label: {
                                        Image(systemName: "trash.fill").foregroundStyle(Theme.accent)
                                    }
                                }
                            }
                            .padding(14).glassCard(corner: 16)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 40)
                }
            }
            .navigationTitle("Mitglieder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Drinks management

struct DrinksAdminView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCustom = false
    @State private var editingDrink: Drink?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 12) {
                        Button {
                            Haptics.tap(); showCustom = true
                        } label: { Label("Neues Produkt", systemImage: "plus.circle.fill") }
                        .buttonStyle(PrimaryButtonStyle())

                        ForEach(store.drinks) { drink in
                            Button {
                                Haptics.tap(); editingDrink = drink
                            } label: {
                                HStack(spacing: 12) {
                                    Text(drink.emoji).font(.system(size: 28))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(drink.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                                        HStack(spacing: 6) {
                                            Text(drink.category.rawValue).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textSecondary)
                                            if !drink.sizes.isEmpty {
                                                Text("· \(drink.sizes.count) Varianten")
                                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                                    .foregroundStyle(Theme.gold.opacity(0.8))
                                            }
                                        }
                                    }
                                    Spacer()
                                    Text(priceLabel(drink))
                                        .font(.system(size: 14, weight: .heavy, design: .rounded)).foregroundStyle(Theme.gold)
                                    Button {
                                        Haptics.warning(); store.removeDrink(drink)
                                    } label: { Image(systemName: "trash.fill").foregroundStyle(Theme.accent) }
                                    .buttonStyle(.plain)
                                }
                                .padding(14).glassCard(corner: 16)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18).padding(.top, 12).padding(.bottom, 40)
                }
            }
            .navigationTitle("Getränke")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .sheet(isPresented: $showCustom) {
                CustomDrinkSheet { store.addDrink($0) }
            }
            .sheet(item: $editingDrink) { drink in
                DrinkEditorSheet(drink: drink) { store.updateDrink($0) }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func priceLabel(_ drink: Drink) -> String {
        if drink.sizes.isEmpty { return String(format: "%.2f €", drink.price) }
        let prices = drink.sizes.map { drink.price + $0.priceModifier }
        let lo = prices.min() ?? drink.price, hi = prices.max() ?? drink.price
        return String(format: "%.2f–%.2f €", lo, hi)
    }
}

// MARK: - Watchers (notify-on-booking with consent)

struct WatchersView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    enum Tab { case choose, requests }
    @State private var tab: Tab = .choose
    @State private var search = ""

    private var otherMembers: [Member] {
        store.members.filter { $0.id != store.currentMember?.id }
    }

    private var filtered: [Member] {
        let base = otherMembers
        guard !search.isEmpty else { return base }
        let q = search.lowercased()
        return base.filter { $0.name.lowercased().contains(q) || $0.email.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                VStack(spacing: 12) {
                    Picker("", selection: $tab) {
                        Text("Benachrichtigen").tag(Tab.choose)
                        Text(requestsLabel).tag(Tab.requests)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 18)
                    .padding(.top, 12)

                    if tab == .choose { chooseTab } else { requestsTab }
                }
            }
            .navigationTitle("Benachrichtigungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var requestsLabel: String {
        let n = store.incomingRequestCount()
        return n > 0 ? "Anfragen (\(n))" : "Anfragen"
    }

    // MARK: Choose whom to notify
    private var chooseTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Wähle hier aus, welche Mitglieder benachrichtigt werden sollen, wenn du ein Getränk buchst. Das Mitglied muss die Anfrage erst annehmen.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                SearchField(text: $search)

                if filtered.isEmpty {
                    Text(search.isEmpty ? "Noch keine weiteren Mitglieder." : "Keine Treffer für »\(search)«.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, 24)
                }

                ForEach(filtered) { m in
                    chooseRow(m)
                }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private func chooseRow(_ m: Member) -> some View {
        let status = store.watchStatus(watcherID: m.id)
        return HStack(spacing: 12) {
            Text(m.emoji).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(m.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(m.email).font(.system(size: 12, design: .rounded)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            statusButton(for: m, status: status)
        }
        .padding(14).glassCard(corner: 16)
    }

    @ViewBuilder
    private func statusButton(for m: Member, status: WatchStatus?) -> some View {
        switch status {
        case .accepted:
            Button {
                Haptics.warning(); store.removeWatch(watcherID: m.id)
            } label: {
                Label("Aktiv", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.mint)
            }
        case .pending:
            Button {
                Haptics.tap(); store.removeWatch(watcherID: m.id)
            } label: {
                Text("Angefragt")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .foregroundStyle(Theme.gold)
            }
        case .declined:
            Button {
                Haptics.tap(); store.requestWatch(watcher: m)
            } label: {
                Text("Abgelehnt · erneut")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.white.opacity(0.06), in: Capsule())
                    .foregroundStyle(Theme.textSecondary)
            }
        case .none:
            Button {
                Haptics.tap(); store.requestWatch(watcher: m)
            } label: {
                Label("Anfragen", systemImage: "bell.fill")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Theme.gold, in: Capsule())
                    .foregroundStyle(Theme.bg0)
            }
        }
    }

    // MARK: Incoming requests (consent)
    private var requestsTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text("Diese Mitglieder möchten benachrichtigt werden, wenn sie buchen – und haben dich als Empfänger gewählt. Nimm an oder lehne ab.")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                let requests = store.incomingRequests()
                if requests.isEmpty {
                    VStack(spacing: 10) {
                        Text("📭").font(.system(size: 52))
                        Text("Keine offenen Anfragen")
                            .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 40)
                }

                ForEach(requests) { link in
                    if let booker = store.members.first(where: { $0.id == link.bookerID }) {
                        requestRow(link: link, booker: booker)
                    }
                }
            }
            .padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 40)
        }
    }

    private func requestRow(link: WatchLink, booker: Member) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Text(booker.emoji).font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(booker.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("möchte dich benachrichtigen")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.warning(); store.declineWatch(link)
                } label: { Text("Ablehnen") }
                .buttonStyle(PrimaryButtonStyle(filled: false))
                Button {
                    Haptics.success(); store.acceptWatch(link)
                } label: { Text("Annehmen") }
                .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(14).glassCard(corner: 18)
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
            TextField("Mitglied suchen…", text: $text)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
