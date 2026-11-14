import SwiftUI
import TipKit

struct ProfileView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(FilterStore.self) private var store
    @Environment(LicenseCardStore.self) private var cardStore
    @AppStorage("boutonAgenda") private var showsCalendarButton = true
    @AppStorage("echauffementMinutes") private var warmUp = 60
    @State private var profile: Profile?
    @State private var photo: UIImage?
    @State private var pastCardsExpanded = false
    @State private var selectedCardIndex = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                header

                section("MES CARTES") { myCardsSection }

                section("RÉGLAGES ET PRÉFÉRENCES") { settingsSection }

                section("À PROPOS") {
                    UnofficialNotice().card()
                }

                ActionRow(title: "Se déconnecter", icon: "rectangle.portrait.and.arrow.right", tone: .danger) { auth.logout() }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            profile = try? await auth.withSession { try await auth.client.fetchProfile() }
            // the site's photo requires the member's session; without a photo, initials are shown
            if let url = profile?.photoURL,
               let data = try? await auth.withSession({ try await auth.client.download(url) }) {
                photo = UIImage(data: data)
            }
        }
        .onAppear { AppTips.home.invalidate(reason: .actionPerformed) }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleAndProfileActions(title: "PROFIL", photo: photo, accent: Theme.accent)
            HStack(spacing: 16) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .accessibilityLabel("Photo de profil")
                    } else {
                        Text(initials).font(.cond(30)).foregroundStyle(Theme.text)
                    }
                }
                .frame(width: 76, height: 76).background(Theme.surface2).clipShape(Circle())
                .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(displayName).font(.cond(34)).textCase(.uppercase).foregroundStyle(Theme.text).lineLimit(2)
                    if let card = cardStore.activeCards.first {
                        Text([card.committee, card.club].filter { !$0.isEmpty }.joined(separator: " · ")).font(.barlow(14)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
            }
        }
        .padding(.top, -4)
    }

    /// "Monsieur MOULIN Felix" → "MOULIN Felix"
    private var nameTokens: [String] {
        (profile?.name ?? "").split(separator: " ").map(String.init).filter { !["monsieur", "madame", "mademoiselle", "m.", "mme", "mlle"].contains($0.lowercased()) }
    }
    private var displayName: String { nameTokens.isEmpty ? "Mon profil" : nameTokens.joined(separator: " ") }
    private var initials: String {
        guard nameTokens.count >= 2 else { return String(nameTokens.first?.prefix(1) ?? "?") }
        return (String(nameTokens[1].prefix(1)) + String(nameTokens[0].prefix(1))).uppercased()
    }

    // MARK: past cards

    private var pastCards: [LicenseCard] { cardStore.cards.filter { !$0.isActive } }

    private var pastCardsSection: some View {
        VStack(spacing: 0) {
            Button { withAnimation { pastCardsExpanded.toggle() } } label: {
                HStack {
                    Text("Anciennes cartes").font(.cond(17, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.text)
                    Text("(\(pastCards.count))").font(.cond(17, .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(pastCardsExpanded ? 180 : 0))
                }
                .padding(18)
            }
            .buttonStyle(.plain)
            if pastCardsExpanded {
                VStack(spacing: 8) { ForEach(pastCards) { LicenseCardRow(card: $0) } }
                    .padding(.horizontal, 10).padding(.bottom, 12)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: building blocks

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(title)
            content()
        }
    }

    private var myCardsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text("\(activeCards.count) actives")
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(seasonLabel)
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.1), in: Capsule())
            }

            if activeCards.isEmpty {
                Text("Aucune carte trouvée.").font(.barlow(14)).foregroundStyle(Theme.muted).card()
            } else {
                TabView(selection: $selectedCardIndex) {
                    ForEach(Array(activeCards.enumerated()), id: \.offset) { index, card in
                        LicenseWalletCard(card: card)
                            .padding(.horizontal, 2)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 238)

                HStack {
                    HStack(spacing: 6) {
                        ForEach(activeCards.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == selectedCardIndex ? Theme.accent : Theme.faint.opacity(0.5))
                                .frame(width: index == selectedCardIndex ? 20 : 6, height: 6)
                        }
                    }
                    Spacer()
                    Label("Balayer pour changer de licence", systemImage: "hand.draw")
                        .font(.barlow(11))
                        .foregroundStyle(Theme.muted)
                }

                Button {
                    // Matches the mockup: CTA present, behavior already handled in the event detail.
                } label: {
                    Label("Présenter le QR code au commissaire", systemImage: "qrcode")
                        .font(.barlow(15, .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            if !pastCards.isEmpty { pastCardsSection }
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                EventFilterSettingsView()
            } label: {
                SettingsLinkRow(
                    icon: "slider.horizontal.3",
                    iconColor: Theme.accent,
                    title: "Filtres de manifestation",
                    subtitle: eventFiltersSummary
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.line)

            NavigationLink {
                CalendarSettingsView()
            } label: {
                SettingsLinkRow(
                    icon: "calendar",
                    iconColor: Theme.secondary,
                    title: "Synchronisation Agenda",
                    subtitle: calendarSummary,
                    subtitleColor: Theme.accent
                )
            }
            .buttonStyle(.plain)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func durationText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    private var eventFiltersSummary: String {
        let sports = store.sportsSummary(store.defaultSports)
        let deps = store.departmentsSummary(store.defaultDepartments)
        return "\(sports) • Dép. \(deps)"
    }

    private var calendarSummary: String {
        guard showsCalendarButton else { return "Inactif" }
        return "Actif (+\(durationText(warmUp)) échauffement)"
    }

    private var activeCards: [LicenseCard] { cardStore.activeCards }

    private var seasonLabel: String {
        guard let season = activeCards.first?.season, !season.isEmpty else { return "Saison" }
        return "Saison \(season)"
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    var subtitleColor: Color = Theme.muted

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(iconColor.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.barlow(20, .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(subtitle)
                    .font(.barlow(14, .semibold))
                    .foregroundStyle(subtitleColor)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(16)
    }
}

private struct LicenseWalletCard: View {
    let card: LicenseCard

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: 0x12241D), Color(hex: 0x040907)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    Circle()
                        .fill(Color(hex: 0x85F8C4).opacity(0.26))
                        .blur(radius: 36)
                        .frame(width: 120, height: 120)
                        .offset(x: 210, y: -30)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color(hex: 0x85F8C4).opacity(0.25), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "wave.3.right")
                        Text("UFOLEP PASS")
                    }
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(Color(hex: 0x85F8C4))

                    Spacer()

                    HStack(spacing: 6) {
                        Circle().fill(Color(hex: 0x85F8C4)).frame(width: 6, height: 6)
                        Text("ACTIVE")
                    }
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(Color(hex: 0x85F8C4))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(hex: 0x85F8C4).opacity(0.2), in: Capsule())
                    .overlay(Capsule().stroke(Color(hex: 0x85F8C4).opacity(0.35), lineWidth: 1))
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(card.discipline.uppercased()).font(.cond(22, .semibold)).foregroundStyle(Color.white)
                    Text(card.season).font(.cond(22, .semibold)).foregroundStyle(Color(hex: 0x85F8C4))
                }
                Text(card.level ?? "Licence Compétition Nationale")
                    .font(.barlow(11))
                    .foregroundStyle(Color.white.opacity(0.75))

                FlowPills {
                    if let level = card.level {
                        Pill(text: level, systemImage: "medal.fill", fg: Color(hex: 0x85F8C4), bg: Color.white.opacity(0.1))
                    }
                    if let age = card.ageCategory {
                        Pill(text: age, systemImage: "person.fill", fg: Color.white.opacity(0.9), bg: Color.white.opacity(0.1))
                    }
                }

                Divider().overlay(Color.white.opacity(0.12))
                HStack {
                    Label("Expire le \(card.expiresOn)", systemImage: "calendar")
                        .font(.barlow(12))
                        .foregroundStyle(Color.white.opacity(0.78))
                    Spacer()
                    Image(systemName: "qrcode")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .frame(width: 30, height: 30)
                        .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .padding(20)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 20, x: 0, y: 10)
    }
}

private struct EventFilterSettingsView: View {
    @Environment(FilterStore.self) private var store
    @Environment(LicenseCardStore.self) private var cardStore

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("RÉGLAGES MANIFESTATIONS")
                InlineTipView(tip: AppTips.profile)
                filterRow("Sport par défaut", value: store.sportsSummary(store.defaultSports), isActive: !store.defaultSports.isEmpty,
                          editor: MultiSelectView.sports(store.sports, selection: $store.defaultSports),
                          onDelete: { store.defaultSports = [] })
                filterRow("Départements par défaut", value: store.departmentsSummary(store.defaultDepartments), isActive: !store.defaultDepartments.isEmpty,
                          editor: MultiSelectView.departments(store.departments, selection: $store.defaultDepartments),
                          onDelete: { store.defaultDepartments = [] })
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        store.resetToDefaults(cards: cardStore.cards)
                    } label: {
                        Label("Rétablir les filtres par défaut", systemImage: "arrow.counterclockwise")
                            .font(.cond(15)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.textSoft)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    Text("Remet les départements et le sport d'origine (déduits de vos cartes) après une suppression ou une modification.")
                        .font(.barlow(12)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 24)
        }
        .screenBackground()
        .navigationTitle("Manifestations")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func filterRow<Destination: View>(_ title: String, value: String, isActive: Bool, editor: Destination, onDelete: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(value).font(.cond(20)).foregroundStyle(isActive ? Theme.accent : Theme.muted).multilineTextAlignment(.trailing)
            }
            HStack(spacing: 10) {
                NavigationLink { editor } label: {
                    Label("Modifier", systemImage: "pencil").font(.cond(14)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button(action: onDelete) {
                    Label("Supprimer", systemImage: "trash").font(.cond(14)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: 0x4A2229), lineWidth: 1))
                }
                .disabled(!isActive).opacity(isActive ? 1 : 0.4)
            }
        }
        .card(padding: 16)
    }
}

private struct CalendarSettingsView: View {
    @AppStorage("boutonAgenda") private var showsCalendarButton = true
    @AppStorage("echauffementMinutes") private var warmUp = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("RÉGLAGES AGENDA")
                VStack(spacing: 0) {
                    HStack {
                        Text("Bouton « Ajouter à l'agenda »").font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Toggle("", isOn: $showsCalendarButton).labelsHidden().tint(Theme.accent)
                    }
                    .padding(16)
                    Divider().overlay(Theme.line)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Échauffement").font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                            Text("Avant l'heure d'appel").font(.barlow(12)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        HStack(spacing: 10) {
                            stepButton("minus", "Réduire l'échauffement") { warmUp = max(0, warmUp - 5) }
                            Text(durationText(warmUp)).font(.cond(26)).foregroundStyle(Theme.text).frame(minWidth: 64)
                            stepButton("plus", "Augmenter l'échauffement") { warmUp = min(240, warmUp + 5) }
                        }
                    }
                    .padding(16)
                    .disabled(!showsCalendarButton).opacity(showsCalendarButton ? 1 : 0.4)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
                Text("Exemple : appel à 13:45, échauffement à \(example). Ce créneau est ajouté à l'agenda.")
                    .font(.barlow(12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20).padding(.vertical, 24)
        }
        .screenBackground()
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                .frame(width: 44, height: 44).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    private func durationText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    private var example: String {
        let total = 13 * 60 + 45 - warmUp
        return String(format: "%02d:%02d", max(0, total) / 60, max(0, total) % 60)
    }
}

private struct LicenseCardRow: View {
    let card: LicenseCard

    var body: some View {
        if card.isActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(card.discipline).textCase(.uppercase).foregroundStyle(Theme.text)
                        Text(card.season).foregroundStyle(Theme.muted)
                    }
                    .font(.cond(28))
                    Spacer()
                    StatusTag(text: card.status)
                }
                FlowPills {
                    if let n = card.level { Pill(text: n, fg: Theme.accent, bg: Theme.accent.opacity(0.13)) }
                    if let a = card.ageCategory { Pill(text: a) }
                }
                Text("Expire le \(card.expiresOn)").font(.barlow(13)).foregroundStyle(Theme.muted)
            }
            .card(border: Theme.accent, radius: 24, padding: 18)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(card.discipline) \(card.season)").font(.cond(20)).textCase(.uppercase).foregroundStyle(Theme.text)
                    Text("\(card.level ?? card.ageCategory ?? "") · expirée le \(card.expiresOn)").font(.barlow(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                StatusTag(text: "Expirée", filled: false)
            }
            .card(radius: 24, padding: 14)
            .opacity(0.6)
        }
    }
}
