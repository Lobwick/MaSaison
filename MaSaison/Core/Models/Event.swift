import Foundation

/// Event contact (« Informations générales » page: event-specific email and phone).
struct EventContact: Decodable {
    let contactEmail: String?
    let contactPhone: String?
    let person: Person?

    struct Person: Decodable {
        let lastName: String?
        let firstName: String?

        enum CodingKeys: String, CodingKey {
            case lastName = "nom"
            case firstName = "prenom"
        }
    }

    enum CodingKeys: String, CodingKey {
        case person = "personne"
        case contactEmail = "mail_specifique"
        case contactPhone = "num_specifique"
    }

    var fullName: String? {
        let n = [person?.firstName, person?.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        return n.isEmpty ? nil : n.capitalized
    }

    var phoneURL: URL? {
        guard let t = contactPhone?.filter({ $0.isNumber || $0 == "+" }), t.count >= 6, Set(t) != ["0"] else { return nil }
        return URL(string: "tel:\(t)")
    }

    var emailURL: URL? {
        guard let e = contactEmail?.trimmingCharacters(in: .whitespaces), e.contains("@") else { return nil }
        return URL(string: "mailto:\(e)")
    }
}

struct Event: Decodable, Identifiable {
    let id: Int
    let name: String
    let startDateText: String
    let endDateText: String
    let startTimeText: String?
    let address: Address?
    let races: [Race]
    let structure: Structure?
    let kind: Kind?
    let documents: [Document]?
    let isOpenForRegistration: Bool?
    let registrationStartDate: String?
    let registrationEndDate: String?
    let registrationStartTime: String?
    let registrationEndTime: String?

    struct Structure: Decodable {
        let name: String
        let code: String?

        enum CodingKeys: String, CodingKey {
            case name = "nom"
            case code
        }
    }

    struct Document: Decodable {
        let fileURL: String?
        let type: DocumentType?

        struct DocumentType: Decodable {
            let code: String?
            let name: String?

            enum CodingKeys: String, CodingKey {
                case code
                case name = "libelle"
            }
        }

        enum CodingKeys: String, CodingKey {
            case type
            case fileURL = "file_url"
        }
    }

    /// PDF documents (rules, program, poster): type label + URL.
    var pdfDocuments: [(name: String, url: URL)] {
        (documents ?? []).compactMap { d in
            guard let f = d.fileURL, let url = URL(string: f), url.pathExtension.lowercased() == "pdf" else { return nil }
            return (d.type?.name ?? d.type?.code?.capitalized ?? "Document", url)
        }
    }

    /// GPX file published by the organizer, if any (today the site only exposes poster, rules, program).
    var gpxURL: URL? {
        documents?.lazy.compactMap { d -> URL? in
            guard let f = d.fileURL, let url = URL(string: f) else { return nil }
            let code = d.type?.code?.uppercased() ?? ""
            return url.pathExtension.lowercased() == "gpx" || code.contains("GPX") || code.contains("TRACE") ? url : nil
        }.first
    }

    var startDate: Date? { Date.fr("dd/MM/yyyy").date(from: startDateText) }

    /// Registration opening (Paris time); start of day if the time is missing.
    var registrationOpensAt: Date? { Self.registrationDate(registrationStartDate, registrationStartTime) }

    /// Registration closing (Paris time); end of day (23:59) if the time is missing.
    var registrationClosesAt: Date? {
        let time = registrationEndTime.flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 } ?? "23:59"
        return Self.registrationDate(registrationEndDate, time)
    }

    /// "18/11/2026" + "23:59" or "23:59:00" → date, in Paris time.
    static func registrationDate(_ date: String?, _ time: String?) -> Date? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        let h = time?.trimmingCharacters(in: .whitespaces).prefix(5)
        return f.date(from: "\(date) \(h.map(String.init) ?? "00:00")")
    }

    /// Event type ("Cyclocross Classique").
    struct Kind: Decodable {
        let name: String

        enum CodingKeys: String, CodingKey {
            case name = "libelle"
        }
    }

    struct Address: Decodable {
        let city: String?
        let postalCode: String?
        let streetNumber: String?
        let streetType: String?
        let streetName: String?
        let latitude: String?
        let longitude: String?

        enum CodingKeys: String, CodingKey {
            case latitude, longitude
            case city = "commune"
            case postalCode = "code_postal_fr"
            case streetNumber = "num_voie"
            case streetType = "type_voie"
            case streetName = "nom_voie"
        }

        var coordinate: (latitude: Double, longitude: Double)? {
            guard let lat = latitude.flatMap(Double.init), let lon = longitude.flatMap(Double.init),
                  lat != 0 || lon != 0 else { return nil }
            return (lat, lon)
        }

        var street: String {
            [streetNumber, streetType, streetName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name = "libelle"
        case address = "adresse"
        case startDateText = "date_debut"
        case endDateText = "date_fin"
        case startTimeText = "date_debut_horaire"
        case races = "config_niveaux"
        case structure, documents
        case kind = "modele"
        case isOpenForRegistration = "inscriptible"
        case registrationStartDate = "dates_inscription_start"
        case registrationEndDate = "dates_inscription_end"
        case registrationStartTime = "horaire_inscription_start"
        case registrationEndTime = "horaire_inscription_end"
    }
}

struct Race: Decodable, Identifiable {
    let id: Int
    let isIncluded: Bool
    let position: Int
    let info: Info
    let level: Level

    enum CodingKeys: String, CodingKey {
        case id, position
        case isIncluded = "avec"
        case info = "infos"
        case level = "niveau"
    }

    struct Level: Decodable {
        let id: Int
        let name: String
        let groupID: Int?
        let position: Int?

        enum CodingKeys: String, CodingKey {
            case id, position
            case name = "libelle"
            case groupID = "groupe_id"
        }
    }

    /// `infos` is `[]` when nothing is filled in, and an object otherwise.
    struct Info: Decodable {
        var callTime: String?
        var startTime: String?
        var lapCount: String?
        var lapDistance: String?
        var duration: String?
        var km: String?

        enum CodingKeys: String, CodingKey {
            case km
            case callTime = "heure"
            case duration = "duree"
            case startTime = "heure_depart"
            case lapCount = "nb_tours"
            case lapDistance = "distance_tour"
        }

        init() {}

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func text(_ key: CodingKeys) -> String? {
                if let s = try? c.decode(String.self, forKey: key) { return s }
                if let d = try? c.decode(Double.self, forKey: key) { return String(d) }
                return nil
            }
            duration = text(.duration)
            km = text(.km)
            callTime = try? c.decode(String.self, forKey: .callTime)
            startTime = try? c.decode(String.self, forKey: .startTime)
            lapCount = try? c.decode(String.self, forKey: .lapCount)
            lapDistance = try? c.decode(String.self, forKey: .lapDistance)
        }

        var isEmpty: Bool { callTime == nil && startTime == nil && lapCount == nil && lapDistance == nil && duration == nil && km == nil }

        /// Race duration in minutes: `duree` (minutes; < 1 read as hours), otherwise estimated
        /// at 30 km/h from the distance, otherwise 60 min.
        var durationMinutes: Int {
            if let d = duration.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }), d > 0 {
                return Int((d < 1 ? d * 60 : d).rounded())
            }
            let distance = (Double(lapCount ?? "") ?? 0) * (Double(lapDistance ?? "") ?? 0)
            let total = distance > 0 ? distance : (Double(km ?? "") ?? 0)
            return total > 0 ? Int((total / 30 * 60).rounded()) : 60
        }
    }
}

struct LevelGroup: Decodable, Identifiable {
    let id: Int
    let name: String

    enum CodingKeys: String, CodingKey {
        case id
        case name = "libelle"
    }
}

/// Event type (model) offered in the federal calendar filter.
struct EventType: Decodable, Identifiable, Hashable {
    let id: Int
    let name: String
    let active: Bool?

    enum CodingKeys: String, CodingKey {
        case id, active
        case name = "libelle"
    }
}

/// Sport = the site's discipline ("Cyclo VTT", "Cyclo - Cyclosport"…).
struct Discipline: Decodable, Identifiable, Hashable {
    let code: String
    let name: String
    let active: Bool?
    var id: String { code }

    enum CodingKeys: String, CodingKey {
        case code, active
        case name = "libelle"
    }
}
