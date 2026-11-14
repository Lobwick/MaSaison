import Foundation
import Observation

/// Remembers races added to the calendar (write-only access cannot read the calendar back).
@Observable
final class CalendarStore {
    private static let key = "evenementsAgenda"
    /// "eventID:raceID" → EventKit event identifier
    private(set) var events: [String: String]

    init() {
        events = UserDefaults.standard.dictionary(forKey: Self.key) as? [String: String] ?? [:]
    }

    func isAdded(event: Int, race: Int) -> Bool { events["\(event):\(race)"] != nil }
    func isAdded(event: Int) -> Bool { events.keys.contains { $0.hasPrefix("\(event):") } }

    func identifier(event: Int, race: Int) -> String? { events["\(event):\(race)"] }

    func remove(event: Int, race: Int) {
        events["\(event):\(race)"] = nil
        UserDefaults.standard.set(events, forKey: Self.key)
    }

    func save(event: Int, race: Int, identifier: String) {
        events["\(event):\(race)"] = identifier
        UserDefaults.standard.set(events, forKey: Self.key)
    }
}
