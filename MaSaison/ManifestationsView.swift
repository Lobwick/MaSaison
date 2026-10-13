import SwiftUI

struct ManifestationsView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(FiltresStore.self) private var store
    @Environment(CartesStore.self) private var cartes
    @State private var departementIDs: Set<Int> = []
    @State private var sportCodes: Set<String> = []
    @State private var filtresInitialises = false
    @State private var recherche = ""
    @State private var manifestations: [Manifestation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var panneauOuvert = false
    @State private var inscritIDs: Set<Int> = []

    private struct Requete: Equatable {
        var departementIDs: Set<Int>
        var sportCodes: Set<String>
        var recherche: String
    }

    private var nombreFiltres: Int { (departementIDs.isEmpty ? 0 : 1) + (sportCodes.isEmpty ? 0 : 1) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                Text("Manifestations").pageTitle()

                HStack(spacing: 10) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                        TextField("", text: $recherche, prompt: Text("Nom de la manifestation").foregroundStyle(Theme.muted))
                            .font(.barlow(15)).foregroundStyle(Theme.text)
                            .autocorrectionDisabled()
                    }
                    .padding(.horizontal, 14).frame(height: 48)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))

                    Button { panneauOuvert = true } label: {
                        Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(nombreFiltres > 0 ? Theme.accent : Theme.text)
                            .frame(width: 48, height: 48)
                            .background(nombreFiltres > 0 ? Theme.accent.opacity(0.13) : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(nombreFiltres > 0 ? Theme.accent : Theme.line, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                if nombreFiltres > 0 {
                                    Text("\(nombreFiltres)").font(.cond(13)).foregroundStyle(Theme.bg)
                                        .frame(minWidth: 20, minHeight: 20).background(Theme.accent, in: Capsule())
                                        .offset(x: 7, y: -7)
                                }
                            }
                    }
                    .accessibilityLabel("Filtres, \(nombreFiltres) actif(s)")
                }

                AstuceView(tip: AppTips.manifestations)

                if nombreFiltres > 0 {
                    FlowPills {
                        if !sportCodes.isEmpty { Pill(text: store.resumeSports(sportCodes), fg: Theme.accent, bg: Theme.accent.opacity(0.13)) }
                        if !departementIDs.isEmpty { Pill(text: "Dép. " + store.resumeDepartements(departementIDs), fg: Theme.accent, bg: Theme.accent.opacity(0.13)) }
                    }
                }

                let pourMoi = manifestations.filter(cartes.correspond)
                let autres = manifestations.filter { !cartes.correspond($0) }
                if !pourMoi.isEmpty {
                    HStack(alignment: .firstTextBaseline) {
                        Eyebrow("POUR MOI", color: Theme.accent)
                        Spacer()
                        Text(resumeCartes).font(.barlow(13)).foregroundStyle(Theme.muted)
                    }
                    ForEach(pourMoi) { ligne($0) }
                }
                if !autres.isEmpty {
                    Eyebrow(pourMoi.isEmpty ? "\(manifestations.count) manifestation(s)" : "Autres (\(autres.count))")
                        .padding(.top, 4)
                    ForEach(autres) { ligne($0) }
                }
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
        }
        .overlay {
            if isLoading && manifestations.isEmpty { ProgressView().tint(Theme.accent) }
            else if let errorMessage {
                ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
            } else if !isLoading && manifestations.isEmpty {
                ContentUnavailableView("Aucune manifestation", systemImage: "flag.slash",
                                       description: Text(nombreFiltres > 0 ? "Essayez de retirer un filtre." : ""))
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $panneauOuvert) {
            FiltresPanel(departements: $departementIDs, sports: $sportCodes)
        }
        .refreshable { await load() }
        .onAppear {
            // filtres par défaut du profil, appliqués une fois à l'ouverture
            if !filtresInitialises { departementIDs = store.departementsParDefaut; sportCodes = store.sportsParDefaut; filtresInitialises = true }
        }
        // un changement dans le profil écrase la sélection courante
        .onChange(of: store.departementsParDefaut) { _, nouveaux in departementIDs = nouveaux }
        .onChange(of: store.sportsParDefaut) { _, nouveaux in sportCodes = nouveaux }
        .task(id: Requete(departementIDs: departementIDs, sportCodes: sportCodes, recherche: recherche)) {
            // petit debounce pour la saisie ; annulé si le filtre change
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load()
        }
    }

    private var resumeCartes: String {
        cartes.cartesActives.map { c in [c.discipline, c.niveau.map { $0.replacingOccurrences(of: "ème catégorie", with: "e").replacingOccurrences(of: "ère catégorie", with: "re") } ?? c.categorieAge?.split(separator: " ").last.map(String.init)].compactMap { $0 }.joined(separator: " ") }.joined(separator: " · ")
    }

    private func ligne(_ m: Manifestation) -> some View {
        NavigationLink {
            ManifestationDetailView(manifestation: m)
        } label: {
            RowCard(date: m.debutDate, title: m.libelle,
                    subtitle: [m.adresse?.commune?.capitalized, m.modele?.libelle].compactMap { $0 }.joined(separator: " · "),
                    inscrit: inscritIDs.contains(m.id))
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            // courses où tu es déjà inscrit (icône dans la liste)
            inscritIDs = Set(((try? await auth.withSession { try await auth.client.fetchInscriptions() }) ?? []).map(\.manifestationID))
            manifestations = try await auth.withSession {
                try await auth.client.searchManifestations(libelle: recherche, structureIDs: departementIDs.sorted(), disciplineCodes: sportCodes.sorted())
            }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
