import Foundation
import Observation

/// Department and sport lists (loaded once) + the profile's default filters, saved on device.
/// As long as the user has not changed anything, defaults are derived from their active cards
/// (sports of the cards, department of their committee).
@Observable
final class FilterStore {
    private static let departmentsKey = "departementsParDefaut"
    private static let sportsKey = "sportsParDefaut"

    private(set) var departments: [Department] = []
    private(set) var sports: [Discipline] = []

    var defaultDepartments: Set<Int> = [] {
        didSet { if !isApplying { UserDefaults.standard.set(defaultDepartments.sorted(), forKey: Self.departmentsKey) } }
    }
    var defaultSports: Set<String> = [] {
        didSet { if !isApplying { UserDefaults.standard.set(defaultSports.sorted(), forKey: Self.sportsKey) } }
    }

    private var isApplying = false
    private var isLoading = false

    init() {
        isApplying = true
        if let ids = UserDefaults.standard.array(forKey: Self.departmentsKey) as? [Int] { defaultDepartments = Set(ids) }
        if let codes = UserDefaults.standard.array(forKey: Self.sportsKey) as? [String] { defaultSports = Set(codes) }
        isApplying = false
    }

    private var hasCustomDepartments: Bool { UserDefaults.standard.object(forKey: Self.departmentsKey) != nil }
    private var hasCustomSports: Bool { UserDefaults.standard.object(forKey: Self.sportsKey) != nil }

    func loadIfNeeded(auth: AuthModel) async {
        guard (departments.isEmpty || sports.isEmpty), !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let deps = try? auth.withSession { try await auth.client.fetchDepartments() }
        async let sps = try? auth.withSession { try await auth.client.fetchDisciplines() }
        departments = await deps ?? departments
        sports = await sps ?? sports
    }

    /// Applies the card-derived defaults to the filters the user has not customized.
    func applyCardDefaults(cards: [LicenseCard]) {
        isApplying = true
        defer { isApplying = false }
        let defaults = Self.defaults(cards: cards, departments: departments, sports: sports)
        if !hasCustomDepartments { defaultDepartments = defaults.departments }
        if !hasCustomSports { defaultSports = defaults.sports }
    }

    /// Restores the card-derived defaults (clears customizations).
    func resetToDefaults(cards: [LicenseCard]) {
        UserDefaults.standard.removeObject(forKey: Self.departmentsKey)
        UserDefaults.standard.removeObject(forKey: Self.sportsKey)
        applyCardDefaults(cards: cards)
    }

    static func defaults(cards: [LicenseCard], departments: [Department], sports: [Discipline]) -> (departments: Set<Int>, sports: Set<String>) {
        let activeCards = cards.filter(\.isActive)
        let deps = departments.filter { d in activeCards.contains { $0.committee.caseInsensitiveCompare(d.name) == .orderedSame } }.map(\.id)
        let codes = activeCards.compactMap { sport(for: $0.discipline, in: sports)?.code }
        return (Set(deps), Set(codes))
    }

    /// "Cyclocross" → "Cyclo - Cyclosport"; "VTT" → "Cyclo VTT"; otherwise the label containing the word.
    static func sport(for card: String, in sports: [Discipline]) -> Discipline? {
        let c = card.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let target: String
        if c.contains("cyclocross") || c.contains("cyclosport") { target = "cyclosport" }
        else { target = c }
        return sports.first { $0.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(target) }
    }

    // MARK: display

    func departmentsSummary(_ ids: Set<Int>) -> String {
        let numbers = departments.filter { ids.contains($0.id) }.map(\.number)
        return numbers.isEmpty ? "Tous" : numbers.joined(separator: " · ")
    }

    func sportsSummary(_ codes: Set<String>) -> String {
        let names = sports.filter { codes.contains($0.code) }.map(\.name)
        return names.isEmpty ? "Tous" : names.joined(separator: " · ")
    }
}
