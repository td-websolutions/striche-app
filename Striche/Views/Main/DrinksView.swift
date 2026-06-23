import SwiftUI

struct DrinksView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.openURL) private var openURL
    @StateObject private var loc = LocationManager()

    /// Bound to MainTabView's selection so tapping the balance chip opens "Meine".
    @Binding var selectedTab: Int

    @State private var selectedCategory: DrinkCategory? = nil
    @State private var sizeChooser: Drink?
    @State private var confettiTrigger = 0
    @State private var showPour = false
    @State private var banner: String?
    @State private var totalPulse = false
    @State private var showReorder = false
    @State private var reportedDrink: Drink?
    @State private var showNoEmailAlert = false

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var filteredDrinks: [Drink] {
        guard let cat = selectedCategory else { return store.drinks }
        return store.drinks.filter { $0.category == cat }
    }

    var todayCount: Int {
        guard let member = store.currentMember else { return 0 }
        return store.bookings(for: member).filter { Calendar.current.isDateInToday($0.date) }.count
    }

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                header
                categoryBar
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(filteredDrinks) { drink in
                            DrinkCardView(
                                drink: drink,
                                count: store.currentMember.map { store.count(of: drink, for: $0) } ?? 0,
                                onTap: { tap(drink) },
                                onUndo: { undo(drink) },
                                onReorder: { showReorder = true },
                                onReportEmpty: { reportEmpty(drink) }
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 120)
                }
            }

            // Confetti & pour overlays
            ConfettiBurst(trigger: confettiTrigger)
            if showPour {
                BeerPourOverlay()
                    .transition(.opacity)
            }

            // Location welcome banner
            if let banner {
                VStack {
                    LocationBanner(text: banner)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // "Heute gebucht" pill just above the tab bar
            if todayCount > 0 {
                VStack {
                    Spacer()
                    todayPill
                        .padding(.bottom, 8)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $sizeChooser) { drink in
            SizeChooserSheet(drink: drink) { size in
                book(drink, size: size)
                sizeChooser = nil
            }
            .presentationDetents([.height(320)])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showReorder) { ReorderDrinksSheet() }
        .alert("Keine E-Mail hinterlegt", isPresented: $showNoEmailAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Es ist noch keine Getränkewart-E-Mail hinterlegt. Ein Admin kann sie im Profil unter „Verwaltung“ eintragen.")
        }
        .onAppear(perform: setupLocation)
    }

    // MARK: Header
    private var header: some View {
        HStack(spacing: 12) {
            if let ui = store.club?.logoImage {
                Image(uiImage: ui).resizable().scaledToFill()
                    .frame(width: 46, height: 46).clipShape(Circle())
                    .overlay(Circle().stroke(Theme.gold.opacity(0.5), lineWidth: 1.5))
            } else {
                Text("🍻").font(.system(size: 34))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(store.club?.name ?? "Verein")
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text("Hallo \(store.currentMember?.name ?? "") 👋")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            // Running balance chip (Guthaben or open tab) – tap to open "Meine".
            let bal = store.currentMember.map { store.balance(for: $0) } ?? 0
            Button {
                Haptics.tap()
                selectedTab = 1
            } label: {
                VStack(spacing: 0) {
                    Text(bal >= 0 ? "Guthaben" : "Offen")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.bg0.opacity(0.7))
                    Text(String(format: "%.2f €", abs(bal)))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.bg0)
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(bal >= 0 ? AnyShapeStyle(Theme.mintGradient) : AnyShapeStyle(Theme.goldGradient), in: Capsule())
                .scaleEffect(totalPulse ? 1.12 : 1)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var todayPill: some View {
        HStack(spacing: 8) {
            Text("🍻").font(.system(size: 16))
            Text("Heute gebucht")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("\(todayCount)")
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.bg0)
                .frame(minWidth: 22)
                .padding(.vertical, 3)
                .background(Theme.gold, in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                chip(title: "Alle", icon: "square.grid.2x2.fill", cat: nil)
                ForEach(DrinkCategory.allCases) { cat in
                    if store.drinks.contains(where: { $0.category == cat }) {
                        chip(title: cat.rawValue, icon: cat.icon, cat: cat)
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
    }

    private func chip(title: String, icon: String, cat: DrinkCategory?) -> some View {
        let active = selectedCategory == cat
        return Button {
            Haptics.selection()
            withAnimation(.smooth) { selectedCategory = cat }
        } label: {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(active ? Theme.gold : Color.white.opacity(0.07), in: Capsule())
                .foregroundStyle(active ? Theme.bg0 : .white)
        }
    }

    // MARK: Actions
    private func tap(_ drink: Drink) {
        if drink.sizes.isEmpty {
            book(drink, size: nil)
        } else {
            Haptics.tap()
            sizeChooser = drink
        }
    }

    private func book(_ drink: Drink, size: DrinkSize?) {
        store.book(drink: drink, size: size)
        SoundManager.shared.play(drink.sound)
        Haptics.heavy()

        // Pulse total
        withAnimation(.spring(response: 0.25, dampingFraction: 0.4)) { totalPulse = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            withAnimation { totalPulse = false }
        }

        switch drink.category {
        case .beer:
            withAnimation { showPour = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                withAnimation { showPour = false }
            }
        default:
            confettiTrigger += 1
        }

        notifyWatchersIfOnSite(drink: drink)
    }

    private func undo(_ drink: Drink) {
        guard let member = store.currentMember, store.count(of: drink, for: member) > 0 else { return }
        store.undoLastBooking(of: drink)
        Haptics.warning()
    }

    private func reportEmpty(_ drink: Drink) {
        guard let email = store.club?.getraenkewartEmail, !email.isEmpty else {
            Haptics.warning()
            showNoEmailAlert = true
            return
        }
        let club = store.club?.name ?? "Verein"
        let reporter = store.currentMember?.name ?? "Ein Mitglied"
        let subject = "Getränk leer: \(drink.name)"
        let body = "\(reporter) meldet: \(drink.name) ist leer und sollte nachbestellt werden.\n\n– gesendet aus der Striche-App des \(club)"
        let q = "subject=\(subject)&body=\(body)"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let url = URL(string: "mailto:\(email)?\(q)") else { return }
        Haptics.success()
        openURL(url)
    }

    // MARK: Location
    private func setupLocation() {
        guard let club = store.club else { return }
        loc.configure(clubName: club.name, lat: club.latitude, lon: club.longitude, radius: club.geofenceRadius)
        loc.onArrive = { name in
            SoundManager.shared.play(.beer)
            showBanner("Herzlich Willkommen beim \(name)! 🍻")
        }
        loc.onLeave = { name in
            NotificationManager.shared.notify(
                title: "Danke für deinen Besuch!",
                body: "Bitte prüfe nochmal, ob du alle deine Getränke gebucht hast – zum Wohle des \(name)! 🍻")
        }
        loc.requestPermission()
        NotificationManager.shared.requestAuthorization()
    }

    private func showBanner(_ text: String) {
        withAnimation(.spring) { banner = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            withAnimation { banner = nil }
        }
    }

    private func notifyWatchersIfOnSite(drink: Drink) {
        guard loc.isInside, let me = store.currentMember else { return }
        let watchers = store.acceptedWatchers(of: me.id)
        guard !watchers.isEmpty else { return }
        // In v1 (single device) we fire one local notification representing the ping.
        NotificationManager.shared.notify(
            title: "🍺 \(me.name) am Vereinsheim",
            body: "\(me.name) hat gerade \(drink.name) gebucht.")
    }
}

// MARK: - Size chooser

struct SizeChooserSheet: View {
    let drink: Drink
    var onPick: (DrinkSize) -> Void

    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()
            VStack(spacing: 18) {
                Text(drink.emoji).font(.system(size: 54)).padding(.top, 18)
                Text(drink.name).font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                Text("Welche Größe?").font(.system(size: 14, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                VStack(spacing: 12) {
                    ForEach(drink.sizes) { size in
                        Button {
                            Haptics.tap(); onPick(size)
                        } label: {
                            HStack {
                                Text(size.label).font(.system(size: 17, weight: .bold, design: .rounded))
                                Spacer()
                                Text(String(format: "%.2f €", drink.price + size.priceModifier))
                                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                            }
                            .padding(.horizontal, 18)
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: false))
                    }
                }
                .padding(.horizontal, 24)
                Spacer()
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Reorder tiles

struct ReorderDrinksSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                List {
                    ForEach(store.drinks) { drink in
                        HStack(spacing: 12) {
                            if let sym = drink.iconSymbol {
                                Image(systemName: sym).font(.system(size: 22))
                                    .foregroundStyle(Theme.gold).frame(width: 34)
                            } else {
                                Text(drink.emoji).font(.system(size: 24)).frame(width: 34)
                            }
                            Text(drink.name)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .listRowBackground(Color.white.opacity(0.06))
                    }
                    .onMove { source, destination in
                        Haptics.selection()
                        store.reorderDrinks(from: source, to: destination)
                    }
                }
                .scrollContentBackground(.hidden)
                .environment(\.editMode, .constant(.active))
            }
            .navigationTitle("Kacheln sortieren")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Fertig") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}

struct LocationBanner: View {
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.fill").foregroundStyle(Theme.gold)
            Text(text)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Spacer()
        }
        .padding(16)
        .glassCard(corner: 18)
    }
}
