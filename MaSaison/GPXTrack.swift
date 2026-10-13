import CoreLocation
import Foundation

/// Tracé GPX : points, distance, dénivelé et profil altimétrique.
struct GPXTrack {
    struct Point {
        let coordinate: CLLocationCoordinate2D
        let altitude: Double?
        let distanceKm: Double   // distance cumulée depuis le départ
    }

    let points: [Point]

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
    var distanceKm: Double { points.last?.distanceKm ?? 0 }
    var altitudes: [Double] { points.compactMap(\.altitude) }
    var altitudeMax: Double? { altitudes.max() }
    var altitudeMin: Double? { altitudes.min() }
    var aProfil: Bool { altitudes.count >= 2 }

    /// Dénivelé positif cumulé (seuil de 2 m pour ignorer le bruit du GPS).
    var denivelePositif: Double {
        var total = 0.0, reference: Double?
        for a in altitudes {
            guard let r = reference else { reference = a; continue }
            if a - r >= 2 { total += a - r; reference = a } else if r - a >= 2 { reference = a }
        }
        return total
    }

    static func parse(_ data: Data) -> GPXTrack? {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse(), delegate.brut.count >= 2 else { return nil }

        var points: [Point] = []
        var cumul = 0.0
        var precedent: CLLocation?
        for p in delegate.brut {
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            if let precedent { cumul += loc.distance(from: precedent) / 1000 }
            precedent = loc
            points.append(Point(coordinate: loc.coordinate, altitude: p.ele, distanceKm: cumul))
        }
        return GPXTrack(points: points)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var brut: [(lat: Double, lon: Double, ele: Double?)] = []
        private var courant: (lat: Double, lon: Double, ele: Double?)?
        private var texte = ""
        private var dansEle = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if name == "trkpt" || name == "rtept", let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                courant = (lat, lon, nil)
            } else if name == "ele", courant != nil {
                dansEle = true
                texte = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if dansEle { texte += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "ele", dansEle {
                courant?.ele = Double(texte.trimmingCharacters(in: .whitespacesAndNewlines))
                dansEle = false
            } else if name == "trkpt" || name == "rtept", let c = courant {
                brut.append(c)
                courant = nil
            }
        }
    }
}
