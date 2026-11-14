import Combine
import CoreLocation

final class MapLocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var position: CLLocation?
    private let manager = CLLocationManager()
    private var isStarted = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            return
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        position = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
