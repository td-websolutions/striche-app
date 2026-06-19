import SwiftUI

struct LocationSetupCard: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loc = LocationManager()
    @State private var captured = false
    @State private var radius: Double = 120

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Image(systemName: captured ? "checkmark.circle.fill" : "location.circle.fill")
                    .foregroundStyle(captured ? Theme.mint : Theme.gold)
                    .font(.system(size: 24))
                VStack(alignment: .leading, spacing: 2) {
                    Text(captured ? "Standort gespeichert" : "Standort festlegen")
                        .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    Text(captured ? "Vereinsheim-Koordinaten erfasst." : "Tippe, während du am Vereinsheim bist.")
                        .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            if captured {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Radius: \(Int(radius)) m")
                        .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                    Slider(value: $radius, in: 50...500, step: 10)
                        .tint(Theme.gold)
                        .onChange(of: radius) { _, r in
                            if let c = loc.currentCoordinate {
                                store.updateClubLocation(lat: c.latitude, lon: c.longitude, radius: r)
                            }
                        }
                }
            }

            Button {
                Haptics.tap()
                loc.requestOneShot()
            } label: {
                Label(captured ? "Erneut erfassen" : "Aktuellen Standort verwenden",
                      systemImage: "location.fill")
            }
            .buttonStyle(PrimaryButtonStyle(filled: false))
        }
        .padding(18)
        .glassCard()
        .onReceive(loc.$currentCoordinate.compactMap { $0 }) { coord in
            store.updateClubLocation(lat: coord.latitude, lon: coord.longitude, radius: radius)
            withAnimation { captured = true }
            Haptics.success()
        }
    }
}
