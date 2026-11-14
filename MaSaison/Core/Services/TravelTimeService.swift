import CoreLocation
import MapKit

/// Driving time between my location and an event's location.
/// The location is only used for this computation (Apple Maps route): it is neither stored nor sent elsewhere.
struct TravelTime: Equatable {
    let duration: TimeInterval
    let distanceKm: Double

    var text: String {
        let minutes = max(1, Int((duration / 60).rounded()))
        let duration = minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
        return "\(duration) en voiture · \(Int(distanceKm.rounded())) km"
    }
}

enum TravelTimeService {
    private static var status: CLAuthorizationStatus { CLLocationManager().authorizationStatus }

    /// True if the user has already authorized location (the computation can start without asking).
    static var isAuthorized: Bool { status == .authorizedWhenInUse || status == .authorizedAlways }
    /// True as long as the question has never been asked.
    static var isNotDetermined: Bool { status == .notDetermined }

    /// Travel time to the location. Triggers the "while using the app" permission request if it has not been asked.
    static func travelTime(toLatitude latitude: Double, longitude: Double) async throws -> TravelTime {
        let departure = try await position()
        let request = MKDirections.Request()
        request.source = MKMapItem(location: departure, address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        request.transportType = .automobile
        do {
            let eta = try await MKDirections(request: request).calculateETA()
            return TravelTime(duration: eta.expectedTravelTime, distanceKm: eta.distance / 1000)
        } catch {
            throw TravelTimeError.routeFailed(error.localizedDescription)
        }
    }

    private enum Position { case location(CLLocation), denied, nothing }

    /// First location received, abandoned after 10 s or if permission is denied.
    private static func position() async throws -> CLLocation {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        let result = await withTaskGroup(of: Position.self) { group in
            group.addTask {
                do {
                    for try await update in CLLocationUpdate.liveUpdates() {
                        if update.authorizationDenied { return .denied }
                        if let location = update.location { return .location(location) }
                    }
                } catch {}
                return .nothing
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(10))
                return .nothing
            }
            let first = await group.next() ?? .nothing
            group.cancelAll()
            return first
        }
        switch result {
        case .location(let location): return location
        case .denied: throw TravelTimeError.denied
        case .nothing: throw TravelTimeError.locationUnavailable
        }
    }
}

enum TravelTimeError: LocalizedError {
    case denied, locationUnavailable, routeFailed(String)

    var errorDescription: String? {
        switch self {
        case .denied: "Localisation refusée : autorise-la dans Réglages > Confidentialité > Service de localisation."
        case .locationUnavailable: "Position introuvable (dans le simulateur : Features > Location)."
        case .routeFailed(let m): "Itinéraire impossible : \(m)"
        }
    }
}
