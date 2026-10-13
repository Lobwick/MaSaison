import CoreText
import SwiftUI

/// Direction visuelle sombre (voir la maquette Claude Design) : fond #0B0D10, cartes anthracite, un accent menthe.
enum Theme {
    static let bg = Color(hex: 0x0B0D10)
    static let surface = Color(hex: 0x14181D)
    static let surface2 = Color(hex: 0x1C2229)
    static let line = Color(hex: 0x232A32)
    static let text = Color(hex: 0xF2F5F7)
    static let textSoft = Color(hex: 0xC9D1D8)
    static let muted = Color(hex: 0x8C97A3)
    static let faint = Color(hex: 0x5A6672)
    static let accent = Color(hex: 0x2DE2A6)
    static let danger = Color(hex: 0xFF4D5E)
    static let warning = Color(hex: 0xFFB020)

    /// Enregistre Barlow / Barlow Condensed (fichiers .ttf du bundle) sans passer par Info.plist.
    static func registerFonts() {
        for url in Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [] {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    enum Poids { case medium, semibold, bold }

    /// Barlow Condensed : titres, chiffres, libellés en majuscules.
    static func cond(_ size: CGFloat, _ poids: Poids = .bold) -> Font {
        let nom = switch poids {
        case .medium: "BarlowCondensed-Medium"
        case .semibold: "BarlowCondensed-SemiBold"
        case .bold: "BarlowCondensed-Bold"
        }
        return .custom(nom, size: size, relativeTo: .title)
    }

    /// Barlow : texte courant.
    static func barlow(_ size: CGFloat, _ poids: Poids = .medium) -> Font {
        let nom = switch poids {
        case .medium: "Barlow-Regular"
        case .semibold: "Barlow-Medium"
        case .bold: "Barlow-SemiBold"
        }
        return .custom(nom, size: size, relativeTo: .body)
    }
}

// MARK: - Briques

/// Petit libellé en majuscules espacées (« PROCHAINE COURSE »).
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.muted

    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text).font(.cond(13, .semibold)).tracking(2).textCase(.uppercase).foregroundStyle(color)
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?
    var fg: Color = Theme.text
    var bg: Color = Theme.surface2

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 12, weight: .bold)) }
            Text(text).font(.barlow(13, .semibold))
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(bg, in: Capsule())
    }
}

/// Étiquette ACTIVE / EXPIRÉE…
struct StatusTag: View {
    let text: String
    var plein = true

    var body: some View {
        Text(text).font(.cond(12, .semibold)).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(plein ? Theme.bg : Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(plein ? Theme.accent : .clear, in: Capsule())
            .overlay { if !plein { Capsule().stroke(Theme.faint, lineWidth: 1) } }
    }
}

extension View {
    /// Carte anthracite arrondie.
    func card(border: Color = Theme.line, radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1))
    }

    func screenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// Titre de page : Barlow Condensed 40, majuscules.
    func pageTitle() -> some View {
        font(.cond(40)).textCase(.uppercase).foregroundStyle(Theme.text)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    var danger = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cond(17)).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(danger ? Theme.danger : Theme.bg)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(danger ? .clear : Theme.accent, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay { if danger { RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0x4A2229), lineWidth: 1) } }
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct OutlineButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.cond(17)).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 52)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Bouton carré 44 pt (modifier, supprimer, fermer).
struct IconButton: View {
    let systemImage: String
    let label: String
    var danger = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(danger ? Theme.danger : Theme.text)
                .frame(width: 44, height: 44)
                .background(danger ? .clear : Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { if danger { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: 0x4A2229), lineWidth: 1) } }
        }
        .accessibilityLabel(label)
    }
}

/// Bloc date « 18 / OCT ».
struct DateBlock: View {
    let date: Date?
    var highlighted = false

    var body: some View {
        VStack(spacing: 0) {
            Text(date.map { Self.jour.string(from: $0) } ?? "—").font(.cond(24)).foregroundStyle(highlighted ? Theme.accent : Theme.text)
            Text(date.map { Self.mois.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? "").font(.cond(11, .semibold)).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(highlighted ? Theme.accent : Theme.muted)
        }
        .frame(width: 52, height: 56)
        .background(highlighted ? Theme.accent.opacity(0.13) : Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let jour: DateFormatter = formatter("dd")
    private static let mois: DateFormatter = formatter("MMM")
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = format
        return f
    }
}

/// Ligne de liste : bloc date + titre + sous-titre + chevron.
struct RowCard: View {
    let date: Date?
    let title: String
    let subtitle: String
    var highlighted = false
    var subtitleColor: Color = Theme.muted
    var inscrit = false

    var body: some View {
        HStack(spacing: 14) {
            DateBlock(date: date, highlighted: highlighted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.cond(19, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(subtitle).font(.barlow(13)).foregroundStyle(subtitleColor)
            }
            Spacer(minLength: 0)
            if inscrit {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    .accessibilityLabel("Inscrit")
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.faint)
        }
        .card(border: highlighted ? Theme.accent : Theme.line, padding: 12)
    }
}

extension Date {
    static func fr(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = format
        return f
    }
}
