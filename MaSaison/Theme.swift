import SwiftUI

/// Direction visuelle claire inspirée des apps Apple : fond blanc, cartes en matériau, accent système.
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
    /// Liste d'envies (signet, pastille, bloc date).
    static let envie = Color(hex: 0xE5B000)

    /// Plus de police custom : on garde la typo SF Pro native.
    static func registerFonts() {
        // no-op
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension Font {
    enum Poids { case medium, semibold, bold }

    /// SF Pro (texte standard iOS).
    static func sfPro(_ size: CGFloat, _ poids: Poids = .medium) -> Font {
        let weight: Font.Weight = switch poids {
        case .medium: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
        return .system(size: size, weight: weight, design: .default)
    }

    /// SF Compact-like (équivalent visuel via design rounded).
    static func sfCompact(_ size: CGFloat, _ poids: Poids = .bold) -> Font {
        let weight: Font.Weight = switch poids {
        case .medium: .medium
        case .semibold: .semibold
        case .bold: .bold
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    /// SF Mono pour les valeurs/horaires.
    static func sfMono(_ size: CGFloat, _ poids: Poids = .medium) -> Font {
        let weight: Font.Weight = switch poids {
        case .medium: .regular
        case .semibold: .semibold
        case .bold: .bold
        }
        return .system(size: size, weight: weight, design: .monospaced)
    }

    // Compatibilité existante
    static func cond(_ size: CGFloat, _ poids: Poids = .bold) -> Font {
        sfCompact(size, poids)
    }

    static func barlow(_ size: CGFloat, _ poids: Poids = .medium) -> Font {
        sfPro(size, poids)
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
    /// Carte « liquid glass ».
    func card(border: Color = Theme.line, radius: CGFloat = 20, padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(border, lineWidth: 1))
    }

    func screenBackground() -> some View {
        background(Theme.bg.ignoresSafeArea())
    }

    /// Titre de page style Apple.
    func pageTitle() -> some View {
        font(.cond(34)).textCase(.uppercase).foregroundStyle(Theme.text)
    }
}

/// En-tête standardisé : titre à gauche, notifications puis profil à droite.
struct TitleAndProfileActions: View {
    let title: String
    var photo: UIImage?
    var accent: Color = Theme.accent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(title).pageTitle()
            Spacer()
            ProfileActions(photo: photo, accent: accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Bouton rond 36 pt de l'en-tête (retour, fermer…), au style des actions notifications / profil.
struct HeaderCircleButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 36, height: 36)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// Notifications puis photo de profil (ouvre l'onglet Profil).
struct ProfileActions: View {
    var photo: UIImage?
    var accent: Color = Theme.accent
    @AppStorage("ongletSelectionne") private var onglet = 0

    var body: some View {
        HStack(spacing: 10) {
           /* Image(systemName: "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSoft)
                .frame(width: 36, height: 36)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))*/
            Button {
                onglet = 4
            } label: {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(accent.opacity(0.9))
                    }
                }
                .frame(width: 36, height: 36)
                .background(accent.opacity(0.08), in: Circle())
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Ouvrir le profil")
        }
    }
}

/// Ton d'une `ActionRow` : action attendue (fond accent), secondaire (fond clair bordé) ou destructive.
enum ActionTon { case principal, secondaire, danger }

/// Visuel d'une action : pastille icône, titre et sous-titre, chevron. À placer dans un `Button`, `Link`,
/// `ShareLink` ou `NavigationLink` avec `.buttonStyle(ActionRowStyle())` ; sinon utiliser `ActionRow`.
struct ActionRowLabel: View {
    let titre: String
    var sousTitre: String?
    let icone: String
    var ton: ActionTon = .secondaire

    private var plein: Bool { ton == .principal }
    private var teinte: Color { ton == .danger ? Theme.danger : Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(plein ? Color.white : teinte)
                .frame(width: 40, height: 40)
                .background(plein ? Color.white.opacity(0.18) : teinte.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(titre)
                    .font(.cond(18)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(plein ? Color.white : ton == .danger ? Theme.danger : Theme.text)
                if let sousTitre {
                    Text(sousTitre)
                        .font(.barlow(12))
                        .foregroundStyle(plein ? Color.white.opacity(0.85) : Theme.muted)
                        .lineLimit(2)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(plein ? Color.white.opacity(0.8) : Theme.faint)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(plein ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(plein ? Color.clear : ton == .danger ? Theme.danger.opacity(0.3) : Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Action d'une carte sous forme de bouton (voir `ActionRowLabel`).
struct ActionRow: View {
    let titre: String
    var sousTitre: String?
    let icone: String
    var ton: ActionTon = .secondaire
    let action: () -> Void

    var body: some View {
        Button(action: action) { ActionRowLabel(titre: titre, sousTitre: sousTitre, icone: icone, ton: ton) }
            .buttonStyle(ActionRowStyle())
    }
}

/// Légère opacité à l'appui, sans autre décoration.
struct ActionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Bouton carré 44 pt (modifier, supprimer, fermer).
struct IconButton: View {
    let systemImage: String
    let label: String
    var danger = false
    let action: () -> Void

    var body: some View {
        let fond = danger ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.surface)
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(danger ? Theme.danger : Theme.text)
                .frame(width: 44, height: 44)
                .background(fond, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { if danger { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.35), lineWidth: 1) } }
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

/// Bloc date + heure (heure en pastille), utilisé pour les listes de courses.
struct DateAndTime: View {
    let date: Date?
    var heure: String? = nil
    var highlighted = false
    /// Couleur de mise en avant (état de la course) ; `highlighted` seul utilise l'accent.
    var teinte: Color? = nil
    /// Texte de l'heure sur fond teinté (sombre pour les teintes claires comme le jaune).
    var texteSurTeinte: Color = Theme.bg

    private var actif: Bool { highlighted || teinte != nil }
    private var couleur: Color { teinte ?? Theme.accent }

    var body: some View {
        VStack(spacing: 4) {
            Text(date.map { Self.jour.string(from: $0) } ?? "—")
                .font(.cond(22, .semibold))
                .foregroundStyle(actif ? couleur : Theme.text)
            Text(date.map { Self.mois.string(from: $0).uppercased().replacingOccurrences(of: ".", with: "") } ?? "")
                .font(.cond(11, .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            if let heure, !heure.isEmpty {
                Text(heure)
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(actif ? texteSurTeinte : Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(actif ? couleur : Theme.accent.opacity(0.13), in: Capsule())
            }
        }
        .frame(width: 62)
        .frame(minHeight: 74)
        .background(actif ? couleur.opacity(0.1) : Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    var resultat: Resultat?

    var body: some View {
        HStack(spacing: 14) {
            DateBlock(date: date, highlighted: highlighted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.cond(19, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(subtitle).font(.barlow(13)).foregroundStyle(subtitleColor)
            }
            Spacer(minLength: 0)
            if let resultat {
                Text(resultat.texteCourt).font(.cond(resultat.place == nil ? 14 : 20, .semibold))
                    .foregroundStyle(resultat.place == nil ? Theme.muted : Theme.accent)
                    .padding(.horizontal, 10).frame(minHeight: 30)
                    .background(resultat.place == nil ? Theme.surface : Theme.accent.opacity(0.13), in: Capsule())
                    .accessibilityLabel(resultat.place.map { "Classement : \($0)" } ?? "Résultat : \(resultat.classement)")
            }
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
