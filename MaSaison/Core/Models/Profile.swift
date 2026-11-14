import Foundation

/// Profile sheet read from the HTML of `/infos`.
struct Profile {
    var name = ""
    var licenseNumber = ""
    var photoURL: URL?
    var fields: [(label: String, value: String)] = []
}

/// License card (`/cartes-pass/cartes`): one discipline, one season, optionally a category.
struct LicenseCard: Identifiable, Hashable {
    let id = UUID()
    let season: String        // "2027"
    let discipline: String    // "Cyclocross"
    let issuedOn: String
    let expiresOn: String
    let ageCategory: String? // "Adulte masculin 30/39"
    let level: String?       // "3ème catégorie"
    let club: String
    let committee: String
    let status: String        // "Active", "Expiré"

    var isActive: Bool { status.lowercased() == "active" }
}
