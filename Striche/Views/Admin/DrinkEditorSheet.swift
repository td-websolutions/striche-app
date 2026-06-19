import SwiftUI

/// Edit an existing drink: name, price and variants (e.g. 0,1 / 0,3 / 0,5 / Flasche).
/// Variants are entered as absolute prices for ease; they are converted back to the
/// base-price + modifier model on save.
struct DrinkEditorSheet: View {
    let drink: Drink
    var onSave: (Drink) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var emoji: String
    @State private var tint: String
    @State private var basePrice: String
    @State private var variants: [EditVariant]

    struct EditVariant: Identifiable, Hashable {
        let id = UUID()
        var label: String
        var price: String   // absolute price in EUR as text
    }

    private let icons = ["🍺","🍻","🥨","🍷","🥂","🍸","🍹","🍶","🥃","🍾","🧃","🥤","🧋","☕️","🍵","🧉","💧","🫧","🥛","🍊","🍎","🍋","🌭","🍔","🍟","🍕","🥪","🥗","🧀","🥜","🍿","🍫","🍩","🌶️","🥒"]
    private let palette = ["#E8A317","#F0B429","#9B2D5E","#7A1F47","#E3C770","#2EC4F0","#9B3B2E","#F08A1D","#C4D92E","#6F4E37","#B5651D","#2EE6A6","#7AB8FF","#FF5C7A","#C9D92E"]
    private let suggestions = ["0,1 l", "0,2 l", "0,3 l", "0,4 l", "0,5 l", "Flasche", "Glas"]

    init(drink: Drink, onSave: @escaping (Drink) -> Void) {
        self.drink = drink
        self.onSave = onSave
        _name = State(initialValue: drink.name)
        _emoji = State(initialValue: drink.emoji)
        _tint = State(initialValue: drink.tintHex)
        _basePrice = State(initialValue: Self.fmt(drink.price))
        _variants = State(initialValue: drink.sizes.map {
            EditVariant(label: $0.label, price: Self.fmt(drink.price + $0.priceModifier))
        })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        DrinkCardPreview(emoji: emoji, name: name.isEmpty ? "Produkt" : name,
                                         price: previewPrice, tint: Color(hex: tint))
                            .padding(.top, 8)

                        VStack(spacing: 14) {
                            SetupField(icon: "textformat", placeholder: "Name", text: $name)
                            if variants.isEmpty {
                                SetupField(icon: "eurosign.circle", placeholder: "Preis (z. B. 2,50)",
                                           text: $basePrice, keyboard: .decimalPad)
                            }
                        }
                        .padding(18).glassCard()

                        variantsSection

                        section("Icon") {
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                                ForEach(icons, id: \.self) { ic in
                                    Text(ic).font(.system(size: 30))
                                        .frame(width: 48, height: 48)
                                        .background(emoji == ic ? Theme.gold.opacity(0.3) : Color.white.opacity(0.05),
                                                    in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12)
                                            .stroke(emoji == ic ? Theme.gold : .clear, lineWidth: 2))
                                        .onTapGesture { Haptics.selection(); emoji = ic }
                                }
                            }
                        }

                        section("Farbe") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(palette, id: \.self) { hex in
                                        Circle().fill(Color(hex: hex))
                                            .frame(width: 38, height: 38)
                                            .overlay(Circle().stroke(.white, lineWidth: tint == hex ? 3 : 0))
                                            .onTapGesture { Haptics.selection(); tint = hex }
                                    }
                                }
                            }
                        }

                        Button("Speichern") { save() }
                            .buttonStyle(PrimaryButtonStyle())
                            .disabled(name.isEmpty)
                            .opacity(name.isEmpty ? 0.5 : 1)

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            .navigationTitle("Bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    private var variantsSection: some View {
        section("Varianten") {
            VStack(spacing: 12) {
                if variants.isEmpty {
                    Text("Keine Varianten – es gilt der Preis oben. Füge z. B. 0,3 l / 0,5 l / Flasche hinzu.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach($variants) { $v in
                        HStack(spacing: 10) {
                            TextField("Größe", text: $v.label)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            TextField("Preis", text: $v.price)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.gold)
                                .frame(width: 70)
                            Text("€").foregroundStyle(Theme.textSecondary)
                            Button {
                                Haptics.tap()
                                variants.removeAll { $0.id == v.id }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.system(size: 20)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                    }
                }

                // Quick-add suggestion chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { s in
                            if !variants.contains(where: { $0.label == s }) {
                                Button {
                                    Haptics.selection()
                                    let seed = basePrice.isEmpty ? "0,00" : basePrice
                                    variants.append(EditVariant(label: s, price: seed))
                                } label: {
                                    Label(s, systemImage: "plus")
                                        .font(.system(size: 13, weight: .bold, design: .rounded))
                                        .padding(.horizontal, 12).padding(.vertical, 8)
                                        .background(Color.white.opacity(0.07), in: Capsule())
                                        .foregroundStyle(.white)
                                }
                            }
                        }
                    }
                }
            }
            .padding(14).glassCard()
        }
    }

    private var previewPrice: Double {
        if let first = variants.first { return parse(first.price) }
        return parse(basePrice)
    }

    private func save() {
        Haptics.success()
        var updated = drink
        updated.name = name
        updated.emoji = emoji
        updated.tintHex = tint
        let clean = variants.filter { !$0.label.trimmingCharacters(in: .whitespaces).isEmpty }
        if clean.isEmpty {
            updated.price = parse(basePrice)
            updated.sizes = []
        } else {
            let base = parse(clean[0].price)
            updated.price = base
            updated.sizes = clean.map { DrinkSize(label: $0.label, priceModifier: parse($0.price) - base) }
        }
        onSave(updated)
        dismiss()
    }

    private func parse(_ s: String) -> Double {
        Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
    }

    private static func fmt(_ d: Double) -> String {
        String(format: "%.2f", d).replacingOccurrences(of: ".", with: ",")
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 14, weight: .bold, design: .rounded)).foregroundStyle(Theme.gold)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
