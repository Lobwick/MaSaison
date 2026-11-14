import EventKit
import Foundation

enum CalendarError: LocalizedError {
    case accessDenied
    case missingTimes
    case eventNotFound

    var errorDescription: String? {
        switch self {
        case .accessDenied: "Accès à l'agenda refusé (Réglages > Confidentialité > Calendriers)."
        case .missingTimes: "Cette course n'a pas d'horaires."
        case .eventNotFound: "L'événement n'est plus dans ton agenda (supprimé ?). Tu peux le rajouter."
        }
    }
}

/// Adds a race to the calendar: from (call time − warm-up) to (start + duration).
enum CalendarService {
    struct TimeSlot {
        let warmUp: Date
        let callTime: Date
        let departure: Date
        let end: Date
        var start: Date { warmUp }
    }

    static func slot(event: Event, race: Race, warmUpMinutes: Int) -> TimeSlot? {
        let info = race.info
        guard let departure = date(event.startDateText, info.startTime ?? info.callTime ?? event.startTimeText),
              let callTime = date(event.startDateText, info.callTime ?? info.startTime ?? event.startTimeText)
        else { return nil }
        let first = min(callTime, departure)
        return TimeSlot(
            warmUp: first.addingTimeInterval(-Double(warmUpMinutes) * 60),
            callTime: callTime,
            departure: departure,
            end: departure.addingTimeInterval(Double(info.durationMinutes) * 60)
        )
    }

    /// Time range covered by races, from the earliest call-up to the latest finish; `nil` if no times are known.
    static func timeRange(event: Event, races: [Race]) -> DateInterval? {
        let slots = races.compactMap { slot(event: event, race: $0, warmUpMinutes: 0) }
        guard let start = slots.map({ min($0.callTime, $0.departure) }).min(),
              let end = slots.map(\.end).max(), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Creates the event and returns its identifier.
    static func addToCalendar(event: Event, race: Race, warmUpMinutes: Int, travelTime: TravelTime? = nil) async throws -> String {
        guard let slot = slot(event: event, race: race, warmUpMinutes: warmUpMinutes) else {
            throw CalendarError.missingTimes
        }
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw CalendarError.accessDenied }

        let ekEvent = EKEvent(eventStore: store)
        ekEvent.calendar = store.defaultCalendarForNewEvents
        ekEvent.title = title(event: event, race: race)
        ekEvent.startDate = slot.start
        ekEvent.endDate = slot.end

        if let address = event.address {
            let title = [address.street, address.postalCode, address.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").capitalized
            let location = EKStructuredLocation(title: title)
            if let c = address.coordinate { location.geoLocation = CLLocation(latitude: c.latitude, longitude: c.longitude) }
            ekEvent.structuredLocation = location
        }

        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        var notes: [String] = []
        if warmUpMinutes > 0 { notes.append("Échauffement : \(slot.warmUp.formatted(time)) (\(warmUpMinutes) min avant l'appel)") }
        notes.append("Appel : \(slot.callTime.formatted(time))")
        notes.append("Départ : \(slot.departure.formatted(time))")
        if let travelTime { notes.append(travelTimeLine(travelTime, slot: slot)) }
        if let o = event.structure?.name { notes.append("Organisateur : \(o)") }
        // EventKit has no public API to attach a file: the GPX is referenced by its link.
        if let gpx = event.gpxURL {
            ekEvent.url = gpx
            notes.append("Tracé GPX : \(gpx.absoluteString)")
        }
        ekEvent.notes = notes.joined(separator: "\n")

        try store.save(ekEvent, span: .thisEvent)
        return ekEvent.eventIdentifier ?? ""
    }

    private static func title(event: Event, race: Race) -> String {
        "\(event.name.capitalized) – \(race.level.name)"
    }

    /// Finds events by title and time (the identifier is not always returned with write-only access).
    /// Several copies may exist (repeated adds): all of them are returned.
    private static func findEvents(in store: EKEventStore, event: Event, race: Race, slot: TimeSlot) -> [EKEvent] {
        let title = title(event: event, race: race)
        let predicate = store.predicateForEvents(withStart: slot.start.addingTimeInterval(-86_400),
                                                end: slot.end.addingTimeInterval(86_400), calendars: nil)
        let candidates = store.events(matching: predicate).filter { $0.title == title }
        let sameTime = candidates.filter { abs($0.startDate.timeIntervalSince(slot.start)) < 60 }
        return sameTime.isEmpty ? candidates : sameTime
    }

    /// "Trajet : 35 min en voiture · 28 km, partir vers 11:10 (calculé le 13 nov. à 10:32)".
    private static func travelTimeLine(_ travelTime: TravelTime, slot: TimeSlot) -> String {
        let fr = Locale(identifier: "fr_FR")
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(fr)
        let computedFormat = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(fr)
        let leaveAt = slot.start.addingTimeInterval(-travelTime.duration)
        return "Trajet : \(travelTime.text), partir vers \(leaveAt.formatted(time)) (calculé le \(Date().formatted(computedFormat)))"
    }

    struct TravelTimeUpdate {
        let identifier: String
        let count: Int
        let calendarNames: [String]
    }

    /// Replaces the "Trajet :" line of already-created events without touching the rest of the notes.
    /// Finding the event requires full calendar access: it is only requested at that point.
    static func updateTravelTimeInEvents(identifier: String, event: Event, race: Race,
                                  warmUpMinutes: Int, travelTime: TravelTime) async throws -> TravelTimeUpdate {
        guard let slot = slot(event: event, race: race, warmUpMinutes: warmUpMinutes) else {
            throw CalendarError.missingTimes
        }
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw CalendarError.accessDenied }

        var events = findEvents(in: store, event: event, race: race, slot: slot)
        if !identifier.isEmpty, let direct = store.event(withIdentifier: identifier),
           !events.contains(where: { $0.eventIdentifier == direct.eventIdentifier }) {
            events.append(direct)
        }
        guard !events.isEmpty else { throw CalendarError.eventNotFound }

        let row = travelTimeLine(travelTime, slot: slot)
        for ekEvent in events {
            var rows = (ekEvent.notes ?? "").components(separatedBy: "\n").filter { !$0.hasPrefix("Trajet :") }
            while rows.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { rows.removeLast() }
            rows.append(row)
            ekEvent.notes = rows.joined(separator: "\n")
            try store.save(ekEvent, span: .thisEvent, commit: false)
        }
        try store.commit()
        return TravelTimeUpdate(identifier: events[0].eventIdentifier ?? identifier,
                         count: events.count,
                         calendarNames: Array(Set(events.map { $0.calendar.title })).sorted())
    }

    private static func date(_ day: String, _ time: String?) -> Date? {
        guard let time else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.date(from: "\(day) \(time)")
    }
}
