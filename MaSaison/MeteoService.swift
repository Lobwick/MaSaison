import CoreLocation
import Foundation
import SwiftUI
import WeatherKit

/// Prévision météo du jour d'une manifestation.
struct Meteo: Codable {
    let libelle: String
    let symbole: String
    let tempMin: Double
    let tempMax: Double
    /// Probabilité de précipitations, en %.
    let probaPluie: Int
    let pluieMm: Double
    let ventKmh: Double
    /// Rafales maximales, en km/h (si connues).
    var rafalesKmh: Double?
    /// Prévisions heure par heure du jour, pour restreindre la météo au créneau de la course.
    var heures: [MeteoHeure] = []
    /// Créneau couvert par la prévision ; `nil` pour la journée entière.
    var plage: DateInterval?

    /// Météo restreinte aux heures qui chevauchent `intervalle` ; `self` si aucune heure ne correspond.
    func pendant(_ intervalle: DateInterval) -> Meteo {
        let h = heures.filter { $0.date < intervalle.end && $0.date.addingTimeInterval(3600) > intervalle.start }
        guard let premiere = h.first else { return self }
        let temps = h.map(\.temperature)
        return Meteo(
            libelle: premiere.libelle,
            symbole: premiere.symbole,
            tempMin: temps.min() ?? tempMin,
            tempMax: temps.max() ?? tempMax,
            probaPluie: h.map(\.probaPluie).max() ?? probaPluie,
            pluieMm: h.map(\.pluieMm).reduce(0, +),
            ventKmh: h.map(\.ventKmh).max() ?? ventKmh,
            rafalesKmh: h.compactMap(\.rafalesKmh).max(),
            heures: h,
            plage: intervalle)
    }
}

/// Prévision d'une heure (début de l'heure dans `date`).
struct MeteoHeure: Codable {
    let date: Date
    let libelle: String
    let symbole: String
    let temperature: Double
    let probaPluie: Int
    let pluieMm: Double
    let ventKmh: Double
    let rafalesKmh: Double?
}

/// Icône météo aux couleurs fixées : l'app force le mode sombre avec des fonds clairs, et le rendu
/// `.multicolor` du système dessinerait alors un soleil blanc, invisible sur les cartes grises.
struct IconeMeteo: View {
    let symbole: String
    var taille: CGFloat

    var body: some View {
        let (principale, secondaire) = Self.couleurs(symbole)
        Image(systemName: symbole)
            .symbolRenderingMode(.palette)
            .foregroundStyle(principale, secondaire)
            .font(.system(size: taille))
    }

    /// Nuages gris, soleil jaune-orangé, lune indigo, pluie bleue, neige bleu clair, orage jaune.
    static func couleurs(_ s: String) -> (Color, Color) {
        let nuage = Color(hex: 0x8A94A6), soleil = Color(hex: 0xF5A623), lune = Color(hex: 0x5B6CB8)
        let pluie = Color(hex: 0x2F80ED), neige = Color(hex: 0x7FB3E6), eclair = Color(hex: 0xF2C200)
        switch true {
        case s.contains("bolt"): return (nuage, eclair)
        case s.contains("snow"), s.contains("sleet"): return (nuage, neige)
        case s.contains("rain"), s.contains("drizzle"), s.contains("heavyrain"): return (nuage, pluie)
        case s.hasPrefix("cloud.sun"): return (nuage, soleil)
        case s.hasPrefix("cloud.moon"): return (nuage, lune)
        case s.hasPrefix("sun"): return (soleil, soleil)
        case s.hasPrefix("moon"): return (lune, lune)
        case s.contains("wind"), s.contains("tornado"), s.contains("hurricane"): return (nuage, nuage)
        default: return (nuage, soleil)   // nuages, brouillard, brume
        }
    }
}

/// Mentions d'attribution exigées par Apple pour afficher des données WeatherKit.
struct MeteoAttribution {
    let logoClair: URL
    let logoSombre: URL
    let mentionsLegales: URL
}

enum MeteoErreur: LocalizedError {
    case jourAbsent
    var errorDescription: String? { "WeatherKit n'a renvoyé aucune prévision pour ce jour." }
}

/// Météo fournie par WeatherKit (Apple). Nécessite la capacité WeatherKit sur l'identifiant de l'app.
enum MeteoService {
    /// Horizon des prévisions journalières de WeatherKit, en jours.
    static let horizonJours = 10

    private static var calendrier: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    /// Vrai si la prévision du jour est disponible (aujourd'hui et les jours suivants, dans l'horizon).
    static func dansHorizon(_ jour: Date) -> Bool {
        let c = calendrier
        guard let ecart = c.dateComponents([.day], from: c.startOfDay(for: Date()), to: c.startOfDay(for: jour)).day else { return false }
        return (0..<horizonJours).contains(ecart)
    }

    /// `nil` si la date est passée ou hors de l'horizon ; lève l'erreur WeatherKit si la requête échoue.
    /// Servie depuis le cache tant que WeatherKit la considère valable (`metadata.expirationDate`).
    static func prevision(latitude: Double, longitude: Double, jour: Date) async throws -> Meteo? {
        let calendrier = Self.calendrier
        let cible = calendrier.startOfDay(for: jour)
        guard dansHorizon(jour), let lendemain = calendrier.date(byAdding: .day, value: 1, to: cible) else { return nil }

        let cle = MeteoCache.cle(latitude: latitude, longitude: longitude, jour: cible)
        if let enCache = MeteoCache.lire(cle) { return enCache }
        // accueil et détail peuvent demander la même prévision en même temps : un seul appel
        if let enCours = requetesEnCours[cle] { return try await enCours.value.0 }

        let requete = Task { try await telecharger(latitude: latitude, longitude: longitude, cible: cible, lendemain: lendemain) }
        requetesEnCours[cle] = requete
        defer { requetesEnCours[cle] = nil }
        let (meteo, expiration) = try await requete.value
        MeteoCache.ecrire(meteo, cle: cle, expiration: expiration)
        return meteo
    }

    private static var requetesEnCours: [String: Task<(Meteo, Date), Error>] = [:]

    /// Appel WeatherKit ; l'expiration retenue est la plus proche des deux prévisions.
    private static func telecharger(latitude: Double, longitude: Double, cible: Date, lendemain: Date) async throws -> (Meteo, Date) {
        let calendrier = Self.calendrier
        let lieu = CLLocation(latitude: latitude, longitude: longitude)
        let (jours, heures) = try await WeatherService.shared.weather(for: lieu,
                                                                      including: .daily(startDate: cible, endDate: lendemain),
                                                                      .hourly(startDate: cible, endDate: lendemain))
        guard let j = jours.forecast.first(where: { calendrier.isDate($0.date, inSameDayAs: cible) }) ?? jours.forecast.first else {
            throw MeteoErreur.jourAbsent
        }
        let expiration = min(jours.metadata.expirationDate, heures.metadata.expirationDate)

        let meteo = Meteo(
            libelle: j.condition.description,
            symbole: j.symbolName,
            tempMin: j.lowTemperature.converted(to: .celsius).value,
            tempMax: j.highTemperature.converted(to: .celsius).value,
            probaPluie: Int((j.precipitationChance * 100).rounded()),
            pluieMm: j.precipitationAmount.converted(to: .millimeters).value,
            ventKmh: j.wind.speed.converted(to: .kilometersPerHour).value,
            rafalesKmh: j.wind.gust?.converted(to: .kilometersPerHour).value,
            heures: heures.forecast.map { h in
                MeteoHeure(
                    date: h.date,
                    libelle: h.condition.description,
                    symbole: h.symbolName,
                    temperature: h.temperature.converted(to: .celsius).value,
                    probaPluie: Int((h.precipitationChance * 100).rounded()),
                    pluieMm: h.precipitationAmount.converted(to: .millimeters).value,
                    ventKmh: h.wind.speed.converted(to: .kilometersPerHour).value,
                    rafalesKmh: h.wind.gust?.converted(to: .kilometersPerHour).value)
            })
        return (meteo, expiration)
    }

    static func attribution() async -> MeteoAttribution? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return MeteoAttribution(logoClair: a.combinedMarkLightURL, logoSombre: a.combinedMarkDarkURL, mentionsLegales: a.legalPageURL)
    }
}

/// Cache des prévisions par lieu (~1 km) et jour, valable jusqu'à l'expiration fournie par WeatherKit.
/// En mémoire et dans `Caches/meteo.json` (le système peut le purger) ; les entrées expirées sont retirées
/// au chargement et à chaque écriture, et tout est vidé à la déconnexion.
enum MeteoCache {
    private struct Entree: Codable {
        let meteo: Meteo
        let expiration: Date
    }

    private static let fichier = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("meteo.json")

    private static var entrees: [String: Entree] = {
        guard let data = try? Data(contentsOf: fichier),
              let lues = try? JSONDecoder().decode([String: Entree].self, from: data) else { return [:] }
        return lues.filter { $0.value.expiration > Date() }
    }()

    /// « 50.42,3.51-2026-11-21 » : coordonnées arrondies au centième (~1 km) et jour.
    static func cle(latitude: Double, longitude: Double, jour: Date) -> String {
        let j = jour.formatted(.iso8601.year().month().day())
        return String(format: "%.2f,%.2f-", latitude, longitude) + j
    }

    static func lire(_ cle: String) -> Meteo? {
        guard let e = entrees[cle] else { return nil }
        guard e.expiration > Date() else {
            entrees[cle] = nil
            enregistrer()
            return nil
        }
        return e.meteo
    }

    static func ecrire(_ meteo: Meteo, cle: String, expiration: Date) {
        guard expiration > Date() else { return }
        entrees[cle] = Entree(meteo: meteo, expiration: expiration)
        enregistrer()
    }

    /// Vide tout le cache (déconnexion).
    static func vider() {
        entrees = [:]
        try? FileManager.default.removeItem(at: fichier)
    }

    private static func enregistrer() {
        entrees = entrees.filter { $0.value.expiration > Date() }
        if let data = try? JSONEncoder().encode(entrees) { try? data.write(to: fichier, options: .atomic) }
    }
}
