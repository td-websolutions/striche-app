import SwiftUI

// MARK: - Color helpers

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

// MARK: - Theme tokens

enum Theme {
    // Deep "Vereinsheim at night" palette
    static let bg0 = Color(hex: "#0B0D17")
    static let bg1 = Color(hex: "#141831")
    static let bg2 = Color(hex: "#1E2347")

    static let gold = Color(hex: "#F0B429")
    static let amber = Color(hex: "#E8A317")
    static let foam = Color(hex: "#FFF4D6")
    static let beer = Color(hex: "#E8A317")

    static let accent = Color(hex: "#FF5C7A")
    static let mint = Color(hex: "#2EE6A6")

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)

    static var appBackground: LinearGradient {
        LinearGradient(colors: [bg0, bg1, bg2],
                       startPoint: .top, endPoint: .bottom)
    }

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [gold, amber, Color(hex: "#C97B00")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static var mintGradient: LinearGradient {
        LinearGradient(colors: [mint, Color(hex: "#17B985")],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Reusable styles

struct GlassCard: ViewModifier {
    var corner: CGFloat = 24
    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 18, y: 10)
    }
}

extension View {
    func glassCard(corner: CGFloat = 24) -> some View { modifier(GlassCard(corner: corner)) }
}

// MARK: - Primary button

struct PrimaryButtonStyle: ButtonStyle {
    var filled: Bool = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 17, weight: .bold, design: .rounded))
            .foregroundStyle(filled ? Theme.bg0 : Theme.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background {
                if filled {
                    Theme.goldGradient
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(filled ? 0 : 0.15), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Animated mesh-ish background

struct AnimatedBackground: View {
    @State private var move = false
    var body: some View {
        ZStack {
            Theme.appBackground.ignoresSafeArea()
            Circle()
                .fill(Theme.gold.opacity(0.18))
                .frame(width: 360)
                .blur(radius: 90)
                .offset(x: move ? -120 : 120, y: move ? -260 : -180)
            Circle()
                .fill(Theme.accent.opacity(0.16))
                .frame(width: 320)
                .blur(radius: 100)
                .offset(x: move ? 140 : -100, y: move ? 320 : 260)
            Circle()
                .fill(Theme.mint.opacity(0.10))
                .frame(width: 280)
                .blur(radius: 90)
                .offset(x: move ? -160 : 120, y: move ? 120 : 360)
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                move = true
            }
        }
    }
}
