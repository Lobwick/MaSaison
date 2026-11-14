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
    @State private var heuresManifestations: [Int: String] = [:]
    @State private var prochaineNavigationURL: URL?
    @State private var photo: UIImage?
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
                            accent: homeAccent,
                            heureDepart: heureAffichee(prochaine),
                            agendaURL: agendaURL(for: prochaine.dateDebut),
                            navigationURL: prochaineNavigationURL
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
            .padding(.horizontal, 20).padding(.top, 0).padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .overlay { if isLoading && inscriptions.isEmpty { ProgressView().tint(Theme.accent) } }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await auth.client.sansCache { await load() } }
        .task { await load() }
        .task { await chargerPhotoProfil() }
    }

    private var enteteAccueil: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitleAndProfileActions(title: "ACCUEIL", photo: photo, accent: homeAccent)
            .padding(.top, -10)
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
                DateAndTime(date: i.dateDebut, heure: heureAffichee(i), highlighted: !i.estTerminee)
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

    private func heureAffichee(_ inscription: Inscription) -> String? {
        if let heure = heuresManifestations[inscription.manifestationID] { return heure }
        if let date = inscription.dateDebut {
            let cal = Calendar.current
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            if h != 0 || m != 0 {
                return Date.fr("HH:mm").string(from: date)
            }
        }
        guard let match = inscription.dateTexte.firstMatch(of: #/\b(\d{1,2})[:hH](\d{2})\b/#),
              let heure = Int(match.output.1), heure >= 0, heure <= 23 else { return nil }
        return String(format: "%02d:%@", heure, String(match.output.2))
    }

    private func normaliserHeure(_ brute: String?) -> String? {
        guard let brute = brute?.trimmingCharacters(in: .whitespacesAndNewlines), !brute.isEmpty else { return nil }
        if let d = Date.fr("HH:mm:ss").date(from: brute) { return Date.fr("HH:mm").string(from: d) }
        if let d = Date.fr("HH:mm").date(from: brute) { return Date.fr("HH:mm").string(from: d) }
        if brute.contains(":") { return brute }
        return nil
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
        // affichage immédiat des dernières données connues, puis mise à jour si le cache est périmé
        if inscriptions.isEmpty, let gardees = await auth.client.depuisCache({ try await auth.client.fetchInscriptions() }) {
            inscriptions = gardees
            resultats = await auth.client.depuisCache { try await auth.client.fetchResultats() } ?? resultats
        }
        do {
            inscriptions = try await auth.withSession { try await auth.client.fetchInscriptions() }
            await chargerHorairesInscriptions()
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
        prochaineNavigationURL = nil
        guard let prochaine = aVenir.first else { return }
        do {
            guard let manifestation = try await auth.withSession({
                try await auth.client.fetchManifestation(id: prochaine.manifestationID, libelle: prochaine.libelle)
            }) else { return }
            if let heure = normaliserHeure(manifestation.dateDebutHoraire) {
                heuresManifestations[prochaine.manifestationID] = heure
            }
            if let c = manifestation.adresse?.coordinate {
                prochaineNavigationURL = navigationURL(for: c.latitude, longitude: c.longitude)
                if let jour = prochaine.dateDebut, MeteoService.dansHorizon(jour) {
                    let jourEntier = try await MeteoService.prevision(latitude: c.latitude, longitude: c.longitude, jour: jour)
                    // restreinte au créneau des courses engagées (toutes si aucune ne correspond) plutôt qu'à la journée
                    let plage = AgendaService.plage(manifestation: manifestation, courses: coursesEngagees(prochaine, dans: manifestation))
                    meteoProchaine = plage.flatMap { p in jourEntier?.pendant(p) } ?? jourEntier
                }
            }
            meteoManifestationID = prochaine.manifestationID
        } catch {
            meteoProchaine = nil
            meteoManifestationID = prochaine.manifestationID
        }
    }

    /// Courses de la manifestation dont le niveau (« Adultes - 3e catégorie » → « 3e catégorie ») figure dans l'inscription.
    private func coursesEngagees(_ inscription: Inscription, dans manifestation: Manifestation) -> [ConfigNiveau] {
        let niveaux = Set(inscription.epreuves.flatMap(\.niveaux).map {
            ($0.components(separatedBy: " - ").last ?? $0).trimmingCharacters(in: .whitespaces).lowercased()
        })
        let engagees = manifestation.configNiveaux.filter { niveaux.contains($0.niveau.libelle.lowercased()) }
        return engagees.isEmpty ? manifestation.configNiveaux : engagees
    }

    private func chargerHorairesInscriptions() async {
        let cibles = Array(inscriptions.prefix(10))
        var map = heuresManifestations
        for inscription in cibles {
            do {
                let manifestation = try await auth.withSession {
                    try await auth.client.fetchManifestation(id: inscription.manifestationID, libelle: inscription.libelle)
                }
                if let heure = normaliserHeure(manifestation?.dateDebutHoraire) {
                    map[inscription.manifestationID] = heure
                }
            } catch {
                continue
            }
        }
        heuresManifestations = map
    }

    private func chargerPhotoProfil() async {
        do {
            let profil = try await auth.withSession { try await auth.client.fetchProfil() }
            guard let url = profil.photoURL else { return }
            if let data = try? await auth.withSession({ try await auth.client.download(url) }) {
                photo = UIImage(data: data)
            }
        } catch {
            photo = nil
        }
    }

    private func agendaURL(for date: Date?) -> URL? {
        guard let date else { return nil }
        let t = Int(date.timeIntervalSinceReferenceDate)
        return URL(string: "calshow:\(t)")
    }

    private func navigationURL(for latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        return components?.url
    }
}

private struct ProchaineCourseCard: View {
    let inscription: Inscription
    let dansAgenda: Bool
    let meteo: Meteo?
    let accent: Color
    let heureDepart: String?
    let agendaURL: URL?
    let navigationURL: URL?

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
                    Text("Départ \(heureDepartTexte)")
                        .font(.barlow(12, .semibold))
                        .foregroundStyle(Theme.textSoft)
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
                if let navigationURL {
                    Link(destination: navigationURL) {
                        Pill(text: "Naviguer", systemImage: "location.fill", fg: Theme.textSoft, bg: Theme.surface2)
                    }
                } else {
                    Pill(text: "Naviguer", systemImage: "location.fill", fg: Theme.faint, bg: Theme.surface2)
                }
                if let agendaURL {
                    Link(destination: agendaURL) {
                        Pill(
                            text: "Agenda",
                            systemImage: "calendar.badge.plus",
                            fg: dansAgenda ? accent : Theme.textSoft,
                            bg: dansAgenda ? accent.opacity(0.12) : Theme.surface2
                        )
                    }
                } else {
                    Pill(text: "Agenda", systemImage: "calendar.badge.plus", fg: Theme.faint, bg: Theme.surface2)
                }
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

    private var heureDepartTexte: String {
        if let heureDepart { return heureDepart.replacingOccurrences(of: ":", with: "h") }
        if let date = inscription.dateDebut { return Date.fr("HH'h'mm").string(from: date) }
        return "—"
    }

    private func meteoResume(_ meteo: Meteo) -> some View {
        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let min = Int(meteo.tempMin.rounded()), max = Int(meteo.tempMax.rounded())
        let pluie = meteo.pluieMm >= 0.1 ? String(format: "%.1f mm", meteo.pluieMm).replacingOccurrences(of: ".", with: ",") : "Sec"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconeMeteo(symbole: meteo.symbole, taille: 26)
                    .frame(width: 34)
                Text(meteo.libelle).font(.barlow(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Text(meteo.plage.map { "\($0.start.formatted(heure)) – \($0.end.formatted(heure))" } ?? "Journée")
                    .font(.barlow(11, .semibold)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 0) {
                meteoCell("TEMP.", min == max ? "\(max)°" : "\(min)°/\(max)°", icon: "thermometer.medium", tint: Color(hex: 0xD97706))
                Divider().frame(height: 40)
                meteoCell("PLUIE", "\(meteo.probaPluie)%", icon: "cloud.rain.fill", tint: Theme.secondary, detail: pluie)
                Divider().frame(height: 40)
                meteoCell("VENT", "\(Int(meteo.ventKmh.rounded())) km/h", icon: "wind", tint: Color(hex: 0x2563EB),
                          detail: meteo.rafalesKmh.map { "Rafales \(Int($0.rounded()))" })
            }
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
