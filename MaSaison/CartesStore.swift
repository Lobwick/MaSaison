import Foundation
import Observation

/// Cartes du licencié, et règle « cette manifestation est pour moi ».
@Observable
final class CartesStore {
    private(set) var cartes: [Carte] = []
    private var isLoading = false

    var cartesActives: [Carte] { cartes.filter(\.estActive) }

    func load(auth: AuthModel) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        cartes = (try? await auth.withSession { try await auth.client.fetchCartes() }) ?? cartes
    }

    /// Une manifestation est « pour moi » si une carte active correspond à sa discipline
    /// (type de manifestation) et à une de ses courses :
    /// - carte avec une catégorie (1re, 2e, 3e…) → on compare la catégorie ;
    /// - sinon → on compare la tranche d'âge de la carte (« Adulte masculin 30/39 » ↔ « 30/39 ans »).
    func correspond(_ m: Manifestation) -> Bool {
        let type = Self.normalise(m.modele?.libelle ?? "")
        return cartesActives.contains { carte in
            guard type.hasPrefix(Self.normalise(carte.discipline)) else { return false }
            if let niveau = carte.niveau {
                return m.configNiveaux.contains { Self.memeCategorie(niveau, $0.niveau.libelle) }
            }
            if let age = carte.categorieAge.flatMap(Self.trancheAge) {
                return m.configNiveaux.contains { Self.trancheAge($0.niveau.libelle) == age }
            }
            return true
        }
    }

    /// Cette course de la manifestation correspond-elle à une de mes cartes actives ?
    func correspond(course: ConfigNiveau, in m: Manifestation) -> Bool {
        let type = Self.normalise(m.modele?.libelle ?? "")
        return cartesActives.contains { carte in
            guard type.hasPrefix(Self.normalise(carte.discipline)) else { return false }
            if let niveau = carte.niveau { return Self.memeCategorie(niveau, course.niveau.libelle) }
            if let age = carte.categorieAge.flatMap(Self.trancheAge) { return Self.trancheAge(course.niveau.libelle) == age }
            return true
        }
    }

    /// « 30/39 » ou « 50 et + » extrait d'un libellé (« Adulte masculin 30/39 », « 50 ans et + »).
    static func trancheAge(_ texte: String) -> String? {
        if let m = texte.firstMatch(of: #/(\d{1,2})\s*/\s*(\d{1,2})/#) { return "\(m.output.1)/\(m.output.2)" }
        if let m = texte.firstMatch(of: #/(\d{1,2})\s*(?:ans)?\s*et\s*\+/#) { return "\(m.output.1)+" }
        return nil
    }

    /// « 3ème catégorie » ≈ « 3e catégorie » (on compare le numéro), sinon texte normalisé.
    private static func memeCategorie(_ carte: String, _ course: String) -> Bool {
        let a = normalise(carte), b = normalise(course)
        if let na = numero(a), let nb = numero(b) { return na == nb && b.contains("categorie") }
        return a == b
    }

    private static func numero(_ s: String) -> String? {
        s.firstMatch(of: #/\d+/#).map { String($0.output) }
    }

    private static func normalise(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .init(identifier: "fr_FR"))
    }
}
