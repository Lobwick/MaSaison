import SwiftUI

/// Small uppercase, letter-spaced label ("PROCHAINE COURSE").
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

/// ACTIVE / EXPIRED… tag.
struct StatusTag: View {
    let text: String
    var filled = true

    var body: some View {
        Text(text).font(.cond(12, .semibold)).tracking(1.5).textCase(.uppercase)
            .foregroundStyle(filled ? Theme.bg : Theme.muted)
            .padding(.horizontal, 10).padding(.vertical, 3)
            .background(filled ? Theme.accent : .clear, in: Capsule())
            .overlay { if !filled { Capsule().stroke(Theme.faint, lineWidth: 1) } }
    }
}

/// Standard header: title on the left, notifications then profile on the right.
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

/// 36 pt round header button (back, close…), styled like the notifications / profile actions.
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

/// Notifications then profile photo (opens the Profile tab).
struct ProfileActions: View {
    var photo: UIImage?
    var accent: Color = Theme.accent
    @AppStorage("ongletSelectionne") private var selectedTab = 0

    var body: some View {
        HStack(spacing: 10) {
           /* Image(systemName: "bell")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSoft)
                .frame(width: 36, height: 36)
                .background(Theme.surface2, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))*/
            Button {
                selectedTab = 4
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

/// Tone of an `ActionRow`: expected action (accent background), secondary (light bordered background) or destructive.
enum ActionTone { case primary, secondary, danger }

/// Visual of an action: icon badge, title and subtitle, chevron. Place it in a `Button`, `Link`,
/// `ShareLink` or `NavigationLink` with `.buttonStyle(ActionRowStyle())`; otherwise use `ActionRow`.
struct ActionRowLabel: View {
    let title: String
    var subtitle: String?
    let icon: String
    var tone: ActionTone = .secondary

    private var filled: Bool { tone == .primary }
    private var tint: Color { tone == .danger ? Theme.danger : Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(filled ? Color.white : tint)
                .frame(width: 40, height: 40)
                .background(filled ? Color.white.opacity(0.18) : tint.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cond(18)).tracking(1.2).textCase(.uppercase)
                    .foregroundStyle(filled ? Color.white : tone == .danger ? Theme.danger : Theme.text)
                if let subtitle {
                    Text(subtitle)
                        .font(.barlow(12))
                        .foregroundStyle(filled ? Color.white.opacity(0.85) : Theme.muted)
                        .lineLimit(2)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(filled ? Color.white.opacity(0.8) : Theme.faint)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .background(filled ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(filled ? Color.clear : tone == .danger ? Theme.danger.opacity(0.3) : Theme.line, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Card action as a button (see `ActionRowLabel`).
struct ActionRow: View {
    let title: String
    var subtitle: String?
    let icon: String
    var tone: ActionTone = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) { ActionRowLabel(title: title, subtitle: subtitle, icon: icon, tone: tone) }
            .buttonStyle(ActionRowStyle())
    }
}

/// Slight opacity when pressed, no other decoration.
struct ActionRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// 44 pt square button (edit, delete, close).
struct IconButton: View {
    let systemImage: String
    let label: String
    var danger = false
    let action: () -> Void

    var body: some View {
        let fill = danger ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.surface)
        Button(action: action) {
            Image(systemName: systemImage).font(.system(size: 16, weight: .semibold))
                .foregroundStyle(danger ? Theme.danger : Theme.text)
                .frame(width: 44, height: 44)
                .background(fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay { if danger { RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.35), lineWidth: 1) } }
        }
        .accessibilityLabel(label)
    }
}

/// "18 / OCT" date block.
struct DateBlock: View {
    let date: Date?
    var highlighted = false

    var body: some View {
        VStack(spacing: 0) {
            Text(date.map { Self.day.string(from: $0) } ?? "—").font(.cond(24)).foregroundStyle(highlighted ? Theme.accent : Theme.text)
            Text(date.map { Self.month.string(from: $0).replacingOccurrences(of: ".", with: "") } ?? "").font(.cond(11, .semibold)).tracking(1.5).textCase(.uppercase)
                .foregroundStyle(highlighted ? Theme.accent : Theme.muted)
        }
        .frame(width: 52, height: 56)
        .background(highlighted ? Theme.accent.opacity(0.13) : Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private static let day: DateFormatter = formatter("dd")
    private static let month: DateFormatter = formatter("MMM")
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = format
        return f
    }
}

/// Date + time block (time in a pill), used for race lists.
struct DateAndTime: View {
    let date: Date?
    var time: String? = nil
    var highlighted = false
    /// Highlight color (race status); `highlighted` alone uses the accent.
    var tint: Color? = nil
    /// Time text on a tinted background (dark for light tints such as yellow).
    var textOnTint: Color = Theme.bg

    private var isActive: Bool { highlighted || tint != nil }
    private var color: Color { tint ?? Theme.accent }

    var body: some View {
        VStack(spacing: 4) {
            Text(date.map { Self.day.string(from: $0) } ?? "—")
                .font(.cond(22, .semibold))
                .foregroundStyle(isActive ? color : Theme.text)
            Text(date.map { Self.month.string(from: $0).uppercased().replacingOccurrences(of: ".", with: "") } ?? "")
                .font(.cond(11, .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted)
            if let time, !time.isEmpty {
                Text(time)
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(isActive ? textOnTint : Theme.accent)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(isActive ? color : Theme.accent.opacity(0.13), in: Capsule())
            }
        }
        .frame(width: 62)
        .frame(minHeight: 74)
        .background(isActive ? color.opacity(0.1) : Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private static let day: DateFormatter = formatter("dd")
    private static let month: DateFormatter = formatter("MMM")
    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = format
        return f
    }
}

/// List row: date block + title + subtitle + chevron.
struct RowCard: View {
    let date: Date?
    let title: String
    let subtitle: String
    var highlighted = false
    var subtitleColor: Color = Theme.muted
    var registered = false
    var result: RaceResult?

    var body: some View {
        HStack(spacing: 14) {
            DateBlock(date: date, highlighted: highlighted)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.cond(19, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(subtitle).font(.barlow(13)).foregroundStyle(subtitleColor)
            }
            Spacer(minLength: 0)
            if let result {
                Text(result.shortText).font(.cond(result.place == nil ? 14 : 20, .semibold))
                    .foregroundStyle(result.place == nil ? Theme.muted : Theme.accent)
                    .padding(.horizontal, 10).frame(minHeight: 30)
                    .background(result.place == nil ? Theme.surface : Theme.accent.opacity(0.13), in: Capsule())
                    .accessibilityLabel(result.place.map { "Classement : \($0)" } ?? "Résultat : \(result.ranking)")
            }
            if registered {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 22)).foregroundStyle(Theme.accent)
                    .accessibilityLabel("Inscrit")
            }
            Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.faint)
        }
        .card(border: highlighted ? Theme.accent : Theme.line, padding: 12)
    }
}
