import Foundation

/// Member registration, read from the HTML of `/manifestations/liste-inscriptions`.
struct Registration: Identifiable, Hashable {
    struct Entry: Hashable {
        let type: String      // "Cyclocross Classique Adultes"
        let status: String    // "Active"
        let levels: [String] // "Adultes - 3e catégorie"
    }

    let eventID: Int
    let name: String
    let year: String
    let organizer: String
    let type: String
    let dateText: String
    let startDate: Date?
    let endDate: Date?
    let entries: [Entry]

    var id: Int { eventID }
    var isFinished: Bool { endDate.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false }
}

/// Row of `/manifestations/resultats`: "10" (place), "AB" (did not finish), "NP" (did not start), "Absent(e)"…
struct RaceResult: Hashable {
    let eventID: Int?
    let name: String
    let date: Date?
    let ranking: String

    var place: Int? { Int(ranking) }
    var shortText: String { place.map { $0 == 1 ? "1er" : "\($0)e" } ?? ranking }
}

/// Response of `manifestations/manifestation/{id}/detail-personne/{personne}`: what the site allows for this person.
struct PersonRegistrationDetail: Decodable {
    struct LevelStatus: Decodable {
        struct Level: Decodable {
            let id: Int
            let name: String

            enum CodingKeys: String, CodingKey {
                case id
                case name = "libelle"
            }
        }

        let level: Level
        let errors: [String]
        let disabled: Bool
        let isOnWaitingList: Bool?

        enum CodingKeys: String, CodingKey {
            case disabled
            case level = "niveau"
            case errors = "erreurs"
            case isOnWaitingList = "sur_liste_attente"
        }

        var isOpenForRegistration: Bool { !disabled && errors.isEmpty }
    }

    struct Empty: Decodable {}

    let levels: [LevelStatus]
    let requestedDocuments: [Empty]?

    enum CodingKeys: String, CodingKey {
        case levels = "niveaux"
        case requestedDocuments = "documentsDemandes"
    }
}

/// Ticket computed by the site before saving (the raw response is kept for display).
struct RegistrationTicket {
    struct LineItem {
        let name: String
        let amount: Double
    }

    let id: String          // "216-39438" (event-person)
    let total: Double
    let rows: [LineItem]
    let raw: Data
}

/// Order awaiting payment (`/commandes`).
struct Order: Identifiable, Hashable {
    let id: Int          // checkbox value (14005)
    let number: String   // "0000013387"
    let name: String  // "Inscription sur la manifestation : Cyclo-cross VTT de Feignies"
    let amount: Double
}
