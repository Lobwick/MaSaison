import SwiftUI

/// Weather icon with fixed colors: the app forces dark mode with light backgrounds, and the system
/// `.multicolor` rendering would then draw a white sun, invisible on grey cards.
struct WeatherIcon: View {
    let symbol: String
    var size: CGFloat

    var body: some View {
        let (primary, secondary) = Self.colors(symbol)
        Image(systemName: symbol)
            .symbolRenderingMode(.palette)
            .foregroundStyle(primary, secondary)
            .font(.system(size: size))
    }

    /// Grey clouds, yellow-orange sun, indigo moon, blue rain, light blue snow, yellow lightning.
    static func colors(_ s: String) -> (Color, Color) {
        let cloud = Color(hex: 0x8A94A6), sun = Color(hex: 0xF5A623), moon = Color(hex: 0x5B6CB8)
        let rain = Color(hex: 0x2F80ED), snow = Color(hex: 0x7FB3E6), lightning = Color(hex: 0xF2C200)
        switch true {
        case s.contains("bolt"): return (cloud, lightning)
        case s.contains("snow"), s.contains("sleet"): return (cloud, snow)
        case s.contains("rain"), s.contains("drizzle"), s.contains("heavyrain"): return (cloud, rain)
        case s.hasPrefix("cloud.sun"): return (cloud, sun)
        case s.hasPrefix("cloud.moon"): return (cloud, moon)
        case s.hasPrefix("sun"): return (sun, sun)
        case s.hasPrefix("moon"): return (moon, moon)
        case s.contains("wind"), s.contains("tornado"), s.contains("hurricane"): return (cloud, cloud)
        default: return (cloud, sun)   // clouds, fog, haze
        }
    }
}
