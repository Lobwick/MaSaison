import SwiftUI

/// Accueil : prochaine course avec compte à rebours, puis inscriptions à venir et terminées.
struct MesInscriptionsView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case aVenir = "À venir"
        case terminees = "Terminées"
        var id: String { rawValue }
    }

    @Environment(AuthModel.self) private var auth
    @Environment(AgendaStore.self) private var agenda
    @State private var inscriptions: [Inscription] = []
    @State private var resultats: [Resultat] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var segment: Segment = .aVenir
    @State private var meteoProchaine: Meteo?
    @State private var meteoManifestationID: Int?
    private let homeAccent = Color(hex: 0x006948)

    private var aVenir: [Inscription] {
        inscriptions.filter { !$0.estTerminee }.sorted { ($0.dateDebut ?? .distantFuture) < ($1.dateDebut ?? .distantFuture) }
    }
    private var terminees: [Inscription] {
        inscriptions.filter(\.estTerminee).sorted { ($0.dateFin ?? .distantPast) > ($1.dateFin ?? .distantPast) }
    }

    private var listeAffichee: [Inscription] {
        segment == .aVenir ? aVenir : terminees
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                enteteAccueil

                if let prochaine = aVenir.first {
                    NavigationLink { InscriptionDetailLoader(inscription: prochaine) } label: {
                        ProchaineCourseCard(
                            inscription: prochaine,
                            dansAgenda: agenda.ajoute(manifestation: prochaine.manifestationID),
                            meteo: meteoManifestationID == prochaine.manifestationID ? meteoProchaine : nil,
                            accent: homeAccent
                        )
                    }
                    .buttonStyle(.plain)
                } else if !isLoading && errorMessage == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("PROCHAINE COURSE")
                        Text("Aucune inscription à venir").font(.cond(24, .semibold)).textCase(.uppercase)
                        Text("Cherchez une manifestation dans l'onglet Courses.").font(.barlow(14)).foregroundStyle(Theme.muted)
                    }
                    .card(radius: 24, padding: 20)
                }

                segmentControl

                if !listeAffichee.isEmpty {
                    section(segment == .aVenir ? "Prochain départ" : "Historique des courses",
                            trailing: segment == .aVenir ? "Demain après-midi" : nil) {
                        ForEach(listeAffichee) { ligne($0) }
                    }
                } else {
                    Text(segment == .aVenir ? "Aucune course à venir." : "Aucune course terminée.")
                        .font(.barlow(14))
                        .foregroundStyle(Theme.muted)
                        .card(padding: 14)
                }

                if let errorMessage {
                    Text(errorMessage).font(.barlow(14)).foregroundStyle(Theme.danger)
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .overlay { if isLoading && inscriptions.isEmpty { ProgressView().tint(Theme.accent) } }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await load() }
        .task { await load() }
    }

    private var saison: String {
        let maintenant = Date()
        let annee = Calendar.current.component(.year, from: maintenant)
        let debut = Calendar.current.component(.month, from: maintenant) >= 9 ? annee : annee - 1
        return "\(debut)/\(debut + 1)"
    }

    private var enteteAccueil: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(homeAccent.opacity(0.9))
                    .frame(width: 36, height: 36)
                    .background(homeAccent.opacity(0.08), in: Circle())
                Text("UFOLEP · SAISON \(saison.replacingOccurrences(of: "/", with: "/"))")
                    .font(.barlow(16, .semibold))
                    .foregroundStyle(homeAccent)
                Spacer()
                Image(systemName: "bell")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .frame(width: 36, height: 36)
                    .background(Theme.surface2, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            HStack(alignment: .top) {
                Text("ACCUEIL")
                .font(.cond(34))
                .foregroundStyle(Theme.text)
                Spacer()
            }
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 4) {
            segmentButton(.aVenir, compteur: aVenir.count)
            segmentButton(.terminees, compteur: terminees.count)
        }
        .padding(4)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func segmentButton(_ cible: Segment, compteur: Int) -> some View {
        let actif = segment == cible
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { segment = cible }
        } label: {
            HStack(spacing: 6) {
                Text(cible.rawValue).font(.barlow(13, .semibold))
                Text("\(compteur)")
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(actif ? Color.white : Theme.textSoft)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(actif ? homeAccent : Theme.surface, in: Capsule())
            }
            .foregroundStyle(actif ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(actif ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ titre: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(titre)
                Spacer()
                if let trailing {
                    Text(trailing).font(.barlow(13, .semibold)).foregroundStyle(homeAccent)
                }
            }
            content()
        }
    }

    private func ligne(_ i: Inscription) -> some View {
        NavigationLink { InscriptionDetailLoader(inscription: i) } label: {
            HStack(spacing: 14) {
                DateBlock(date: i.dateDebut, highlighted: !i.estTerminee)
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(i.libelle).font(.cond(20, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text([i.organisateur, i.epreuves.flatMap(\.niveaux).first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.barlow(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                if i.estTerminee, let r = resultat(de: i) {
                    Text(r.texteCourt)
                        .font(.barlow(12, .semibold))
                        .foregroundStyle(Theme.textSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surface2, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(!i.estTerminee ? homeAccent.opacity(0.25) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// Par identifiant de manifestation, à défaut par date (les libellés diffèrent d'une page à l'autre).
    private func resultat(de i: Inscription) -> Resultat? {
        resultats.first { $0.manifestationID == i.manifestationID }
            ?? resultats.first { $0.date != nil && $0.date == i.dateDebut }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            inscriptions = try await auth.withSession { try await auth.client.fetchInscriptions() }
            // les résultats sont un bonus : leur échec ne bloque pas l'accueil
            resultats = (try? await auth.withSession { try await auth.client.fetchResultats() }) ?? resultats
            await chargerMeteoProchaine()
        } catch {
            errorMessage = error.localizedDescription
            meteoProchaine = nil
            meteoManifestationID = nil
        }
    }

    private func chargerMeteoProchaine() async {
        meteoProchaine = nil
        meteoManifestationID = nil
        guard let prochaine = aVenir.first, let jour = prochaine.dateDebut, MeteoService.dansHorizon(jour) else { return }
        do {
            guard let manifestation = try await auth.withSession({
                try await auth.client.fetchManifestation(id: prochaine.manifestationID, libelle: prochaine.libelle)
            }),
            let c = manifestation.adresse?.coordinate else { return }
            meteoProchaine = try await MeteoService.prevision(latitude: c.latitude, longitude: c.longitude, jour: jour)
            meteoManifestationID = prochaine.manifestationID
        } catch {
            meteoProchaine = nil
            meteoManifestationID = prochaine.manifestationID
        }
    }
}

private struct ProchaineCourseCard: View {
    let inscription: Inscription
    let dansAgenda: Bool
    let meteo: Meteo?
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("BRIEF JOUR DE COURSE")
                Spacer()
                Pill(text: "\(statutCourt) CONFIRMÉ", fg: accent, bg: accent.opacity(0.12))
            }
            HStack(spacing: 18) {
                anneau
                VStack(alignment: .leading, spacing: 6) {
                    Text(inscription.libelle).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text([inscription.organisateur, inscription.epreuves.flatMap(\.niveaux).first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.barlow(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    if let date = inscription.dateDebut {
                        Text("Départ \(Date.fr("HH'h'mm").string(from: date))")
                            .font(.barlow(12, .semibold))
                            .foregroundStyle(Theme.textSoft)
                    }
                    HStack(spacing: 8) {
                        Label(inscription.organisateur, systemImage: "mappin")
                    }
                    .font(.barlow(12, .semibold))
                    .foregroundStyle(Theme.muted)
                }
            }
            if let meteo {
                meteoResume(meteo)
            }
            Divider().overlay(Theme.line)
            HStack {
                Label("Engagement validé", systemImage: "checkmark.seal")
                    .font(.barlow(13, .semibold))
                    .foregroundStyle(accent)
                Spacer()
                Pill(text: "Circuit", systemImage: "map", fg: Theme.textSoft, bg: Theme.surface2)
                Pill(text: "Agenda", systemImage: "calendar.badge.plus", fg: accent, bg: accent.opacity(0.12))
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .overlay(alignment: .top) {
            LinearGradient(colors: [accent, Color(hex: 0x85F8C4), Theme.secondary],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var joursRestants: Int {
        guard let debut = inscription.dateDebut else { return 0 }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: debut)).day ?? 0)
    }

    private var secondesRestantes: TimeInterval {
        guard let debut = inscription.dateDebut else { return 0 }
        return debut.timeIntervalSinceNow
    }

    private var heuresRestantes: Int {
        max(1, Int(ceil(secondesRestantes / 3600)))
    }

    /// L'anneau est décoratif : il se remplit à l'approche de la course (sur 30 jours).
    private var anneau: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 9)
            Circle().trim(from: 0, to: max(0.05, 1 - Double(min(joursRestants, 30)) / 30))
                .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(libelleCompteRebours).font(.cond(40)).foregroundStyle(Theme.text)
                Text(inscription.dateDebut.map { Date.fr("EEE d MMM").string(from: $0).uppercased().replacingOccurrences(of: ".", with: "") } ?? "")
                    .font(.cond(11, .medium)).tracking(1.5).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 112, height: 112)
    }

    private var libelleCompteRebours: String {
        if secondesRestantes <= 0 { return "J" }
        if secondesRestantes < 86_400 { return "H-\(heuresRestantes)" }
        return "J-\(joursRestants)"
    }

    private var statutCourt: String {
        if secondesRestantes <= 0 { return "Jour J" }
        if secondesRestantes < 86_400 { return "H-\(heuresRestantes)" }
        return "J-\(joursRestants)"
    }

    private func meteoResume(_ meteo: Meteo) -> some View {
        HStack(spacing: 0) {
            meteoCell("TEMP.", "\(Int(meteo.tempMin.rounded()))°/\(Int(meteo.tempMax.rounded()))°", icon: "thermometer.sun.fill", tint: Color(hex: 0xD97706), detail: meteo.libelle)
            Divider().frame(height: 40)
            meteoCell("PLUIE", "\(meteo.probaPluie)%", icon: "drop.fill", tint: Theme.secondary)
            Divider().frame(height: 40)
            meteoCell("VENT", "\(Int(meteo.ventKmh.rounded())) km/h", icon: "wind", tint: Color(hex: 0x2563EB))
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func meteoCell(_ titre: String, _ valeur: String, icon: String, tint: Color, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(titre).font(.barlow(10, .semibold)).foregroundStyle(Theme.muted)
                Text(valeur).font(.barlow(14, .semibold)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.barlow(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}

/// Pastilles qui passent à la ligne.
struct FlowPills<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 8) { content }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let largeur = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, ligne: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > largeur, x > 0 { x = 0; y += ligne + spacing; ligne = 0 }
            x += t.width + spacing; ligne = max(ligne, t.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: maxX, height: y + ligne)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, ligne: CGFloat = 0
        for v in subviews {
            let t = v.sizeThatFits(.unspecified)
            if x + t.width > bounds.maxX, x > bounds.minX { x = bounds.minX; y += ligne + spacing; ligne = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(t))
            x += t.width + spacing; ligne = max(ligne, t.height)
        }
    }
}

/// Charge la manifestation complète (API calendrier) d'une inscription puis affiche son détail.
struct InscriptionDetailLoader: View {
    @Environment(AuthModel.self) private var auth
    let inscription: Inscription
    @State private var manifestation: Manifestation?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let manifestation {
                ManifestationDetailView(manifestation: manifestation)
            } else if let errorMessage {
                ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(errorMessage)).screenBackground()
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground()
            }
        }
        .task {
            do {
                manifestation = try await auth.withSession {
                    try await auth.client.fetchManifestation(id: inscription.manifestationID, libelle: inscription.libelle)
                }
                if manifestation == nil { errorMessage = "Manifestation introuvable." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
