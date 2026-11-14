import Foundation

struct MapPin: Identifiable {
    struct Element {
        let event: Event
        let latitude: Double
        let longitude: Double
    }

    let id: String
    let latitude: Double
    let longitude: Double
    let events: [Event]

    static func cluster(_ elements: [Element], radiusKm: Double = 5) -> [MapPin] {
        struct Cluster {
            var latitude: Double
            var longitude: Double
            var elements: [Element]
        }
        var groups: [Cluster] = []
        for element in elements {
            if let index = groups.firstIndex(where: { distanceKm(lat1: $0.latitude, lon1: $0.longitude, lat2: element.latitude, lon2: element.longitude) <= radiusKm }) {
                var group = groups[index]
                group.elements.append(element)
                let n = Double(group.elements.count)
                group.latitude = ((group.latitude * (n - 1)) + element.latitude) / n
                group.longitude = ((group.longitude * (n - 1)) + element.longitude) / n
                groups[index] = group
            } else {
                groups.append(Cluster(latitude: element.latitude, longitude: element.longitude, elements: [element]))
            }
        }
        return groups.map { group in
            let ids = group.elements.map { String($0.event.id) }.sorted().joined(separator: "-")
            let events = group.elements.map(\.event).sorted { ($0.startDate ?? .distantFuture, $0.id) < ($1.startDate ?? .distantFuture, $1.id) }
            return MapPin(id: ids, latitude: group.latitude, longitude: group.longitude, events: events)
        }
    }

    private static func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}
