import SwiftUI

// MARK: - Seat usage card (shown in the members section)

struct SeatPlanCard: View {
    @EnvironmentObject var store: AppStore
    @State private var showPlans = false

    private var used: Int { store.usedSeats }
    private var plan: SeatPlan { store.activePlan }
    private var cap: Int { plan.maxSeats }
    private var overbooked: Bool { store.needsUpgrade }

    private var progress: Double {
        guard cap > 0, cap != .max else { return overbooked ? 1 : 0.04 }
        return min(1, Double(used) / Double(cap))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Mitglieder-Plätze", systemImage: "person.3.fill")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Spacer()
                Text(plan.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white.opacity(0.08), in: Capsule())
                    .foregroundStyle(.white)
            }

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("\(used)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(cap == .max ? "Mitglieder" : "von \(cap) Plätzen belegt")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }

            if cap != .max {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.08))
                        Capsule()
                            .fill(overbooked ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.goldGradient))
                            .frame(width: max(6, geo.size.width * progress))
                    }
                }
                .frame(height: 8)
            }

            if let pending = store.pendingPlan {
                statusLine(icon: "clock.badge.fill", tint: Theme.gold,
                           text: pending.isEnterprise
                           ? "Enterprise angefragt – wir melden uns."
                           : "Bestellung erfasst (\(pending.name)) – Rechnung folgt per Mail.")
            } else if overbooked {
                statusLine(icon: "exclamationmark.triangle.fill", tint: Theme.accent,
                           text: "Plätze überbucht – bitte Plan erweitern.")
            } else if plan.isFree {
                statusLine(icon: "gift.fill", tint: Theme.mint,
                           text: "\(store.seatsRemaining) freie Plätze · danach kostenpflichtig.")
            } else {
                statusLine(icon: "checkmark.seal.fill", tint: Theme.mint,
                           text: "\(store.seatsRemaining) Plätze frei · \(plan.priceLabel)")
            }

            Button {
                Haptics.tap(); showPlans = true
            } label: {
                Label(overbooked ? "Jetzt erweitern" : "Plan verwalten",
                      systemImage: "creditcard.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle(filled: overbooked))
        }
        .padding(16)
        .glassCard(corner: 18)
        .sheet(isPresented: $showPlans) { PlanSheet() }
    }

    private func statusLine(icon: String, tint: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(tint)
            Text(text)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Plan chooser / order sheet

struct PlanSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String
    @State private var confirmOrder = false

    init() {
        _selected = State(initialValue: SeatPlan.freeID)
    }

    private var selectedPlan: SeatPlan { SeatPlans.plan(id: selected) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        intro
                        ForEach(SeatPlans.all) { plan in
                            planRow(plan)
                        }
                        Text("Abrechnung für 1 Jahr im Voraus per Rechnung. Kündigung bis 1 Monat vor Ende der Laufzeit möglich. Die Rechnung wird dir nach der Bestellung manuell zugeschickt. Verwaltung und Verlängerung erfolgen über dein Vereins-Dashboard.")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18).padding(.vertical, 16)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .safeAreaInset(edge: .bottom) { orderBar }
            .navigationTitle("Plätze & Tarife")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Schließen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
            .onAppear {
                // Pre-select the active plan, or the one required for current size.
                let req = store.requiredPlan
                selected = store.needsUpgrade ? req.id : store.activePlan.id
            }
            .confirmationDialog(orderTitle, isPresented: $confirmOrder, titleVisibility: .visible) {
                Button(orderButtonTitle) {
                    Haptics.success()
                    store.requestPlan(selectedPlan)
                    dismiss()
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text(selectedPlan.isEnterprise
                     ? "Wir melden uns mit einem individuellen Angebot."
                     : String(format: "Der Tarif wird sofort freigeschaltet. Abrechnung für 1 Jahr im Voraus: %.2f € (12 × %.2f €). Kündigung bis 1 Monat vor Ende der Laufzeit. Die Rechnung erhältst du anschließend per Mail.", selectedPlan.yearlyTotal, selectedPlan.monthlyPrice))
            }
        }
        .preferredColorScheme(.dark)
    }

    private var intro: some View {
        VStack(spacing: 6) {
            Text("Bis 5 Mitglieder kostenlos")
                .font(.system(size: 18, weight: .heavy, design: .rounded)).foregroundStyle(.white)
            Text("Wächst dein Verein, wähle den passenden Tarif. Alle Funktionen sind in jedem Tarif enthalten – es zählt nur die Anzahl der Plätze.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 4)
    }

    private func planRow(_ plan: SeatPlan) -> some View {
        let isSelected = selected == plan.id
        let isActive = store.activePlan.id == plan.id && store.pendingPlan == nil
        let isRecommended = store.needsUpgrade && store.requiredPlan.id == plan.id
        let fits = store.usedSeats <= plan.maxSeats
        return Button {
            Haptics.selection(); selected = plan.id
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 20)).foregroundStyle(isSelected ? Theme.gold : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(plan.name).font(.system(size: 15, weight: .bold, design: .rounded)).foregroundStyle(.white)
                        if isActive { badge("Aktiv", Theme.mint) }
                        if isRecommended { badge("Empfohlen", Theme.gold) }
                    }
                    Text(plan.isEnterprise ? "Mehr als 500 Plätze" :
                            (plan.isFree ? "Perfekt zum Ausprobieren" : "bis \(plan.maxSeats) Mitglieder"))
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(fits ? Theme.textSecondary : Theme.accent.opacity(0.9))
                }
                Spacer()
                Text(plan.priceLabel)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(plan.isFree ? Theme.mint : .white)
                    .multilineTextAlignment(.trailing)
            }
            .padding(14)
            .background(isSelected ? Color.white.opacity(0.06) : Color.clear, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Theme.gold.opacity(0.6) : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }

    private var orderBar: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.tap(); confirmOrder = true
            } label: {
                Text(orderButtonTitle).frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(orderDisabled)
            .opacity(orderDisabled ? 0.5 : 1)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
        }
        .background(.ultraThinMaterial)
    }

    private var orderDisabled: Bool {
        selectedPlan.isFree || (store.activePlan.id == selected && store.pendingPlan == nil)
    }

    private var orderTitle: String {
        selectedPlan.isEnterprise ? "Enterprise anfragen?" : "\(selectedPlan.name) bestellen?"
    }

    private var orderButtonTitle: String {
        if selectedPlan.isEnterprise { return "Kontakt anfragen" }
        if selectedPlan.isFree { return "Kostenloser Tarif" }
        return String(format: "Kostenpflichtig bestellen · %.2f € / Jahr", selectedPlan.yearlyTotal)
    }
}
