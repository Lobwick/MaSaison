import Foundation

/// Weather forecast for the day of an event.
struct WeatherSummary: Codable {
    let condition: String
    let symbol: String
    let minTemp: Double
    let maxTemp: Double
    /// Probability of precipitation, in %.
    let rainChance: Int
    let rainMm: Double
    let windKmh: Double
    /// Maximum wind gusts, in km/h (if known).
    var gustsKmh: Double?
    /// Hour-by-hour forecasts of the day, to narrow the weather to the race time range.
    var hours: [HourlyWeather] = []
    /// Time range covered by the forecast; `nil` for the whole day.
    var timeRange: DateInterval?

    /// Weather narrowed to the hours overlapping `interval`; `self` if no hour matches.
    func during(_ interval: DateInterval) -> WeatherSummary {
        let h = hours.filter { $0.date < interval.end && $0.date.addingTimeInterval(3600) > interval.start }
        guard let first = h.first else { return self }
        let temperatures = h.map(\.temperature)
        return WeatherSummary(
            condition: first.condition,
            symbol: first.symbol,
            minTemp: temperatures.min() ?? minTemp,
            maxTemp: temperatures.max() ?? maxTemp,
            rainChance: h.map(\.rainChance).max() ?? rainChance,
            rainMm: h.map(\.rainMm).reduce(0, +),
            windKmh: h.map(\.windKmh).max() ?? windKmh,
            gustsKmh: h.compactMap(\.gustsKmh).max(),
            hours: h,
            timeRange: interval)
    }
}

/// Forecast for one hour (start of the hour in `date`).
struct HourlyWeather: Codable {
    let date: Date
    let condition: String
    let symbol: String
    let temperature: Double
    let rainChance: Int
    let rainMm: Double
    let windKmh: Double
    let gustsKmh: Double?
}
