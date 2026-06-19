import SwiftUI

struct OnboardingPage: Identifiable {
    let id = UUID()
    let emoji: String
    let title: String
    let subtitle: String
    let tint: Color
}

struct OnboardingView: View {
    @EnvironmentObject var store: AppStore
    @State private var index = 0
    @State private var floaty = false

    private let pages: [OnboardingPage] = [
        .init(emoji: "🍺",
              title: "Tschüss Strichliste",
              subtitle: "Jedes Mitglied bucht seine Getränke selbst – mit Erinnerungen und ordentlich Spaßfaktor. Der Getränkewart hat endlich Feierabend.",
              tint: Theme.gold),
        .init(emoji: "👀",
              title: "Alle im Blick",
              subtitle: "Definiere Mitglieder, die benachrichtigt werden, sobald du am Vereinsheim etwas trinkst. Volle Transparenz – zum Wohle des Vereins.",
              tint: Theme.accent),
        .init(emoji: "🍷",
              title: "Beliebig viele Getränke",
              subtitle: "Pils, Weizen, Sekt, Weinschorle, Sprudel, Snacks … oder eigene Produkte mit Preis, Icon und Namen. Als Kassenwart siehst du jede Buchung.",
              tint: Theme.mint),
        .init(emoji: "📍",
              title: "Standort-Magie",
              subtitle: "Die App begrüßt dich am Vereinsheim und erinnert dich beim Gehen ans Buchen. Direkte Zahlung per PayPal, Apple-Pay & Google-Pay kommt in v2.",
              tint: Color(hex: "#7AB8FF"))
    ]

    var body: some View {
        ZStack {
            AnimatedBackground()

            VStack(spacing: 0) {
                // Brand
                HStack(spacing: 10) {
                    Text("🍻").font(.system(size: 26))
                    Text("Striche")
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.goldGradient)
                    Spacer()
                    Button("Überspringen") { finish() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)

                TabView(selection: $index) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                        pageView(page)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.smooth, value: index)

                // Dots
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == index ? Theme.gold : Color.white.opacity(0.2))
                            .frame(width: i == index ? 26 : 8, height: 8)
                            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: index)
                    }
                }
                .padding(.bottom, 20)

                Button(index == pages.count - 1 ? "Los geht's 🎉" : "Weiter") {
                    Haptics.tap()
                    if index == pages.count - 1 {
                        finish()
                    } else {
                        withAnimation(.smooth) { index += 1 }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                floaty = true
            }
        }
    }

    @ViewBuilder
    private func pageView(_ page: OnboardingPage) -> some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(page.tint.opacity(0.25))
                    .frame(width: 220, height: 220)
                    .blur(radius: 40)
                Circle()
                    .stroke(page.tint.opacity(0.4), lineWidth: 2)
                    .frame(width: 200, height: 200)
                Text(page.emoji)
                    .font(.system(size: 110))
                    .offset(y: floaty ? -10 : 10)
                    .shadow(color: page.tint.opacity(0.6), radius: 30)
            }

            VStack(spacing: 14) {
                Text(page.title)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(page.subtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.horizontal, 28)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
    }

    private func finish() {
        Haptics.success()
        store.completeOnboarding()
    }
}
