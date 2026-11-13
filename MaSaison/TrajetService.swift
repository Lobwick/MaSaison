import CoreLocation
import MapKit

/// Temps de trajet en voiture entre ma position et le lieu d'une manifestation.
/// La position sert uniquement à ce calcul (itinéraire Apple Plans) : elle n'est ni enregistrée ni envoyée ailleurs.
struct Trajet: Equatable {
    let duree: TimeInterval
    let distanceKm: Double

    var texte: String {
        let minutes = max(1, Int((duree / 60).rounded()))
        let duree = minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
        return "\(duree) en voiture · \(Int(distanceKm.rounded())) km"
    }
}

enum TrajetService {
    private static var statut: CLAuthorizationStatus { CLLocationManager().authorizationStatus }

    /// Vrai si l'utilisateur a déjà autorisé la localisation (le calcul peut partir sans rien demander).
    static var autorise: Bool { statut == .authorizedWhenInUse || statut == .authorizedAlways }
    /// Vrai tant que la question n'a jamais été posée.
    static var nonDemande: Bool { statut == .notDetermined }

    /// Temps de trajet jusqu'au lieu. Déclenche la demande d'autorisation « quand l'app est active » si elle n'a pas été posée.
    static func trajet(versLatitude latitude: Double, longitude: Double) async -> Trajet? {
        guard let depart = await position() else { return nil }
        let requete = MKDirections.Request()
        requete.source = MKMapItem(location: depart, address: nil)
        requete.destination = MKMapItem(location: CLLocation(latitude: latitude, longitude: longitude), address: nil)
        requete.transportType = .automobile
        guard let eta = try? await MKDirections(request: requete).calculateETA() else { return nil }
        return Trajet(duree: eta.expectedTravelTime, distanceKm: eta.distance / 1000)
    }

    /// Première position reçue, abandonnée après 10 s ou si l'autorisation est refusée.
    private static func position() async -> CLLocation? {
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        return await withTaskGroup(of: CLLocation?.self) { groupe in
            groupe.addTask {
                do {
                    for try await maj in CLLocationUpdate.liveUpdates() {
                        if maj.authorizationDenied { return nil }
                        if let lieu = maj.location { return lieu }
                    }
                } catch {}
                return nil
            }
            groupe.addTask {
                try? await Task.sleep(for: .seconds(10))
                return nil
            }
            let premier = await groupe.next() ?? nil
            groupe.cancelAll()
            return premier
        }
    }
}
