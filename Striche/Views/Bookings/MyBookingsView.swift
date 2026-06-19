import SwiftUI

struct MyBookingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var showHistory = false

    var member: Member? { store.currentMember }

    var allBookings: [Booking] {
        guard let member else { return [] }
        return store.bookings(for: member)
    }

    var openBookings: [Booking] { allBookings.filter { !$0.paid } }

    var grouped: [(day: String, items: [Booking])] {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEEE, d. MMMM"
        fmt.locale = Locale(identifier: "de_DE")
        let dict = Dictionary(grouping: openBookings) { fmt.string(from: $0.date) }
        return dict.sorted { ($0.value.first?.date ?? .now) > ($1.value.first?.date ?? .now) }
            .map { ($0.key, $0.value) }
    }

    // Chronological history: settled drinks + credit top-ups / settlements.
    enum HistoryEntry: Identifiable {
        case booking(Booking)
        case credit(CreditTransaction)
        var id: UUID {
            switch self { case .booking(let b): return b.id; case .credit(let c): return c.id }
        }
        var date: Date {
            switch self { case .booking(let b): return b.date; case .credit(let c): return c.date }
        }
    }

    var history: [HistoryEntry] {
        guard let member else { return [] }
        let paid = allBookings.filter { $0.paid }.map { HistoryEntry.booking($0) }
        let credits = store.creditTransactions(for: member).map { HistoryEntry.credit($0) }
        return (paid + credits).sorted { $0.date > $1.date }
    }

    var body: some View {
        ZStack {
            AnimatedBackground()
            VStack(spacing: 0) {
                headerTotal
                ScrollView {
                    VStack(spacing: 18) {
                        if openBookings.isEmpty {
                            emptyOpen
                        } else {
                            ForEach(grouped, id: \.day) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.day.capitalized)
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .foregroundStyle(Theme.gold)
                                    ForEach(section.items) { b in bookingRow(b) }
                                }
                            }
                        }

                        if !history.isEmpty { historySection }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 100)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
    }

    private var balance: Double { member.map { store.balance(for: $0) } ?? 0 }

    private var headerTotal: some View {
        VStack(spacing: 6) {
            Text(balance >= 0 ? "Dein Guthaben" : "Mein Deckel")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            Text(String(format: "%.2f €", abs(balance)))
                .font(.system(size: 44, weight: .heavy, design: .rounded))
                .foregroundStyle(balance >= 0 ? AnyShapeStyle(Theme.mintGradient) : AnyShapeStyle(Theme.goldGradient))
            Text(balance >= 0
                 ? "Buchungen werden direkt verrechnet"
                 : "\(openBookings.count) offene Buchungen")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 18)
    }

    private func bookingRow(_ b: Booking) -> some View {
        HStack(spacing: 12) {
            Text(emoji(for: b)).font(.system(size: 26))
            VStack(alignment: .leading, spacing: 2) {
                Text(b.drinkName + (b.sizeLabel.map { " · \($0)" } ?? ""))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(b.date, format: .dateTime.hour().minute())
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(String(format: "%.2f €", b.price))
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
        .padding(14)
        .glassCard(corner: 18)
    }

    // MARK: History
    private var historySection: some View {
        DisclosureGroup(isExpanded: $showHistory) {
            VStack(spacing: 8) {
                ForEach(history) { entry in
                    switch entry {
                    case .booking(let b): historyBookingRow(b)
                    case .credit(let c): historyCreditRow(c)
                    }
                }
            }
            .padding(.top, 10)
        } label: {
            Label("Verlauf (\(history.count))", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.gold)
        }
        .tint(Theme.gold)
        .padding(16)
        .glassCard(corner: 18)
    }

    private func historyBookingRow(_ b: Booking) -> some View {
        HStack(spacing: 10) {
            Text(emoji(for: b)).font(.system(size: 20))
            VStack(alignment: .leading, spacing: 1) {
                Text(b.drinkName + (b.sizeLabel.map { " · \($0)" } ?? ""))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white.opacity(0.9))
                Text(b.date, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(String(format: "−%.2f €", b.price))
                .font(.system(size: 13, weight: .bold, design: .rounded)).foregroundStyle(Theme.textSecondary)
        }
    }

    private func historyCreditRow(_ c: CreditTransaction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: c.kind == .topUp ? "plus.circle.fill" : "checkmark.seal.fill")
                .font(.system(size: 20)).foregroundStyle(Theme.mint)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.note ?? (c.kind == .topUp ? "Guthaben aufgeladen" : "Deckel bar bezahlt"))
                    .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                Text(c.date, format: .dateTime.day().month().hour().minute())
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text(String(format: "+%.2f €", c.amount))
                .font(.system(size: 13, weight: .heavy, design: .rounded)).foregroundStyle(Theme.mint)
        }
    }

    private func emoji(for b: Booking) -> String {
        store.drinks.first { $0.id == b.drinkID }?.emoji ?? "🥤"
    }

    private var emptyOpen: some View {
        VStack(spacing: 14) {
            Text(balance > 0 ? "✨" : "🍺").font(.system(size: 64)).opacity(0.7)
            Text(balance > 0 ? "Alles beglichen" : "Noch nichts gebucht")
                .font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(balance > 0
                 ? "Dein Guthaben deckt deine Buchungen automatisch ab."
                 : "Tippe im Tab »Buchen« auf ein Getränk – so oft du magst.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center).padding(.horizontal, 40)
        }
        .padding(.top, 40)
    }
}
