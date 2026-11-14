import SwiftUI

/// Light visual direction inspired by Apple apps: white background, material cards, system accent.
enum Theme {
    static let bg = Color(hex: 0xFCF8FB)
    static let surface = Color.white
    static let surface2 = Color(hex: 0xF6F3F5)
    static let line = Color.black.opacity(0.06)
    static let text = Color(hex: 0x111318)
    static let textSoft = Color(hex: 0x2B2F36)
    static let muted = Color(hex: 0x6B7380)
    static let faint = Color(hex: 0x98A0AD)
    static let accent = Color(hex: 0x006948)
    static let secondary = Color(hex: 0x0058BC)
    static let danger = Color.red
    static let warning = Color.orange
    /// Wishlist (bookmark, pill, date block).
    static let wishlist = Color(hex: 0xE5B000)

    /// No more custom font: we keep the native SF Pro typeface.
    static func registerFonts() {
        // no-op
    }
}

extension Font {
    enum Emphasis { case medium, semibold, bold }

    /// SF Pro (standard iOS text).
    static func sfPro(_ size: CGFloat, _ emphasis: Emphasis = .medium) -> Font {
        let weight: Font.Weight = switch emphasis {
        case .medium: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// SF Compact-like (visual equivalent using the rounded design).
    static func sfCompact(_ size: CGFloat, _ emphasis: Emphasis = .bold) -> Font {
        let weight: Font.Weight = switch emphasis {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    /// SF Mono for values/times.
    static func sfMono(_ size: CGFloat, _ emphasis: Emphasis = .medium) -> Font {
        let weight: Font.Weight = switch emphasis {
        case .medium: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // Existing compatibility
    static func cond(_ size: CGFloat, _ emphasis: Emphasis = .bold) -> Font {
        sfCompact(size, emphasis)
    }

    static func barlow(_ size: CGFloat, _ emphasis: Emphasis = .medium) -> Font {
        sfPro(size, emphasis)
    }
}

extension View {
    /// "Liquid glass" card.
    func card(border: Color = Theme.line, radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1))
    }

    func screenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// Apple-style page title.
    func pageTitle() -> some View {
        font(.cond(34)).textCase(.uppercase).foregroundStyle(Theme.text)
    }
}
