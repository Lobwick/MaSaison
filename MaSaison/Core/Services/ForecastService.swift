import CoreLocation
import Foundation
import SwiftUI
import WeatherKit

/// Attribution required by Apple to display WeatherKit data.
struct WeatherCredits {
    let lightLogo: URL
    let darkLogo: URL
    let legalPage: URL
}

enum ForecastError: LocalizedError {
    case dayMissing
    var errorDescription: String? { "WeatherKit n'a renvoyé aucune prévision pour ce jour." }
}

/// Weather provided by WeatherKit (Apple). Requires the WeatherKit capability on the app identifier.
enum ForecastService {
    /// Horizon of WeatherKit daily forecasts, in days.
    static let horizonDays = 10

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }

    /// True if the day's forecast is available (today and following days, within the horizon).
    static func isWithinHorizon(_ day: Date) -> Bool {
        let c = calendar
        guard let dayOffset = c.dateComponents([.day], from: c.startOfDay(for: Date()), to: c.startOfDay(for: day)).day else { return false }
        return (0..<horizonDays).contains(dayOffset)
    }

    /// `nil` if the date is past or beyond the horizon; throws the WeatherKit error if the request fails.
    /// Served from the cache as long as WeatherKit considers it valid (`metadata.expirationDate`).
    static func forecast(latitude: Double, longitude: Double, day: Date) async throws -> WeatherSummary? {
        let calendar = Self.calendar
        let target = calendar.startOfDay(for: day)
        guard isWithinHorizon(day), let nextDay = calendar.date(byAdding: .day, value: 1, to: target) else { return nil }

        let key = WeatherCache.key(latitude: latitude, longitude: longitude, day: target)
        if let cached = WeatherCache.read(key) { return cached }
        // home and detail may request the same forecast at the same time: a single call
        if let inFlight = inFlightRequests[key] { return try await inFlight.value.0 }

        let request = Task { try await fetchForecast(latitude: latitude, longitude: longitude, target: target, nextDay: nextDay) }
        inFlightRequests[key] = request
        defer { inFlightRequests[key] = nil }
        let (weather, expiration) = try await request.value
        WeatherCache.write(weather, key: key, expiration: expiration)
        return weather
    }

    private static var inFlightRequests: [String: Task<(WeatherSummary, Date), Error>] = [:]

    /// WeatherKit call; the retained expiration is the earliest of the two forecasts.
    private static func fetchForecast(latitude: Double, longitude: Double, target: Date, nextDay: Date) async throws -> (WeatherSummary, Date) {
        let calendar = Self.calendar
        let location = CLLocation(latitude: latitude, longitude: longitude)
        let (days, hours) = try await WeatherService.shared.weather(for: location,
                                                                      including: .daily(startDate: target, endDate: nextDay),
                                                                      .hourly(startDate: target, endDate: nextDay))
        guard let j = days.forecast.first(where: { calendar.isDate($0.date, inSameDayAs: target) }) ?? days.forecast.first else {
            throw ForecastError.dayMissing
        }
        let expiration = min(days.metadata.expirationDate, hours.metadata.expirationDate)

        let weather = WeatherSummary(
            condition: j.condition.description,
            symbol: j.symbolName,
            minTemp: j.lowTemperature.converted(to: .celsius).value,
            maxTemp: j.highTemperature.converted(to: .celsius).value,
            rainChance: Int((j.precipitationChance * 100).rounded()),
            rainMm: j.precipitationAmount.converted(to: .millimeters).value,
            windKmh: j.wind.speed.converted(to: .kilometersPerHour).value,
            gustsKmh: j.wind.gust?.converted(to: .kilometersPerHour).value,
            hours: hours.forecast.map { h in
                HourlyWeather(
                    date: h.date,
                    condition: h.condition.description,
                    symbol: h.symbolName,
                    temperature: h.temperature.converted(to: .celsius).value,
                    rainChance: Int((h.precipitationChance * 100).rounded()),
                    rainMm: h.precipitationAmount.converted(to: .millimeters).value,
                    windKmh: h.wind.speed.converted(to: .kilometersPerHour).value,
                    gustsKmh: h.wind.gust?.converted(to: .kilometersPerHour).value)
            })
        return (weather, expiration)
    }

    static func attribution() async -> WeatherCredits? {
        guard let a = try? await WeatherService.shared.attribution else { return nil }
        return WeatherCredits(lightLogo: a.combinedMarkLightURL, darkLogo: a.combinedMarkDarkURL, legalPage: a.legalPageURL)
    }
}
