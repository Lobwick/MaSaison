import Foundation
import Observation

/// Mémorise les courses ajoutées à l'agenda (l'accès « écriture seule » ne permet pas de relire le calendrier).
@Observable
final class AgendaStore {
    private static let cle = "evenementsAgenda"
    /// « idManifestation:idCourse » → identifiant de l'événement EventKit
    private(set) var evenements: [String: String]

    init() {
        evenements = UserDefaults.standard.dictionary(forKey: Self.cle) as? [String: String] ?? [:]
    }

    func ajoute(manifestation: Int, course: Int) -> Bool { evenements["\(manifestation):\(course)"] != nil }
    func ajoute(manifestation: Int) -> Bool { evenements.keys.contains { $0.hasPrefix("\(manifestation):") } }

    func identifiant(manifestation: Int, course: Int) -> String? { evenements["\(manifestation):\(course)"] }

    func retirer(manifestation: Int, course: Int) {
        evenements["\(manifestation):\(course)"] = nil
        UserDefaults.standard.set(evenements, forKey: Self.cle)
    }

    func enregistrer(manifestation: Int, course: Int, identifiant: String) {
        evenements["\(manifestation):\(course)"] = identifiant
        UserDefaults.standard.set(evenements, forKey: Self.cle)
    }
}
