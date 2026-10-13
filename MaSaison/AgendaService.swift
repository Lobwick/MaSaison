import EventKit
import Foundation

enum AgendaError: LocalizedError {
    case accesRefuse
    case horairesManquants

    var errorDescription: String? {
        switch self {
        case .accesRefuse: "Accès à l'agenda refusé (Réglages > Confidentialité > Calendriers)."
        case .horairesManquants: "Cette course n'a pas d'horaires."
        }
    }
}

/// Ajoute une course au calendrier : de (appel − échauffement) jusqu'à (départ + durée).
enum AgendaService {
    struct Creneau {
        let echauffement: Date
        let appel: Date
        let depart: Date
        let fin: Date
        var debut: Date { echauffement }
    }

    static func creneau(manifestation: Manifestation, course: ConfigNiveau, echauffementMinutes: Int) -> Creneau? {
        let infos = course.infos
        guard let depart = date(manifestation.dateDebut, infos.heureDepart ?? infos.heure ?? manifestation.dateDebutHoraire),
              let appel = date(manifestation.dateDebut, infos.heure ?? infos.heureDepart ?? manifestation.dateDebutHoraire)
        else { return nil }
        let premier = min(appel, depart)
        return Creneau(
            echauffement: premier.addingTimeInterval(-Double(echauffementMinutes) * 60),
            appel: appel,
            depart: depart,
            fin: depart.addingTimeInterval(Double(infos.dureeMinutes) * 60)
        )
    }

    /// Crée l'événement et renvoie son identifiant.
    static func ajouter(manifestation: Manifestation, course: ConfigNiveau, echauffementMinutes: Int) async throws -> String {
        guard let creneau = creneau(manifestation: manifestation, course: course, echauffementMinutes: echauffementMinutes) else {
            throw AgendaError.horairesManquants
        }
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw AgendaError.accesRefuse }

        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        event.title = "\(manifestation.libelle.capitalized) – \(course.niveau.libelle)"
        event.startDate = creneau.debut
        event.endDate = creneau.fin

        if let adresse = manifestation.adresse {
            let titre = [adresse.rue, adresse.codePostalFr, adresse.commune].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ").capitalized
            let lieu = EKStructuredLocation(title: titre)
            if let c = adresse.coordinate { lieu.geoLocation = CLLocation(latitude: c.latitude, longitude: c.longitude) }
            event.structuredLocation = lieu
        }

        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        var notes: [String] = []
        if echauffementMinutes > 0 { notes.append("Échauffement : \(creneau.echauffement.formatted(heure)) (\(echauffementMinutes) min avant l'appel)") }
        notes.append("Appel : \(creneau.appel.formatted(heure))")
        notes.append("Départ : \(creneau.depart.formatted(heure))")
        if let o = manifestation.structure?.nom { notes.append("Organisateur : \(o)") }
        // EventKit n'a pas d'API publique pour joindre un fichier : le GPX est référencé par son lien.
        if let gpx = manifestation.gpxURL {
            event.url = gpx
            notes.append("Tracé GPX : \(gpx.absoluteString)")
        }
        event.notes = notes.joined(separator: "\n")

        try store.save(event, span: .thisEvent)
        return event.eventIdentifier ?? ""
    }

    private static func date(_ jour: String, _ heure: String?) -> Date? {
        guard let heure else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.date(from: "\(jour) \(heure)")
    }
}
