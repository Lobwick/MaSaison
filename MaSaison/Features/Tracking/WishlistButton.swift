import SwiftUI

/// Wishlist bookmark while not registered, then a Registered / Confirmed badge.
struct WishlistButton: View {
    let event: Event
    var size: CGFloat = 18
    @Environment(RaceTrackingStore.self) private var tracking

    var body: some View {
        let eventID = event.id
        let status = tracking.status(eventID)
        if status.isWishlistEditable {
            let isActive = status == .wishlist
            Button {
                tracking.toggleWishlist(event)
            } label: {
                Image(systemName: isActive ? "bookmark.fill" : "bookmark")
                    .font(.system(size: size, weight: .semibold))
                    .foregroundStyle(isActive ? Theme.wishlist : Theme.faint)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: isActive)
            .accessibilityLabel(isActive ? "Retirer de ma liste d'envies" : "Ajouter à ma liste d'envies")
        } else {
            TrackingStatusBadge(status: status)
        }
    }
}

/// "Envie", "Inscrit · à payer" or "Validé" pill; nothing for `.untracked`.
struct TrackingStatusBadge: View {
    let status: TrackingStatus

    var body: some View {
        if let (text, icon, color) = appearance {
            Label(text, systemImage: icon)
                .font(.barlow(12, .semibold))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(color.opacity(0.12), in: Capsule())
        }
    }

    private var appearance: (String, String, Color)? {
        switch status {
        case .untracked: nil
        case .wishlist: ("Envie", "bookmark.fill", Theme.wishlist)
        case .registered: ("Inscrit · à payer", "hourglass", Theme.secondary)
        case .confirmed: ("Validé", "checkmark.seal.fill", Theme.accent)
        }
    }
}
