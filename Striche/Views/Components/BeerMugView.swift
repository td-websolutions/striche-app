import SwiftUI

/// A wavy liquid shape used to fill the mug.
struct LiquidWave: Shape {
    var progress: CGFloat   // 0...1 fill level
    var phase: CGFloat      // animates the wave horizontally

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(progress, phase) }
        set { progress = newValue.first; phase = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let waveHeight: CGFloat = 8
        let level = rect.height * (1 - progress)
        p.move(to: CGPoint(x: 0, y: level))
        for x in stride(from: 0, through: rect.width, by: 1) {
            let relativeX = x / rect.width
            let y = level + sin(relativeX * .pi * 2 + phase) * waveHeight
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

/// Big celebratory mug that fills up. Shown as an overlay on a beer booking.
struct FillingMugView: View {
    var fill: CGFloat          // 0...1 target fill
    @State private var phase: CGFloat = 0
    @State private var bubbles: [Bubble] = []

    struct Bubble: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var size: CGFloat
    }

    var body: some View {
        ZStack {
            // Mug body
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Theme.foam, lineWidth: 6)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                )
                .frame(width: 130, height: 170)
                .overlay {
                    // Liquid
                    LiquidWave(progress: fill, phase: phase)
                        .fill(LinearGradient(colors: [Theme.beer, Theme.gold],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay {
                            ForEach(bubbles) { b in
                                Circle().fill(.white.opacity(0.5))
                                    .frame(width: b.size, height: b.size)
                                    .position(x: b.x, y: b.y)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .frame(width: 130, height: 170)
                }
                .overlay(alignment: .top) {
                    // Foam head
                    if fill > 0.5 {
                        Capsule().fill(Theme.foam)
                            .frame(width: 120, height: 26)
                            .offset(y: -10)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            // Handle
            RoundedRectangle(cornerRadius: 16)
                .stroke(Theme.foam, lineWidth: 6)
                .frame(width: 42, height: 80)
                .offset(x: 86)
        }
        .onAppear {
            withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
            spawnBubbles()
        }
    }

    private func spawnBubbles() {
        bubbles = (0..<10).map { _ in
            Bubble(x: CGFloat.random(in: 20...110),
                   y: CGFloat.random(in: 40...160),
                   size: CGFloat.random(in: 3...8))
        }
    }
}

/// Full-screen celebratory pour overlay for beer bookings.
struct BeerPourOverlay: View {
    @State private var fill: CGFloat = 0
    @State private var show = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 20) {
                FillingMugView(fill: fill)
                    .scaleEffect(show ? 1 : 0.4)
                    .opacity(show ? 1 : 0)
                Text("Prost! 🍻")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.gold)
                    .opacity(show ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { show = true }
            withAnimation(.easeOut(duration: 1.0)) { fill = 0.92 }
        }
    }
}
