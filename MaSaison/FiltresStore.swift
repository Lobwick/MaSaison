import Foundation
import Observation

/// Listes des départements et des sports (chargées une fois) + filtres par défaut du profil, sauvegardés dans l'app.
/// Tant que l'utilisateur n'a rien modifié, les valeurs d'origine sont déduites de ses cartes actives
/// (sports des cartes, département de leur comité).
@Observable
final class FiltresStore {
    private static let cleDepartements = "departementsParDefaut"
    private static let cleSports = "sportsParDefaut"

    private(set) var departements: [Departement] = []
    private(set) var sports: [Discipline] = []

    var departementsParDefaut: Set<Int> = [] {
        didSet { if !applique { UserDefaults.standard.set(departementsParDefaut.sorted(), forKey: Self.cleDepartements) } }
    }
    var sportsParDefaut: Set<String> = [] {
        didSet { if !applique { UserDefaults.standard.set(sportsParDefaut.sorted(), forKey: Self.cleSports) } }
    }

    private var applique = false
    private var isLoading = false

    init() {
        applique = true
        if let ids = UserDefaults.standard.array(forKey: Self.cleDepartements) as? [Int] { departementsParDefaut = Set(ids) }
        if let codes = UserDefaults.standard.array(forKey: Self.cleSports) as? [String] { sportsParDefaut = Set(codes) }
        applique = false
    }

    private var departementsPersonnalises: Bool { UserDefaults.standard.object(forKey: Self.cleDepartements) != nil }
    private var sportsPersonnalises: Bool { UserDefaults.standard.object(forKey: Self.cleSports) != nil }

    func loadIfNeeded(auth: AuthModel) async {
        guard (departements.isEmpty || sports.isEmpty), !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        async let deps = try? auth.withSession { try await auth.client.fetchDepartements() }
        async let sps = try? auth.withSession { try await auth.client.fetchDisciplines() }
        departements = await deps ?? departements
        sports = await sps ?? sports
    }

    /// Applique les valeurs d'origine (cartes actives) aux filtres que l'utilisateur n'a pas personnalisés.
    func appliquerOrigine(cartes: [Carte]) {
        applique = true
        defer { applique = false }
        let origine = Self.origine(cartes: cartes, departements: departements, sports: sports)
        if !departementsPersonnalises { departementsParDefaut = origine.departements }
        if !sportsPersonnalises { sportsParDefaut = origine.sports }
    }

    /// Rétablit les valeurs d'origine (efface les personnalisations).
    func retablir(cartes: [Carte]) {
        UserDefaults.standard.removeObject(forKey: Self.cleDepartements)
        UserDefaults.standard.removeObject(forKey: Self.cleSports)
        appliquerOrigine(cartes: cartes)
    }

    static func origine(cartes: [Carte], departements: [Departement], sports: [Discipline]) -> (departements: Set<Int>, sports: Set<String>) {
        let actives = cartes.filter(\.estActive)
        let deps = departements.filter { d in actives.contains { $0.comite.caseInsensitiveCompare(d.nom) == .orderedSame } }.map(\.id)
        let codes = actives.compactMap { sport(pour: $0.discipline, dans: sports)?.code }
        return (Set(deps), Set(codes))
    }

    /// « Cyclocross » → « Cyclo - Cyclosport » ; « VTT » → « Cyclo VTT » ; sinon libellé qui contient le mot.
    static func sport(pour carte: String, dans sports: [Discipline]) -> Discipline? {
        let c = carte.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
        let cible: String
        if c.contains("cyclocross") || c.contains("cyclosport") { cible = "cyclosport" }
        else { cible = c }
        return sports.first { $0.libelle.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).contains(cible) }
    }

    // MARK: affichage

    func resumeDepartements(_ ids: Set<Int>) -> String {
        let numeros = departements.filter { ids.contains($0.id) }.map(\.numero)
        return numeros.isEmpty ? "Tous" : numeros.joined(separator: " · ")
    }

    func resumeSports(_ codes: Set<String>) -> String {
        let noms = sports.filter { codes.contains($0.code) }.map(\.libelle)
        return noms.isEmpty ? "Tous" : noms.joined(separator: " · ")
    }
}
