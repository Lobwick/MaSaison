import CoreLocation
import Foundation
import WeatherKit

/// Prévision météo du jour d'une manifestation.
struct Meteo {
    let libelle: String
    let symbole: String
    let tempMin: Double
    let tempMax: Double
    /// Probabilité de précipitations, en %.
    let probaPluie: Int
    let pluieMm: Double
    let ventKmh: Double
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
    static func prevision(latitude: Double, longitude: Double, jour: Date) async throws -> Meteo? {
        let calendrier = Self.calendrier
        let cible = calendrier.startOfDay(for: jour)
        guard dansHorizon(jour), let lendemain = calendrier.date(byAdding: .day, value: 1, to: cible) else { return nil }

        let lieu = CLLocation(latitude: latitude, longitude: longitude)
        let jours = try await WeatherService.shared.weather(for: lieu, including: .daily(startDate: cible, endDate: lendemain))
        guard let j = jours.forecast.first(where: { calendrier.isDate($0.date, inSameDayAs: cible) }) ?? jours.forecast.first else {
            throw MeteoErreur.jourAbsent
        }

        return Meteo(
            libelle: j.condition.description,
            symbole: j.symbolName,
            tempMin: j.lowTemperature.converted(to: .celsius).value,
            tempMax: j.highTemperature.converted(to: .celsius).value,
            probaPluie: Int((j.precipitationChance * 100).rounded()),
            pluieMm: j.precipitationAmount.converted(to: .millimeters).value,
            ventKmh: j.wind.speed.converted(to: .kilometersPerHour).value)
    }

    static func attribution() async -> MeteoAttribution? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return MeteoAttribution(logoClair: a.combinedMarkLightURL, logoSombre: a.combinedMarkDarkURL, mentionsLegales: a.legalPageURL)
    }
}
