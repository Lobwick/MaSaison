import Foundation
import Observation
import SwiftUI
import UserNotifications

/// Event tracking: wishlist stored on device, registrations and payments read from the site.
@Observable
final class RaceTrackingStore {
    private static let wishlistKey = "enviesManifestations"
    private static let deadlinesKey = "echeancesManifestations"

    /// Name and registration deadline of a tracked event, for reminders.
    struct Deadline: Codable {
        let name: String
        let closesAt: Date
        /// Optional: missing from deadlines stored before the opening reminder was added.
        var opensAt: Date?

        /// Keys persisted in UserDefaults: keep them stable.
        enum CodingKeys: String, CodingKey {
            case name = "libelle"
            case closesAt = "cloture"
            case opensAt = "ouverture"
        }
    }
    /// Deadlines of wishlisted or registered events (stored: reminders can be rescheduled offline).
    private var deadlines: [Int: Deadline]
    private(set) var wishlistIDs: Set<Int>
    /// Registered, payment pending (order to pay or registration in draft).
    private(set) var registeredIDs: Set<Int> = []
    /// Registration confirmed by payment.
    private(set) var confirmedIDs: Set<Int> = []

    init() {
        wishlistIDs = Set(UserDefaults.standard.array(forKey: Self.wishlistKey) as? [Int] ?? [])
        deadlines = UserDefaults.standard.data(forKey: Self.deadlinesKey)
            .flatMap { try? JSONDecoder().decode([Int: Deadline].self, from: $0) } ?? [:]
    }

    func status(_ event: Int) -> TrackingStatus {
        if confirmedIDs.contains(event) { return .confirmed }
        if registeredIDs.contains(event) { return .registered }
        if wishlistIDs.contains(event) { return .wishlist }
        return .untracked
    }

    func toggleWishlist(_ event: Event) {
        guard status(event.id).isWishlistEditable else { return }
        if wishlistIDs.remove(event.id) == nil { wishlistIDs.insert(event.id) }
        saveWishlist()
        rememberDeadlines([event])
    }

    /// Records the deadlines of tracked events among those displayed, then reschedules reminders if needed.
    func rememberDeadlines(_ events: [Event]) {
        var changed = false
        for m in events where wishlistIDs.contains(m.id) || registeredIDs.contains(m.id) {
            guard let closesAt = m.registrationClosesAt else { continue }
            let opensAt = m.registrationOpensAt
            if deadlines[m.id]?.closesAt == closesAt && deadlines[m.id]?.opensAt == opensAt { continue }
            deadlines[m.id] = Deadline(name: m.name, closesAt: closesAt, opensAt: opensAt)
            changed = true
        }
        if changed { saveDeadlines() }
        Task { await rescheduleReminders() }
    }

    /// Reloads registrations and orders to pay; keeps the previous state if the site does not respond.
    func refresh(_ auth: AuthModel) async {
        guard let registrations = try? await auth.withSession({ try await auth.client.fetchRegistrations() }) else { return }
        let orders = (try? await auth.withSession { try await auth.client.fetchOrders() }) ?? []
        var pending = Set<Int>(), paid = Set<Int>()
        for i in registrations {
            let isDraft = i.entries.contains { $0.status.lowercased().contains("saisie") }
            // same matching as RegistrationSection: the order carries the event name
            let hasOrderToPay = orders.contains { $0.name.localizedCaseInsensitiveContains(i.name) }
            if isDraft || hasOrderToPay { pending.insert(i.eventID) } else { paid.insert(i.eventID) }
        }
        registeredIDs = pending
        confirmedIDs = paid
        // once registered, the wish is fulfilled: it leaves the list
        let fulfilled = wishlistIDs.intersection(pending.union(paid))
        if !fulfilled.isEmpty {
            wishlistIDs.subtract(fulfilled)
            saveWishlist()
        }
        // pending registrations whose deadline is unknown: fetch it
        let withoutDeadline = registrations.filter { pending.contains($0.eventID) && deadlines[$0.eventID] == nil }
        var found: [Event] = []
        for i in withoutDeadline {
            if let m = try? await auth.withSession({ try await auth.client.fetchEvent(id: i.eventID, name: i.name) }) {
                found.append(m)
            }
        }
        rememberDeadlines(found)
    }

    // MARK: closing reminders

    private static let reminderPrefix = "cloture-"

    /// Wishlisted events whose registration is not open yet: at opening time.
    /// On closing day, at 9:00 then 20:00, for each wishlisted or registered-but-unpaid race.
    /// Everything is recomputed on each call: a confirmed or removed race loses its reminders.
    func rescheduleReminders() async {
        let center = UNUserNotificationCenter.current()
        let staleIDs = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.reminderPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: staleIDs)

        // keep only deadlines that are still useful
        let trackedIDs = wishlistIDs.union(registeredIDs)
        let countBefore = deadlines.count
        deadlines = deadlines.filter { trackedIDs.contains($0.key) && $0.value.closesAt > Date() }
        if deadlines.count != countBefore { saveDeadlines() }

        let requests = deadlines.flatMap { id, e in reminders(id: id, deadline: e) }
        guard !requests.isEmpty, await requestNotificationPermission(center) else { return }
        for request in requests { try? await center.add(request) }
    }

    private func reminders(id: Int, deadline e: Deadline) -> [UNNotificationRequest] {
        var parisCalendar = Calendar(identifier: .gregorian)
        parisCalendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let registered = registeredIDs.contains(id)
        let deadlineTime = e.closesAt.formatted(time)
        var requests: [UNNotificationRequest] = []
        if !registered, let opensAt = e.opensAt, opensAt > Date(), opensAt < e.closesAt {
            let content = UNMutableNotificationContent()
            content.title = "Inscriptions ouvertes"
            content.body = "\(e.name) est dans tes envies : tu peux t'inscrire jusqu'au \(e.closesAt.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Locale(identifier: "fr_FR")))) à \(deadlineTime)."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: parisCalendar.dateComponents(in: parisCalendar.timeZone, from: opensAt).triggerComponents, repeats: false)
            requests.append(UNNotificationRequest(identifier: "\(Self.reminderPrefix)\(id)-ouverture", content: content, trigger: trigger))
        }
        return requests + [9, 20].compactMap { h -> UNNotificationRequest? in
            // useless after closing or already past
            guard let fireDate = parisCalendar.date(bySettingHour: h, minute: 0, second: 0, of: e.closesAt),
                  fireDate < e.closesAt, fireDate > Date() else { return nil }
            let content = UNMutableNotificationContent()
            content.title = h == 9 ? "Clôture des inscriptions aujourd'hui" : "Dernier rappel : clôture ce soir"
            content.body = registered
                ? "\(e.name) : ton inscription n'est pas encore payée. Clôture à \(deadlineTime)."
                : "\(e.name) est dans tes envies. Inscris-toi avant \(deadlineTime)."
            content.sound = .default
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: parisCalendar.dateComponents(in: parisCalendar.timeZone, from: fireDate).triggerComponents, repeats: false)
            return UNNotificationRequest(identifier: "\(Self.reminderPrefix)\(id)-\(h)", content: content, trigger: trigger)
        }
    }

    /// Asks for permission the first time there is a reminder to schedule.
    private func requestNotificationPermission(_ center: UNUserNotificationCenter) async -> Bool {
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default: return false
        }
    }

    private func saveDeadlines() {
        if let data = try? JSONEncoder().encode(deadlines) { UserDefaults.standard.set(data, forKey: Self.deadlinesKey) }
    }

    private func saveWishlist() {
        UserDefaults.standard.set(Array(wishlistIDs), forKey: Self.wishlistKey)
    }
}

private extension DateComponents {
    /// Components useful for a calendar trigger (with the time zone), without the fields that disturb it.
    var triggerComponents: DateComponents {
        DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
