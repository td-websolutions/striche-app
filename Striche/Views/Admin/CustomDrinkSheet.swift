import SwiftUI

struct CustomDrinkSheet: View {
    var onCreate: (Drink) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var price = ""
    @State private var emoji = "🥤"
    @State private var category: DrinkCategory = .soft
    @State private var tint = "#2EC4F0"

    // Icon library — a tasty, broad emoji palette.
    private let icons = ["🍺","🍻","🥨","🍷","🥂","🍸","🍹","🍶","🥃","🍾","🧃","🥤","🧋","☕️","🍵","🧉","💧","🥛","🍊","🍎","🍋","🌭","🍔","🍟","🍕","🥪","🥗","🧀","🥜","🍿","🍫","🍩","🌶️","🥒"]
    private let palette = ["#E8A317","#F0B429","#9B2D5E","#7A1F47","#2EC4F0","#9B3B2E","#F08A1D","#C4D92E","#6F4E37","#B5651D","#2EE6A6","#FF5C7A","#7AB8FF","#C9D92E"]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.appBackground.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        // Live preview
                        DrinkCardPreview(emoji: emoji, name: name.isEmpty ? "Produkt" : name,
                                         price: Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0,
                                         tint: Color(hex: tint))
                            .padding(.top, 8)

                        VStack(spacing: 14) {
                            SetupField(icon: "textformat", placeholder: "Name", text: $name)
                            SetupField(icon: "eurosign.circle", placeholder: "Preis (z. B. 2,50)", text: $price, keyboard: .decimalPad)
                        }
                        .padding(18).glassCard()

                        section("Kategorie") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(DrinkCategory.allCases) { cat in
                                        Button {
                                            Haptics.selection(); category = cat
                                        } label: {
                                            Label(cat.rawValue, systemImage: cat.icon)
                                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                                .padding(.horizontal, 14).padding(.vertical, 10)
                                                .background(category == cat ? Theme.gold : Color.white.opacity(0.07),
                                                            in: Capsule())
                                                .foregroundStyle(category == cat ? Theme.bg0 : .white)
                                        }
                                    }
                                }
                            }
                        }

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

                        Button("Produkt anlegen") {
                            let p = Double(price.replacingOccurrences(of: ",", with: ".")) ?? 0
                            let drink = Drink(name: name, emoji: emoji, price: p,
                                              category: category, tintHex: tint)
                            Haptics.success()
                            onCreate(drink)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .disabled(name.isEmpty)
                        .opacity(name.isEmpty ? 0.5 : 1)

                        Spacer(minLength: 30)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .navigationTitle("Eigenes Produkt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } } }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
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

struct DrinkCardPreview: View {
    let emoji: String
    let name: String
    let price: Double
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            Text(emoji).font(.system(size: 54))
            Text(name).font(.system(size: 17, weight: .bold, design: .rounded)).foregroundStyle(.white)
            Text(String(format: "%.2f €", price)).font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.8))
        }
        .frame(width: 150, height: 150)
        .background(
            LinearGradient(colors: [tint.opacity(0.55), tint.opacity(0.2)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.15), lineWidth: 1))
        .shadow(color: tint.opacity(0.4), radius: 20, y: 10)
    }
}
