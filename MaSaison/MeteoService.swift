import Foundation

/// Prévision météo du jour d'une manifestation, via Open-Meteo (gratuit, sans clé ni compte).
/// Seules les coordonnées du lieu et la date sont envoyées. Disponible jusqu'à 16 jours avant l'épreuve.
struct Meteo: Equatable {
    let tempMin: Double
    let tempMax: Double
    let probaPluie: Int?
    let pluieMm: Double
    let ventKmh: Double
    let rafalesKmh: Double?
    let code: Int

    var libelle: String {
        switch code {
        case 0: "Ciel dégagé"
        case 1: "Plutôt dégagé"
        case 2: "Partiellement nuageux"
        case 3: "Couvert"
        case 45, 48: "Brouillard"
        case 51, 53, 55, 56, 57: "Bruine"
        case 61, 63, 65, 66, 67: "Pluie"
        case 71, 73, 75, 77: "Neige"
        case 80, 81, 82: "Averses"
        case 85, 86: "Averses de neige"
        case 95, 96, 99: "Orages"
        default: "Variable"
        }
    }

    var symbole: String {
        switch code {
        case 0, 1: "sun.max.fill"
        case 2: "cloud.sun.fill"
        case 3: "cloud.fill"
        case 45, 48: "cloud.fog.fill"
        case 51, 53, 55, 56, 57: "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: "cloud.snow.fill"
        case 80, 81, 82: "cloud.heavyrain.fill"
        case 95, 96, 99: "cloud.bolt.rain.fill"
        default: "cloud.fill"
        }
    }
}

enum MeteoService {
    /// Horizon de prévision d'Open-Meteo, en jours.
    static let horizonJours = 16

    /// `nil` si la date est passée ou trop lointaine, ou si la météo est indisponible (jamais d'erreur affichée).
    static func prevision(latitude: Double, longitude: Double, jour: Date, session: URLSession = .shared) async -> Meteo? {
        var calendrier = Calendar(identifier: .gregorian)
        calendrier.timeZone = TimeZone(identifier: "Europe/Paris")!
        let aujourdhui = calendrier.startOfDay(for: Date())
        let cible = calendrier.startOfDay(for: jour)
        guard let ecart = calendrier.dateComponents([.day], from: aujourdhui, to: cible).day,
              (0..<horizonJours).contains(ecart) else { return nil }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendrier.timeZone
        f.dateFormat = "yyyy-MM-dd"
        let date = f.string(from: cible)

        var composants = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        composants.queryItems = [
            .init(name: "latitude", value: String(latitude)),
            .init(name: "longitude", value: String(longitude)),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,wind_gusts_10m_max"),
            .init(name: "timezone", value: "Europe/Paris"),
            .init(name: "start_date", value: date),
            .init(name: "end_date", value: date),
        ]
        guard let url = composants.url,
              let (data, reponse) = try? await session.data(from: url),
              (reponse as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return decoder(data)
    }

    static func decoder(_ data: Data) -> Meteo? {
        guard let r = try? JSONDecoder().decode(Reponse.self, from: data),
              let code = r.daily.weatherCode.first ?? nil,
              let tMax = r.daily.tempMax.first ?? nil,
              let tMin = r.daily.tempMin.first ?? nil else { return nil }
        return Meteo(
            tempMin: tMin, tempMax: tMax,
            probaPluie: (r.daily.probaPluie?.first ?? nil),
            pluieMm: (r.daily.pluie?.first ?? nil) ?? 0,
            ventKmh: (r.daily.vent?.first ?? nil) ?? 0,
            rafalesKmh: r.daily.rafales?.first ?? nil,
            code: code)
    }

    private struct Reponse: Decodable {
        let daily: Daily
        struct Daily: Decodable {
            let weatherCode: [Int?]
            let tempMax: [Double?]
            let tempMin: [Double?]
            let probaPluie: [Int?]?
            let pluie: [Double?]?
            let vent: [Double?]?
            let rafales: [Double?]?

            enum CodingKeys: String, CodingKey {
                case weatherCode = "weather_code"
                case tempMax = "temperature_2m_max"
                case tempMin = "temperature_2m_min"
                case probaPluie = "precipitation_probability_max"
                case pluie = "precipitation_sum"
                case vent = "wind_speed_10m_max"
                case rafales = "wind_gusts_10m_max"
            }
        }
    }
}
