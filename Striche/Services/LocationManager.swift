import CoreLocation
import Combine

/// Monitors arrival/departure at the Vereinsheim and fires welcome / goodbye events.
@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var isInside = false
    @Published var lastEvent: String?
    @Published var currentCoordinate: CLLocationCoordinate2D?

    private let manager = CLLocationManager()
    private var clubName: String = "deinem Verein"
    private var center: CLLocationCoordinate2D?
    private var radius: Double = 120
    private var departureTimer: Timer?

    /// Called whenever the member arrives (welcome) — UI can show banner + sound.
    var onArrive: ((String) -> Void)?
    /// Called 10 min after leaving — reminder to book drinks.
    var onLeave: ((String) -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func configure(clubName: String, lat: Double?, lon: Double?, radius: Double) {
        self.clubName = clubName
        self.radius = radius
        if let lat, let lon { self.center = CLLocationCoordinate2D(latitude: lat, longitude: lon) }
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func startMonitoring() {
        manager.startUpdatingLocation()
    }

    /// For setup: grab one location fix to use as the Vereinsheim coordinate.
    func requestOneShot() {
        manager.requestWhenInUseAuthorization()
        manager.requestLocation()
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.currentCoordinate = loc.coordinate
            self.evaluate(loc)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) { }

    private func evaluate(_ loc: CLLocation) {
        guard let center else { return }
        let clubLoc = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let distance = loc.distance(from: clubLoc)
        let nowInside = distance <= radius

        if nowInside && !isInside {
            isInside = true
            departureTimer?.invalidate()
            let msg = "Herzlich Willkommen beim \(clubName)! 🍻"
            lastEvent = msg
            onArrive?(clubName)
        } else if !nowInside && isInside {
            isInside = false
            // Departure reminder 10 minutes later.
            departureTimer?.invalidate()
            departureTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.onLeave?(self.clubName)
                }
            }
        }
    }
}
