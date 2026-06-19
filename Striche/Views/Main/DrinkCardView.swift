import SwiftUI

struct FloatingPlus: Identifiable {
    let id = UUID()
    var text: String
    var x: CGFloat
}

struct DrinkCardView: View {
    let drink: Drink
    let count: Int
    var onTap: () -> Void
    var onUndo: () -> Void
    var onReorder: () -> Void
    var onReportEmpty: () -> Void

    @State private var pressed = false
    @State private var liquid: CGFloat = 0.0
    @State private var wavePhase: CGFloat = 0
    @State private var floaters: [FloatingPlus] = []
    @State private var jiggle = false

    var body: some View {
        ZStack {
            // Card base with liquid fill that rises slightly with each tap
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(colors: [drink.tint.opacity(0.35), drink.tint.opacity(0.12)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .overlay {
                    LiquidWave(progress: liquid, phase: wavePhase)
                        .fill(
                            LinearGradient(colors: [drink.tint.opacity(0.85), drink.tint.opacity(0.55)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .allowsHitTesting(false)
                }
                .overlay(RoundedRectangle(cornerRadius: 28).stroke(.white.opacity(0.15), lineWidth: 1))

            VStack(spacing: 8) {
                Group {
                    if let sym = drink.iconSymbol {
                        Image(systemName: sym)
                            .font(.system(size: 46))
                            .foregroundStyle(
                                LinearGradient(colors: [Color(hex: "#FFF7D6"), Color(hex: "#E9D89A")],
                                               startPoint: .top, endPoint: .bottom)
                            )
                    } else {
                        Text(drink.emoji)
                            .font(.system(size: 52))
                    }
                }
                .scaleEffect(jiggle ? 1.25 : 1)
                .rotationEffect(.degrees(jiggle ? -8 : 0))
                Text(drink.name)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(priceText)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.vertical, 18)

            // Count badge
            if count > 0 {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(count)")
                            .font(.system(size: 14, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.bg0)
                            .frame(minWidth: 26, minHeight: 26)
                            .padding(.horizontal, 4)
                            .background(Theme.gold, in: Capsule())
                            .overlay(Capsule().stroke(.white.opacity(0.4), lineWidth: 1))
                            .scaleEffect(jiggle ? 1.2 : 1)
                    }
                    Spacer()
                }
                .padding(10)
                .transition(.scale.combined(with: .opacity))
            }

            // Floating +1
            ForEach(floaters) { f in
                Text(f.text)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.foam)
                    .shadow(color: drink.tint, radius: 6)
                    .offset(x: f.x, y: -70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(height: 150)
        .scaleEffect(pressed ? 0.94 : 1)
        .shadow(color: drink.tint.opacity(0.4), radius: 14, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: 28))
        .onTapGesture { register() }
        .contextMenu {
            Button {
                onUndo()
            } label: {
                Label("Letzte Buchung rückgängig", systemImage: "arrow.uturn.backward")
            }
            .disabled(count == 0)
            Button {
                onReorder()
            } label: {
                Label("Kacheln neu sortieren", systemImage: "arrow.up.arrow.down")
            }
            Divider()
            Button(role: .destructive) {
                onReportEmpty()
            } label: {
                Label("Getränk leer melden", systemImage: "exclamationmark.bubble")
            }
        }
        .onAppear {
            withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) { wavePhase = .pi * 2 }
            liquid = baseLiquid
        }
        .onChange(of: count) { _, _ in liquid = baseLiquid }
    }

    private var baseLiquid: CGFloat {
        // Visual fill grows with count, capped so it never fully covers content.
        min(0.55, CGFloat(count) * 0.06)
    }

    private var priceText: String {
        if drink.sizes.isEmpty {
            return String(format: "%.2f €", drink.price)
        }
        let prices = drink.sizes.map { drink.price + $0.priceModifier }
        return String(format: "ab %.2f €", prices.min() ?? drink.price)
    }

    private func register() {
        onTap()
        // local splashy feedback
        withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) {
            pressed = true; jiggle = true
            liquid = min(0.6, baseLiquid + 0.18)
        }
        let f = FloatingPlus(text: "+1", x: CGFloat.random(in: -14...14))
        withAnimation { floaters.append(f) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                pressed = false; jiggle = false; liquid = baseLiquid
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation { floaters.removeAll { $0.id == f.id } }
        }
    }
}
