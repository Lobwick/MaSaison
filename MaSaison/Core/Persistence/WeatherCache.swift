import Foundation

/// Forecast cache by location (~1 km) and day, valid until the expiration provided by WeatherKit.
/// In memory and in `Caches/meteo.json` (the system may purge it); expired entries are removed
/// on load and on every write, and everything is cleared on sign-out.
enum WeatherCache {
    private struct Entry: Codable {
        let weather: WeatherSummary
        let expiration: Date
    }

    private static let file = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("meteo.json")

    private static var entries: [String: Entry] = {
        guard let data = try? Data(contentsOf: file),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return [:] }
        return decoded.filter { $0.value.expiration > Date() }
    }()

    /// "50.42,3.51-2026-11-21": coordinates rounded to two decimals (~1 km) and day.
    static func key(latitude: Double, longitude: Double, day: Date) -> String {
        let j = day.formatted(.iso8601.year().month().day())
        return String(format: "%.2f,%.2f-", latitude, longitude) + j
    }

    static func read(_ key: String) -> WeatherSummary? {
        guard let e = entries[key] else { return nil }
        guard e.expiration > Date() else {
            entries[key] = nil
            save()
            return nil
        }
        return e.weather
    }

    static func write(_ weather: WeatherSummary, key: String, expiration: Date) {
        guard expiration > Date() else { return }
        entries[key] = Entry(weather: weather, expiration: expiration)
        save()
    }

    /// Clears the whole cache (sign-out).
    static func clear() {
        entries = [:]
        try? FileManager.default.removeItem(at: file)
    }

    private static func save() {
        entries = entries.filter { $0.value.expiration > Date() }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: file, options: .atomic) }
    }
}
