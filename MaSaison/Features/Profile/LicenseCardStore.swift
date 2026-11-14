import Foundation
import Observation

/// The member's license cards, and the "this event is for me" rule.
@Observable
final class LicenseCardStore {
    private(set) var cards: [LicenseCard] = []
    private var isLoading = false

    var activeCards: [LicenseCard] { cards.filter(\.isActive) }

    func load(auth: AuthModel) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        cards = (try? await auth.withSession { try await auth.client.fetchCards() }) ?? cards
    }

    /// An event is "for me" if an active card matches its discipline
    /// (event type) and one of its races:
    /// - card with a category (1st, 2nd, 3rd…) → compare the category;
    /// - otherwise → compare the card's age bracket ("Adulte masculin 30/39" ↔ "30/39 ans").
    func matches(_ m: Event) -> Bool {
        let type = Self.normalize(m.kind?.name ?? "")
        return activeCards.contains { card in
            guard type.hasPrefix(Self.normalize(card.discipline)) else { return false }
            if let level = card.level {
                return m.races.contains { Self.sameCategory(level, $0.level.name) }
            }
            if let age = card.ageCategory.flatMap(Self.ageBracket) {
                return m.races.contains { Self.ageBracket($0.level.name) == age }
            }
            return true
        }
    }

    /// Does this race of the event match one of my active cards?
    func matches(race: Race, in m: Event) -> Bool {
        let type = Self.normalize(m.kind?.name ?? "")
        return activeCards.contains { card in
            guard type.hasPrefix(Self.normalize(card.discipline)) else { return false }
            if let level = card.level { return Self.sameCategory(level, race.level.name) }
            if let age = card.ageCategory.flatMap(Self.ageBracket) { return Self.ageBracket(race.level.name) == age }
            return true
        }
    }

    /// "30/39" or "50+" extracted from a label ("Adulte masculin 30/39", "50 ans et +").
    nonisolated static func ageBracket(_ text: String) -> String? {
        if let m = text.firstMatch(of: #/(\d{1,2})\s*/\s*(\d{1,2})/#) { return "\(m.output.1)/\(m.output.2)" }
        if let m = text.firstMatch(of: #/(\d{1,2})\s*(?:ans)?\s*et\s*\+/#) { return "\(m.output.1)+" }
        return nil
    }

    /// "3ème catégorie" ≈ "3e catégorie" (compares the number), otherwise normalized text.
    nonisolated private static func sameCategory(_ card: String, _ race: String) -> Bool {
        let a = normalize(card), b = normalize(race)
        if let na = number(a), let nb = number(b) { return na == nb && b.contains("categorie") }
        return a == b
    }

    nonisolated private static func number(_ s: String) -> String? {
        s.firstMatch(of: #/\d+/#).map { String($0.output) }
    }

    nonisolated private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR"))
    }
}
