import SwiftUI
import MapKit
import CoreLocation
import Combine

/// Address autocomplete backed by Apple's MKLocalSearchCompleter (no API key needed).
/// Publishes live suggestions for a query and resolves a picked suggestion to a coordinate.
@MainActor
final class AddressSearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var query = ""
    @Published var results: [MKLocalSearchCompletion] = []

    private let completer = MKLocalSearchCompleter()
    private var bag = Set<AnyCancellable>()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        $query
            .removeDuplicates()
            .debounce(for: .milliseconds(250), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.count < 3 {
                    self.results = []
                } else {
                    self.completer.queryFragment = trimmed
                }
            }
            .store(in: &bag)
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        MainActor.assumeIsolated { self.results = completer.results }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        MainActor.assumeIsolated { self.results = [] }
    }

    /// Resolve a tapped suggestion into a real map coordinate.
    func resolve(_ completion: MKLocalSearchCompletion) async -> CLLocationCoordinate2D? {
        let request = MKLocalSearch.Request(completion: completion)
        let response = try? await MKLocalSearch(request: request).start()
        return response?.mapItems.first?.placemark.coordinate
    }
}

struct LocationSetupCard: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var loc = LocationManager()
    @StateObject private var search = AddressSearchCompleter()

    @State private var coordinate: CLLocationCoordinate2D?
    @State private var radius: Double = 120
    @State private var isSet = false
    @State private var resolving = false
    @State private var camera: MapCameraPosition = .automatic
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 14) {
            header
            searchField

            if searchFocused && !search.results.isEmpty {
                resultsList
            }

            if isSet, let coordinate {
                mapPreview(coordinate)
                radiusSlider
            }

            currentLocationButton
        }
        .padding(18)
        .glassCard()
        .animation(.smooth, value: isSet)
        .animation(.smooth, value: search.results.count)
        .onAppear(perform: restoreExisting)
        .onReceive(loc.$currentCoordinate.compactMap { $0 }) { coord in
            apply(coord)
            Haptics.success()
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Image(systemName: isSet ? "checkmark.circle.fill" : "location.circle.fill")
                .foregroundStyle(isSet ? Theme.mint : Theme.gold)
                .font(.system(size: 24))
            VStack(alignment: .leading, spacing: 2) {
                Text(isSet ? "Standort gespeichert" : "Standort festlegen")
                    .font(.system(size: 16, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text(isSet ? "Vereinsheim-Koordinaten erfasst."
                           : "Adresse suchen oder aktuellen Standort verwenden.")
                    .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.gold).frame(width: 20)
            TextField("Adresse oder Ort des Vereinsheims", text: $search.query)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .focused($searchFocused)
                .submitLabel(.search)
            if resolving {
                ProgressView().tint(Theme.gold)
            } else if !search.query.isEmpty {
                Button {
                    search.query = ""
                    search.results = []
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var resultsList: some View {
        VStack(spacing: 0) {
            ForEach(Array(search.results.prefix(5).enumerated()), id: \.offset) { _, result in
                Button {
                    pick(result)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.circle.fill")
                            .foregroundStyle(Theme.gold).font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(result.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            if !result.subtitle.isEmpty {
                                Text(result.subtitle)
                                    .font(.system(size: 12, weight: .medium, design: .rounded))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if result != search.results.prefix(5).last {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private func mapPreview(_ coord: CLLocationCoordinate2D) -> some View {
        Map(position: $camera, interactionModes: []) {
            Marker("Vereinsheim", systemImage: "house.fill", coordinate: coord)
                .tint(Theme.gold)
            MapCircle(center: coord, radius: radius)
                .foregroundStyle(Theme.gold.opacity(0.15))
                .stroke(Theme.gold.opacity(0.6), lineWidth: 2)
        }
        .frame(height: 170)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.10), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private var radiusSlider: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Radius: \(Int(radius)) m")
                .font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Slider(value: $radius, in: 50...500, step: 10)
                .tint(Theme.gold)
                .onChange(of: radius) { _, r in
                    guard let coordinate else { return }
                    store.updateClubLocation(lat: coordinate.latitude, lon: coordinate.longitude, radius: r)
                    frameCamera(coordinate)
                }
        }
    }

    private var currentLocationButton: some View {
        Button {
            Haptics.tap()
            loc.requestOneShot()
        } label: {
            Label("Aktuellen Standort verwenden", systemImage: "location.fill")
        }
        .buttonStyle(PrimaryButtonStyle(filled: false))
    }

    // MARK: Actions

    private func restoreExisting() {
        guard let club = store.club else { return }
        radius = club.geofenceRadius
        if let lat = club.latitude, let lon = club.longitude {
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            coordinate = coord
            isSet = true
            frameCamera(coord)
        }
    }

    private func pick(_ result: MKLocalSearchCompletion) {
        searchFocused = false
        search.query = result.title
        search.results = []
        resolving = true
        Task {
            let coord = await search.resolve(result)
            resolving = false
            if let coord {
                apply(coord)
                Haptics.success()
            }
        }
    }

    private func apply(_ coord: CLLocationCoordinate2D) {
        coordinate = coord
        store.updateClubLocation(lat: coord.latitude, lon: coord.longitude, radius: radius)
        isSet = true
        searchFocused = false
        search.results = []
        frameCamera(coord)
    }

    private func frameCamera(_ coord: CLLocationCoordinate2D) {
        let span = max(radius * 4, 300)
        camera = .region(MKCoordinateRegion(center: coord,
                                            latitudinalMeters: span,
                                            longitudinalMeters: span))
    }
}
