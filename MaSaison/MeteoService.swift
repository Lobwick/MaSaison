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
struct MeteoHeure {
    let date: Date
    let libelle: String
    let symbole: String
    let temperature: Double
    let probaPluie: Int
    let pluieMm: Double
    let ventKmh: Double
    let rafalesKmh: Double?
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
        let (jours, heures) = try await WeatherService.shared.weather(for: lieu,
                                                                      including: .daily(startDate: cible, endDate: lendemain),
                                                                      .hourly(startDate: cible, endDate: lendemain))
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
    }

    static func attribution() async -> MeteoAttribution? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return MeteoAttribution(logoClair: a.combinedMarkLightURL, logoSombre: a.combinedMarkDarkURL, mentionsLegales: a.legalPageURL)
    }
}
