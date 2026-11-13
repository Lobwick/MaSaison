import EventKit
import Foundation

enum AgendaError: LocalizedError {
    case accesRefuse
    case horairesManquants
    case evenementIntrouvable

    var errorDescription: String? {
        switch self {
        case .accesRefuse: "Accès à l'agenda refusé (Réglages > Confidentialité > Calendriers)."
        case .horairesManquants: "Cette course n'a pas d'horaires."
        case .evenementIntrouvable: "L'événement n'est plus dans ton agenda (supprimé ?). Tu peux le rajouter."
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

    /// Plage couverte par des courses, de la première convocation à la dernière arrivée ; `nil` si aucun horaire.
    static func plage(manifestation: Manifestation, courses: [ConfigNiveau]) -> DateInterval? {
        let creneaux = courses.compactMap { creneau(manifestation: manifestation, course: $0, echauffementMinutes: 0) }
        guard let debut = creneaux.map({ min($0.appel, $0.depart) }).min(),
              let fin = creneaux.map(\.fin).max(), fin > debut else { return nil }
        return DateInterval(start: debut, end: fin)
    }

    /// Crée l'événement et renvoie son identifiant.
    static func ajouter(manifestation: Manifestation, course: ConfigNiveau, echauffementMinutes: Int, trajet: Trajet? = nil) async throws -> String {
        guard let creneau = creneau(manifestation: manifestation, course: course, echauffementMinutes: echauffementMinutes) else {
            throw AgendaError.horairesManquants
        }
        let store = EKEventStore()
        guard try await store.requestWriteOnlyAccessToEvents() else { throw AgendaError.accesRefuse }

        let event = EKEvent(eventStore: store)
        event.calendar = store.defaultCalendarForNewEvents
        event.title = titre(manifestation: manifestation, course: course)
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
        if let trajet { notes.append(ligneTrajet(trajet, creneau: creneau)) }
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

    private static func titre(manifestation: Manifestation, course: ConfigNiveau) -> String {
        "\(manifestation.libelle.capitalized) – \(course.niveau.libelle)"
    }

    /// Retrouve les événements par leur titre et leur horaire (l'identifiant n'est pas toujours rendu en écriture seule).
    /// Plusieurs copies peuvent exister (ajouts répétés) : on les renvoie toutes.
    private static func trouver(dans store: EKEventStore, manifestation: Manifestation, course: ConfigNiveau, creneau: Creneau) -> [EKEvent] {
        let titre = titre(manifestation: manifestation, course: course)
        let predicat = store.predicateForEvents(withStart: creneau.debut.addingTimeInterval(-86_400),
                                                end: creneau.fin.addingTimeInterval(86_400), calendars: nil)
        let candidats = store.events(matching: predicat).filter { $0.title == titre }
        let memeHeure = candidats.filter { abs($0.startDate.timeIntervalSince(creneau.debut)) < 60 }
        return memeHeure.isEmpty ? candidats : memeHeure
    }

    /// « Trajet : 35 min en voiture · 28 km, partir vers 11:10 (calculé le 13 nov. à 10:32) ».
    private static func ligneTrajet(_ trajet: Trajet, creneau: Creneau) -> String {
        let fr = Locale(identifier: "fr_FR")
        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(fr)
        let calcule = Date.FormatStyle(date: .abbreviated, time: .shortened).locale(fr)
        let partir = creneau.debut.addingTimeInterval(-trajet.duree)
        return "Trajet : \(trajet.texte), partir vers \(partir.formatted(heure)) (calculé le \(Date().formatted(calcule)))"
    }

    struct MiseAJour {
        let identifiant: String
        let nombre: Int
        let calendriers: [String]
    }

    /// Remplace la ligne « Trajet : » des événements déjà créés, sans toucher au reste des notes.
    /// Retrouver l'événement demande l'accès complet au calendrier : il n'est demandé qu'à ce moment-là.
    static func mettreAJourTrajet(identifiant: String, manifestation: Manifestation, course: ConfigNiveau,
                                  echauffementMinutes: Int, trajet: Trajet) async throws -> MiseAJour {
        guard let creneau = creneau(manifestation: manifestation, course: course, echauffementMinutes: echauffementMinutes) else {
            throw AgendaError.horairesManquants
        }
        let store = EKEventStore()
        guard try await store.requestFullAccessToEvents() else { throw AgendaError.accesRefuse }

        var evenements = trouver(dans: store, manifestation: manifestation, course: course, creneau: creneau)
        if !identifiant.isEmpty, let direct = store.event(withIdentifier: identifiant),
           !evenements.contains(where: { $0.eventIdentifier == direct.eventIdentifier }) {
            evenements.append(direct)
        }
        guard !evenements.isEmpty else { throw AgendaError.evenementIntrouvable }

        let ligne = ligneTrajet(trajet, creneau: creneau)
        for event in evenements {
            var lignes = (event.notes ?? "").components(separatedBy: "\n").filter { !$0.hasPrefix("Trajet :") }
            while lignes.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lignes.removeLast() }
            lignes.append(ligne)
            event.notes = lignes.joined(separator: "\n")
            try store.save(event, span: .thisEvent, commit: false)
        }
        try store.commit()
        return MiseAJour(identifiant: evenements[0].eventIdentifier ?? identifiant,
                         nombre: evenements.count,
                         calendriers: Array(Set(evenements.map { $0.calendar.title })).sorted())
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
