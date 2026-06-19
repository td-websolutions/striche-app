import SwiftUI

struct ConfettiPiece: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
    var scale: CGFloat
    var color: Color
    var symbol: String
    var vx: CGFloat
    var vy: CGFloat
}

/// One-shot confetti / emoji burst. Drive it with a `trigger` value change.
struct ConfettiBurst: View {
    var trigger: Int
    var emojis: [String] = ["🎉","✨","🍺","🥳","⭐️","🫧"]

    @State private var pieces: [ConfettiPiece] = []

    private let colors: [Color] = [Theme.gold, Theme.accent, Theme.mint, .white, Color(hex: "#7AB8FF")]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { p in
                    Text(p.symbol)
                        .font(.system(size: 26 * p.scale))
                        .foregroundStyle(p.color)
                        .rotationEffect(.degrees(p.rotation))
                        .position(x: p.x, y: p.y)
                }
            }
            .onChange(of: trigger) { _, _ in
                burst(in: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func burst(in size: CGSize) {
        let cx = size.width / 2
        let cy = size.height / 2
        var new: [ConfettiPiece] = []
        for _ in 0..<26 {
            let angle = Double.random(in: 0..<(2 * .pi))
            let speed = CGFloat.random(in: 60...220)
            new.append(ConfettiPiece(
                x: cx, y: cy,
                rotation: Double.random(in: 0..<360),
                scale: CGFloat.random(in: 0.6...1.4),
                color: colors.randomElement()!,
                symbol: emojis.randomElement()!,
                vx: CGFloat(cos(angle)) * speed,
                vy: CGFloat(sin(angle)) * speed
            ))
        }
        pieces = new
        withAnimation(.easeOut(duration: 1.1)) {
            for i in pieces.indices {
                pieces[i].x += pieces[i].vx
                pieces[i].y += pieces[i].vy + 180 // gravity
                pieces[i].rotation += Double.random(in: 180...540)
                pieces[i].scale *= 0.4
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            pieces = []
        }
    }
}
