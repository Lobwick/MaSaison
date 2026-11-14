import SwiftUI

/// Status of an event for the user. Progression: untracked ⇄ wishlist → registered → confirmed.
enum TrackingStatus {
    /// Neither wishlisted nor registered.
    case untracked
    /// In the wishlist ("bucket list"), a choice local to the device.
    case wishlist
    /// Registered on the site, payment not yet validated.
    case registered
    /// Registration paid (or free): nothing left to do.
    case confirmed

    /// Wishlist yellow, registered blue, confirmed green; `nil` when untracked.
    var color: Color? {
        switch self {
        case .untracked: nil
        case .wishlist: Theme.wishlist
        case .registered: Theme.secondary
        case .confirmed: Theme.accent
        }
    }

    /// The wishlist can only be toggled manually while not registered.
    var isWishlistEditable: Bool { self == .untracked || self == .wishlist }
}
