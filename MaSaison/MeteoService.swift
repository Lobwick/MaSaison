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

/// Météo fournie par WeatherKit (Apple). Nécessite la capacité WeatherKit sur l'identifiant de l'app.
enum MeteoService {
    /// Horizon des prévisions journalières de WeatherKit, en jours.
    static let horizonJours = 10

    /// `nil` si la date est passée ou trop lointaine, ou si la météo est indisponible (jamais d'erreur affichée).
    static func prevision(latitude: Double, longitude: Double, jour: Date) async -> Meteo? {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!
        let aujourdhui = calendrier.startOfDay(for: Date())
        let cible = calendrier.startOfDay(for: jour)
        guard let ecart = calendrier.dateComponents([.day], from: aujourdhui, to: cible).day,
              (0..<horizonJours).contains(ecart),
              let lendemain = calendrier.date(byAdding: .day, value: 1, to: cible) else { return nil }

        let lieu = CLLocation(latitude: latitude, longitude: longitude)
        guard let jours = try? await WeatherService.shared.weather(for: lieu, including: .daily(startDate: cible, endDate: lendemain)),
              let j = jours.forecast.first(where: { calendrier.isDate($0.date, inSameDayAs: cible) }) else { return nil }

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
