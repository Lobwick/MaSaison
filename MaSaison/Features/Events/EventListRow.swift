import SwiftUI

struct EventListRow: View {
    let event: Event
    let status: TrackingStatus

    private var registered: Bool { status == .registered || status == .confirmed }
    private var statusColor: Color { status == .confirmed ? Theme.accent : Theme.secondary }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var time: String? {
        guard let raw = event.startTimeText?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        if raw.contains(":") { return raw }
        if let d = Date.fr("HH:mm:ss").date(from: raw) { return Self.timeFormatter.string(from: d) }
        if let d = Date.fr("HH:mm").date(from: raw) { return Self.timeFormatter.string(from: d) }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            DateAndTime(date: event.startDate, time: time, tint: status.color,
                        textOnTint: status == .wishlist ? Theme.text : Theme.bg)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.name)
                    .font(.barlow(17, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text([event.address?.city?.capitalized, event.kind?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if registered { TrackingStatusBadge(status: status) }
            }
            Spacer()
            if status.isWishlistEditable {
                Color.clear.frame(width: 36, height: 36) // placeholder for the wishlist bookmark
            }
            if registered {
                Image(systemName: status == .confirmed ? "checkmark.circle.fill" : "hourglass.circle.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(statusColor)
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .card(border: registered ? statusColor.opacity(0.35) : Theme.line, radius: 24, padding: 12)
    }
}
