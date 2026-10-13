import SwiftUI

/// Accueil : prochaine course avec compte à rebours, puis inscriptions à venir et terminées.
struct MesInscriptionsView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(AgendaStore.self) private var agenda
    @State private var inscriptions: [Inscription] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    private var aVenir: [Inscription] {
        inscriptions.filter { !$0.estTerminee }.sorted { ($0.dateDebut ?? .distantFuture) < ($1.dateDebut ?? .distantFuture) }
    }
    private var terminees: [Inscription] {
        inscriptions.filter(\.estTerminee).sorted { ($0.dateFin ?? .distantPast) > ($1.dateFin ?? .distantPast) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow("UFOLEP · SAISON \(saison)", color: Theme.accent)
                    Text("Mes inscriptions").pageTitle()
                }

                AstuceView(tip: AppTips.accueil)

                if let prochaine = aVenir.first {
                    NavigationLink { InscriptionDetailLoader(inscription: prochaine) } label: {
                        ProchaineCourseCard(inscription: prochaine, dansAgenda: agenda.ajoute(manifestation: prochaine.manifestationID))
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

                HStack(spacing: 12) {
                    compteur(aVenir.count, "À venir", accent: true)
                    compteur(terminees.count, "Terminées", accent: false)
                }

                if !aVenir.isEmpty {
                    section("À venir") { ForEach(aVenir) { ligne($0) } }
                }
                if !terminees.isEmpty {
                    section("Terminées") { ForEach(terminees) { ligne($0) } }
                }

                if let errorMessage {
                    Text(errorMessage).font(.barlow(14)).foregroundStyle(Theme.danger)
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
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

    private func compteur(_ valeur: Int, _ libelle: String, accent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(valeur)").font(.cond(44)).foregroundStyle(accent ? Theme.accent : Theme.text)
            Eyebrow(libelle)
        }
        .card(padding: 14)
    }

    private func section<Content: View>(_ titre: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(titre)
            content()
        }
    }

    private func ligne(_ i: Inscription) -> some View {
        NavigationLink { InscriptionDetailLoader(inscription: i) } label: {
            RowCard(date: i.dateDebut, title: i.libelle,
                    subtitle: [i.organisateur, i.epreuves.flatMap(\.niveaux).first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            inscriptions = try await auth.withSession { try await auth.client.fetchInscriptions() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ProchaineCourseCard: View {
    let inscription: Inscription
    let dansAgenda: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Eyebrow("PROCHAINE COURSE")
                Spacer()
                StatusTag(text: inscription.epreuves.first?.statut ?? "Active")
            }
            HStack(spacing: 18) {
                anneau
                VStack(alignment: .leading, spacing: 6) {
                    Text(inscription.libelle).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text([inscription.organisateur, inscription.type].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.barlow(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            FlowPills {
                ForEach(categories, id: \.self) { Pill(text: $0) }
                if dansAgenda { Pill(text: "Dans l'agenda", systemImage: "calendar.badge.checkmark", fg: Theme.accent) }
            }
        }
        .card(radius: 24, padding: 20)
    }

    private var categories: [String] {
        inscription.epreuves.flatMap(\.niveaux).map { $0.replacingOccurrences(of: " - ", with: " · ") }
    }

    private var joursRestants: Int {
        guard let debut = inscription.dateDebut else { return 0 }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: debut)).day ?? 0)
    }

    /// L'anneau est décoratif : il se remplit à l'approche de la course (sur 30 jours).
    private var anneau: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 9)
            Circle().trim(from: 0, to: max(0.05, 1 - Double(min(joursRestants, 30)) / 30))
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(joursRestants == 0 ? "J" : "J-\(joursRestants)").font(.cond(40)).foregroundStyle(Theme.text)
                Text(inscription.dateDebut.map { Date.fr("EEE d MMM").string(from: $0).uppercased().replacingOccurrences(of: ".", with: "") } ?? "")
                    .font(.cond(11, .medium)).tracking(1.5).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 112, height: 112)
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
