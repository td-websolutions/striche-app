import SwiftUI

struct KassenwartView: View {
    @EnvironmentObject var store: AppStore
    @State private var expanded: UUID?
    @State private var memberToSettle: Member?
    @State private var memberToTopUp: Member?
    @State private var showStats = false

    var registeredMembers: [Member] {
        store.members.sorted { store.total(for: $0) > store.total(for: $1) }
    }

    var body: some View {
        ZStack {
            AnimatedBackground()
            ScrollView {
                VStack(spacing: 18) {
                    summaryCard
                    statsButton
                    topDrinks

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Mitglieder")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.gold)
                        ForEach(registeredMembers) { member in
                            memberCard(member)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
        }
        .confirmationDialog("Deckel begleichen?",
                            isPresented: Binding(get: { memberToSettle != nil },
                                                 set: { if !$0 { memberToSettle = nil } }),
                            titleVisibility: .visible) {
            if let m = memberToSettle {
                Button("\(m.name): \(String(format: "%.2f €", store.total(for: m))) als bezahlt markieren") {
                    Haptics.success()
                    store.markPaid(member: m)
                    memberToSettle = nil
                }
            }
            Button("Abbrechen", role: .cancel) { memberToSettle = nil }
        }
        .sheet(item: $memberToTopUp) { m in
            TopUpSheet(member: m) { amount in
                store.topUp(member: m, amount: amount)
            }
        }
        .sheet(isPresented: $showStats) { StatisticsView() }
    }

    private var statsButton: some View {
        Button {
            Haptics.tap(); showStats = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar.xaxis").font(.system(size: 20, weight: .bold))
                    .foregroundStyle(Theme.gold)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Statistik & Auswertung")
                        .font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text("Umsatz pro Monat · PDF / Excel Export")
                        .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            }
            .padding(14)
            .glassCard(corner: 18)
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 8) {
            Text("Offene Gesamtsumme")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.bg0.opacity(0.75))
            Text(String(format: "%.2f €", store.grandTotal))
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.bg0)
            Text("\(store.bookings.filter { !$0.paid }.count) Buchungen · \(store.members.count) Mitglieder")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.bg0.opacity(0.7))
            if store.grandCredit > 0 {
                Text(String(format: "Guthaben gesamt: %.2f €", store.grandCredit))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.bg0.opacity(0.85))
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .background(Theme.goldGradient, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Theme.gold.opacity(0.4), radius: 20, y: 10)
    }

    private var topDrinks: some View {
        let counts = Dictionary(grouping: store.bookings, by: { $0.drinkName })
            .mapValues { $0.count }
            .sorted { $0.value > $1.value }
            .prefix(3)
        return Group {
            if !counts.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Beliebteste Getränke")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    HStack(spacing: 12) {
                        ForEach(Array(counts.enumerated()), id: \.element.key) { i, item in
                            VStack(spacing: 4) {
                                Text(["🥇","🥈","🥉"][min(i, 2)]).font(.system(size: 26))
                                Text(item.key).font(.system(size: 12, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white).lineLimit(1)
                                Text("\(item.value)×").font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.gold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .glassCard(corner: 16)
                        }
                    }
                }
            }
        }
    }

    private func memberCard(_ member: Member) -> some View {
        let memberBookings = store.bookings(for: member)
        let bal = store.balance(for: member)
        let owed = max(0, -bal)
        let credit = max(0, bal)
        let isOpen = expanded == member.id
        return VStack(spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(.smooth) { expanded = isOpen ? nil : member.id }
            } label: {
                HStack(spacing: 12) {
                    Text(member.emoji).font(.system(size: 28))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(member.name).font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                            if member.isAdmin { Image(systemName: "crown.fill").font(.caption2).foregroundStyle(Theme.gold) }
                            if member.passwordHash == nil {
                                Text("eingeladen").font(.system(size: 10, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background(Color.white.opacity(0.08), in: Capsule())
                            }
                        }
                        Text(credit > 0 ? "Guthaben" : "\(memberBookings.filter { !$0.paid }.count) offen")
                            .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(String(format: "%.2f €", credit > 0 ? credit : owed))
                            .font(.system(size: 17, weight: .heavy, design: .rounded))
                            .foregroundStyle(credit > 0 ? Theme.mint : (owed > 0 ? Theme.gold : Theme.textSecondary))
                        if credit > 0 {
                            Text("Guthaben").font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.mint.opacity(0.8))
                        }
                    }
                    Image(systemName: "chevron.down").font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .padding(14)
            }

            if isOpen {
                VStack(spacing: 8) {
                    Divider().overlay(Color.white.opacity(0.1))
                    ForEach(memberBookings.filter { !$0.paid }.prefix(20)) { b in
                        HStack {
                            Text(b.drinkName + (b.sizeLabel.map { " · \($0)" } ?? ""))
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.9))
                            Spacer()
                            Text(b.date, format: .dateTime.day().month().hour().minute())
                                .font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.textSecondary)
                            Text(String(format: "%.2f €", b.price))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(b.paid ? Theme.mint : .white)
                        }
                    }
                    HStack(spacing: 10) {
                        Button {
                            Haptics.tap(); memberToTopUp = member
                        } label: {
                            Label("Aufladen", systemImage: "plus.circle.fill")
                                .lineLimit(1)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(PrimaryButtonStyle(filled: owed == 0))

                        if owed > 0 {
                            Button {
                                memberToSettle = member
                            } label: {
                                Label("Bezahlt", systemImage: "checkmark")
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButtonStyle())
                        }
                    }
                    .padding(.top, 4)
                }
                .padding(14)
                .transition(.opacity)
            }
        }
        .glassCard(corner: 18)
    }
}

// MARK: - Top up credit sheet

struct TopUpSheet: View {
    let member: Member
    var onConfirm: (Double) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""

    private let quick: [Double] = [5, 10, 20, 50]

    private var parsed: Double { Double(amount.replacingOccurrences(of: ",", with: ".")) ?? 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        VStack(spacing: 8) {
                            Text(member.emoji).font(.system(size: 54))
                            Text(member.name).font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                            Text("Guthaben aufladen (z. B. nach Barzahlung)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
                        }
                        .padding(.top, 8)

                        SetupField(icon: "eurosign.circle", placeholder: "Betrag (z. B. 20,00)",
                                   text: $amount, keyboard: .decimalPad)
                            .padding(18).glassCard()

                        HStack(spacing: 10) {
                            ForEach(quick, id: \.self) { v in
                                Button {
                                    Haptics.selection()
                                    amount = String(format: "%.0f", v)
                                } label: {
                                    Text("+\(Int(v)) €")
                                        .font(.system(size: 15, weight: .bold, design: .rounded))
                                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                                        .foregroundStyle(.white)
                                }
                            }
                        }

                        Button("Aufladen") {
                            Haptics.success(); onConfirm(parsed); dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(parsed <= 0)
                        .opacity(parsed <= 0 ? 0.5 : 1)

                        Spacer(minLength: 20)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Guthaben")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
