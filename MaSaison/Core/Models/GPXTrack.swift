import CoreLocation
import Foundation

/// GPX track: points, distance, elevation gain and elevation profile.
struct GPXTrack {
    struct Point {
        let coordinate: CLLocationCoordinate2D
        let altitude: Double?
        let distanceKm: Double   // cumulative distance from the start
    }

    let points: [Point]

    var coordinates: [CLLocationCoordinate2D] { points.map(\.coordinate) }
    var distanceKm: Double { points.last?.distanceKm ?? 0 }
    var altitudes: [Double] { points.compactMap(\.altitude) }
    var maxAltitude: Double? { altitudes.max() }
    var minAltitude: Double? { altitudes.min() }
    var hasElevationProfile: Bool { altitudes.count >= 2 }

    /// Cumulative elevation gain (2 m threshold to ignore GPS noise).
    var elevationGain: Double {
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
        guard parser.parse(), delegate.raw.count >= 2 else { return nil }

        var points: [Point] = []
        var cumulative = 0.0
        var previous: CLLocation?
        for p in delegate.raw {
            let loc = CLLocation(latitude: p.lat, longitude: p.lon)
            if let previous { cumulative += loc.distance(from: previous) / 1000 }
            previous = loc
            points.append(Point(coordinate: loc.coordinate, altitude: p.ele, distanceKm: cumulative))
        }
        return GPXTrack(points: points)
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        var raw: [(lat: Double, lon: Double, ele: Double?)] = []
        private var current: (lat: Double, lon: Double, ele: Double?)?
        private var text = ""
        private var inElevation = false

        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
            if name == "trkpt" || name == "rtept", let lat = attributes["lat"].flatMap(Double.init), let lon = attributes["lon"].flatMap(Double.init) {
                current = (lat, lon, nil)
            } else if name == "ele", current != nil {
                inElevation = true
                text = ""
            }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            if inElevation { text += string }
        }

        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            if name == "ele", inElevation {
                current?.ele = Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
                inElevation = false
            } else if name == "trkpt" || name == "rtept", let c = current {
                raw.append(c)
                current = nil
            }
        }
    }
}
