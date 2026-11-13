import Combine
import CoreLocation
import MapKit
import SwiftUI

struct ManifestationsView: View {
    enum Vue: String, CaseIterable, Identifiable {
        case liste, carte, calendrier
        var id: String { rawValue }
        var titre: String {
            switch self {
            case .liste: "Liste"
            case .carte: "Carte"
            case .calendrier: "Calendrier"
            }
        }
    }

    @Environment(AuthModel.self) private var auth
    @Environment(FiltresStore.self) private var store
    @Environment(CartesStore.self) private var cartes
    @AppStorage("hideFloatingTabBar") private var hideFloatingTabBar = false
    private let afficherSelecteurVue: Bool
    private let afficherRecherche: Bool
    @State private var vueSelectionnee: Vue = .liste
    @State private var departementIDs: Set<Int> = []
    @State private var sportCodes: Set<String> = []
    @State private var filtresInitialises = false
    @State private var recherche = ""
    @FocusState private var rechercheFocus: Bool
    @State private var manifestations: [Manifestation] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var panneauOuvert = false
    @State private var inscritIDs: Set<Int> = []
    // pagination : le site n'accepte qu'un sport à la fois, on suit donc la page suivante de chaque sport encore non épuisé
    @State private var prochainePage = 1
    @State private var sportsRestants: [String?] = [nil]
    @State private var chargementSuite = false
    @State private var generation = 0
    @State private var pointCarteSelectionneID: String?
    @State private var moisCourant = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Calendar.current.startOfDay(for: Date())
    @State private var jourSelectionne = Calendar.current.startOfDay(for: Date())
    @State private var positionCarte: MapCameraPosition = .region(Self.regionFrance)
    @State private var carteCentreeSurMoi = false
    @StateObject private var localisation = LocalisationCourses()
    @State private var trajetApercu: Trajet?
    @State private var trajetApercuEnCours = false
    @State private var erreurTrajetApercu: String?
    @State private var trajetApercuManifestationID: Int?
    @State private var jourPopupCalendrier: Date?
    @State private var positionsSemaines: [PositionSemaine] = []
    @State private var hauteurViewportCalendrier: CGFloat = 0
    @State private var prechargementCalendrierEnCours = false
    @State private var filtreStatut: FiltreStatut = .tous

    private struct Requete: Equatable {
        var departementIDs: Set<Int>
        var sportCodes: Set<String>
        var recherche: String
    }

    private enum FiltreStatut: String, CaseIterable, Identifiable {
        case tous
        case inscrit
        var id: String { rawValue }
    }

    private var estCartePleinEcran: Bool { !afficherSelecteurVue && vueSelectionnee == .carte }
    private var estCalendrierPleinEcran: Bool { !afficherSelecteurVue && vueSelectionnee == .calendrier }
    private var nombreFiltres: Int { (departementIDs.isEmpty ? 0 : 1) + (sportCodes.isEmpty ? 0 : 1) }
    private var titrePage: String {
        if afficherSelecteurVue { return "Manifestations" }
        switch vueSelectionnee {
        case .liste: return "Courses"
        case .carte: return "Carte"
        case .calendrier: return "Calendrier"
        }
    }

    init(vueInitiale: Vue = .liste, afficherSelecteurVue: Bool = true, afficherRecherche: Bool = true) {
        self.afficherSelecteurVue = afficherSelecteurVue
        self.afficherRecherche = afficherRecherche
        _vueSelectionnee = State(initialValue: vueInitiale)
    }

    var body: some View {
        Group {
            if estCartePleinEcran {
                vueCarte
            } else if estCalendrierPleinEcran {
                vueCalendrier
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if vueSelectionnee == .liste && !afficherSelecteurVue {
                            enteteCoursesRecherche
                        } else {
                            Text(titrePage).pageTitle()

                            HStack(spacing: 10) {
                                if afficherRecherche {
                                    HStack(spacing: 10) {
                                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                                        TextField("", text: $recherche, prompt: Text("Nom de la manifestation").foregroundStyle(Theme.muted))
                                            .font(.barlow(15)).foregroundStyle(Theme.text)
                                            .autocorrectionDisabled()
                                    }
                                    .padding(.horizontal, 14).frame(height: 48)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
                                } else {
                                    Spacer(minLength: 0)
                                }
                                boutonFiltres
                            }
                        }

                        if nombreFiltres > 0 && vueSelectionnee != .carte && vueSelectionnee != .calendrier {
                            FlowPills {
                                if !sportCodes.isEmpty { Pill(text: store.resumeSports(sportCodes), fg: Theme.accent, bg: Theme.accent.opacity(0.13)) }
                                if !departementIDs.isEmpty { Pill(text: "Dép. " + store.resumeDepartements(departementIDs), fg: Theme.accent, bg: Theme.accent.opacity(0.13)) }
                            }
                        }

                        if afficherSelecteurVue {
                            Picker("Vue", selection: $vueSelectionnee) {
                                ForEach(Vue.allCases) { vue in
                                    Text(vue.titre).tag(vue)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 2)
                        }

                        contenuSelectionne

                        if vueSelectionnee == .liste && !sportsRestants.isEmpty && !manifestations.isEmpty && errorMessage == nil {
                            ProgressView().tint(Theme.accent)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .onAppear { Task { await chargerSuite() } }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 120)
                    .containerRelativeFrame(.horizontal)
                }
            }
        }
        .overlay { overlayEtat }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $panneauOuvert) {
            FiltresPanel(departements: $departementIDs, sports: $sportCodes)
        }
        .refreshable { await load() }
        // retour d'une fiche : l'inscription a pu changer
        .onAppear {
            Task { await chargerInscriptions() }
            // filtres par défaut du profil, appliqués une fois à l'ouverture
            if !filtresInitialises { departementIDs = store.departementsParDefaut; sportCodes = store.sportsParDefaut; filtresInitialises = true }
        }
        // un changement dans le profil écrase la sélection courante
        .onChange(of: store.departementsParDefaut) { _, nouveaux in
            majDepartementsParDefaut(nouveaux)
        }
        .onChange(of: store.sportsParDefaut) { _, nouveaux in
            majSportsParDefaut(nouveaux)
        }
        .onChange(of: vueSelectionnee) { _, nouvelleVue in
            majVueSelectionnee(nouvelleVue)
        }
        .onChange(of: panneauOuvert) { _, _ in
            majVisibiliteTabBar()
        }
        .onChange(of: pointCarteSelectionneID) { _, _ in
            majVisibiliteTabBar()
        }
        .onChange(of: jourPopupCalendrier) { _, _ in
            majVisibiliteTabBar()
        }
        .task(id: vueSelectionnee) {
            if vueSelectionnee == .calendrier {
                await prechargerCalendrierSiNecessaire(jusqua: moisCourant)
            }
        }
        .task(id: moisCourant) {
            if vueSelectionnee == .calendrier {
                await prechargerCalendrierSiNecessaire(jusqua: moisCourant)
            }
        }
        .onChange(of: manifestationIDs) { _, _ in
            majManifestations()
        }
        .onReceive(localisation.$position) { position in
            majPositionUtilisateur(position)
        }
        .task(id: Requete(departementIDs: departementIDs, sportCodes: sportCodes, recherche: recherche)) {
            // petit debounce pour la saisie ; annulé si le filtre change
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            await load()
        }
        .onAppear { majVisibiliteTabBar() }
        .onDisappear { hideFloatingTabBar = false }
    }

    private var boutonFiltres: some View {
        let afficherEtatActif = !estCartePleinEcran && !estCalendrierPleinEcran
        return Button { panneauOuvert = true } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(afficherEtatActif && nombreFiltres > 0 ? Theme.accent : Theme.text)
                .frame(width: 48, height: 48)
                .background(afficherEtatActif && nombreFiltres > 0 ? Theme.accent.opacity(0.13) : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(afficherEtatActif && nombreFiltres > 0 ? Theme.accent : Theme.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if afficherEtatActif && nombreFiltres > 0 {
                        Text("\(nombreFiltres)").font(.cond(13)).foregroundStyle(Theme.bg)
                            .frame(minWidth: 20, minHeight: 20).background(Theme.accent, in: Capsule())
                            .offset(x: 7, y: -7)
                    }
                }
        }
        .accessibilityLabel("Filtres, \(nombreFiltres) actif(s)")
    }

    @ViewBuilder
    private var contenuSelectionne: some View {
        switch vueSelectionnee {
        case .liste:
            vueListe
        case .carte:
            vueCarte
        case .calendrier:
            vueCalendrier
        }
    }

    @ViewBuilder
    private var overlayEtat: some View {
        if isLoading && manifestations.isEmpty {
            ProgressView().tint(Theme.accent)
        } else if let errorMessage {
            ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if !isLoading && manifestations.isEmpty {
            ContentUnavailableView("Aucune manifestation", systemImage: "flag.slash",
                                   description: Text(nombreFiltres > 0 ? "Essayez de retirer un filtre." : ""))
        }
    }

    private var resumeCartes: String {
        var morceaux: [String] = []
        for carte in cartes.cartesActives {
            let niveau = carte.niveau?
                .replacingOccurrences(of: "ème catégorie", with: "e")
                .replacingOccurrences(of: "ère catégorie", with: "re")
            let age = carte.categorieAge?.split(separator: " ").last.map(String.init)
            let detail = niveau ?? age
            morceaux.append([carte.discipline, detail].compactMap { $0 }.joined(separator: " "))
        }
        return morceaux.joined(separator: " · ")
    }

    private var enteteCoursesRecherche: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(Theme.accent.opacity(0.9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Courses").pageTitle()
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 6, height: 6)
                        Text("Saison UFOLEP \(saisonCourses)")
                            .font(.barlow(12, .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Image(systemName: "bell")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textSoft)
                    .frame(width: 40, height: 40)
                    .background(Theme.surface2, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            .padding(.top, -4)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("", text: $recherche, prompt: Text("Nom de la manifestation").foregroundStyle(Theme.muted))
                        .focused($rechercheFocus)
                        .font(.barlow(15))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                    if !recherche.isEmpty {
                        Button {
                            recherche = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.faint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(rechercheFocus ? Theme.accent : Theme.line, lineWidth: rechercheFocus ? 2 : 1)
                )
                boutonFiltres
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chipStatut(.tous, texte: "Tous", icone: nil, couleur: Theme.text, fond: Theme.text, texteCouleur: Theme.bg)
                    chipStatut(.inscrit, texte: "Inscrit (\(inscritIDs.count))", icone: "checkmark.circle.fill", couleur: Theme.accent, fond: Theme.accent.opacity(0.12), texteCouleur: Theme.accent)
                }
                .padding(.horizontal, 1)
            }
        }
    }

    private var vueListe: some View {
        let source = switch filtreStatut {
        case .tous: manifestations
        case .inscrit: manifestations.filter { inscritIDs.contains($0.id) }
        }
        let pourMoi = source.filter(cartes.correspond)
        let autres = source.filter { !cartes.correspond($0) }
        return Group {
            if !pourMoi.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("POUR MOI", color: Theme.accent)
                    Spacer()
                    Text(resumeCartes).font(.barlow(13)).foregroundStyle(Theme.muted)
                }
                ForEach(pourMoi) { ligne($0) }
            }
            if !autres.isEmpty {
                Eyebrow(pourMoi.isEmpty ? "\(source.count) manifestation(s)" : "Autres (\(autres.count))")
                    .padding(.top, 4)
                ForEach(autres) { ligne($0) }
            }
            if source.isEmpty {
                Text(filtreStatut == .inscrit ? "Aucune course inscrite avec les filtres actifs." : "Aucune course trouvée avec les filtres actifs.")
                    .font(.barlow(14))
                    .foregroundStyle(Theme.muted)
                    .card(padding: 14)
            }
        }
    }

    private var pointsCarte: [PointCarte] {
        PointCarte.regrouper(manifestations.compactMap { m in
            guard let c = m.adresse?.coordinate else { return nil }
            return PointCarte.Element(manifestation: m, latitude: c.latitude, longitude: c.longitude)
        })
    }

    private var manifestationIDs: [Int] {
        manifestations.map(\.id)
    }

    private var pointSelectionne: PointCarte? {
        guard let pointCarteSelectionneID else { return nil }
        return pointsCarte.first { $0.id == pointCarteSelectionneID }
    }

    private var pointsCarteIDs: [String] {
        pointsCarte.map(\.id)
    }

    private var vueCarte: some View {
        Group {
            if estCartePleinEcran {
                ZStack(alignment: .top) {
                    Map(position: $positionCarte) {
                        pointsCarteAnnotations
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)

                    HStack {
                        Text(titrePage).pageTitle()
                        Spacer()
                        boutonFiltresCarte
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            boutonControleCarte(systemImage: "location.fill", label: "Me recentrer") {
                                guard let position = localisation.position else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    positionCarte = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 24_000, longitudinalMeters: 24_000))
                                }
                            }
                            boutonControleCarte(systemImage: "safari", label: "Nord") {
                                guard let position = localisation.position else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    positionCarte = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 70_000, longitudinalMeters: 70_000))
                                }
                            }
                            boutonControleCarte(systemImage: "square.stack.3d.up", label: "Style de carte") {
                                // Placeholder visuel aligné avec Stitch ; style déjà géré par MapKit.
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 130)
                }
                .safeAreaInset(edge: .bottom) {
                    if let pointSelectionne {
                        popupCarte(pointSelectionne)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("Plans · Données UFOLEP")
                        .font(.barlow(10))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                        .padding(.leading, 12)
                        .padding(.bottom, 8)
                }
                .onAppear {
                    localisation.demarrer()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Eyebrow("AUTOUR DE MOI", color: Theme.accent)
                        Spacer()
                        if localisation.position != nil {
                            Text("Position détectée").font(.barlow(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    Map(position: $positionCarte) {
                        pointsCarteAnnotations
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1) }
                    .onAppear {
                        localisation.demarrer()
                        if pointCarteSelectionneID == nil { pointCarteSelectionneID = pointsCarte.first?.id }
                    }
                    if let pointSelectionne {
                        apercu(pointSelectionne)
                    } else {
                        Text("Touchez un marqueur pour afficher un aperçu.")
                            .font(.barlow(13))
                            .foregroundStyle(Theme.muted)
                            .card(padding: 14)
                    }
                }
            }
        }
        .onChange(of: pointsCarteIDs) { _, ids in
            if ids.contains(pointCarteSelectionneID ?? "") { return }
            pointCarteSelectionneID = estCartePleinEcran ? nil : ids.first
        }
        .task(id: pointCarteSelectionneID) {
            await majTrajetApercu()
        }
    }

    @MapContentBuilder
    private var pointsCarteAnnotations: some MapContent {
        ForEach(pointsCarte) { point in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                Button {
                    pointCarteSelectionneID = point.id
                } label: {
                    if point.manifestations.count == 1 {
                        VStack(spacing: 4) {
                            if let date = point.manifestations.first?.debutDate {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                                    Text(Date.fr("d MMM").string(from: date).capitalized)
                                        .font(.barlow(10, .semibold))
                                        .foregroundStyle(Theme.text)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.surface, in: Capsule())
                            }
                            ZStack {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: pointCarteSelectionneID == point.id ? 46 : 36, height: pointCarteSelectionneID == point.id ? 46 : 36)
                                Image(systemName: "bicycle")
                                    .font(.system(size: pointCarteSelectionneID == point.id ? 18 : 15, weight: .bold))
                                    .foregroundStyle(Theme.bg)
                            }
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                    } else {
                        ZStack {
                            Circle().fill(Theme.accent).frame(width: 34, height: 34)
                            Text("\(point.manifestations.count)")
                                .font(.cond(14, .semibold))
                                .foregroundStyle(Theme.bg)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        if localisation.position != nil { UserAnnotation() }
    }

    private var boutonFiltresCarte: some View {
        Button { panneauOuvert = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if nombreFiltres > 0 {
                        Text("\(nombreFiltres)")
                            .font(.barlow(10, .semibold))
                            .foregroundStyle(Theme.bg)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filtres, \(nombreFiltres) actif(s)")
    }

    private func boutonControleCarte(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSoft)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func popupCarte(_ point: PointCarte) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(point.manifestations.count == 1 ? "APERÇU" : "\(point.manifestations.count) COURSES PROCHES")
                    .font(.cond(14, .semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    pointCarteSelectionneID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if point.manifestations.count == 1, let manifestation = point.manifestations.first {
                Text(manifestation.libelle).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                Text([manifestation.adresse?.commune?.capitalized, manifestation.modele?.libelle].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(14)).foregroundStyle(Theme.muted)
                trajetApercuLigne(manifestation)
                NavigationLink {
                    ManifestationDetailView(manifestation: manifestation)
                } label: {
                    Label("Ouvrir la fiche", systemImage: "arrow.right.circle.fill")
                        .font(.cond(16, .semibold)).tracking(1.2).textCase(.uppercase)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(OutlineButtonStyle())
            } else {
                ForEach(Array(point.manifestations.prefix(4))) { manifestation in
                    NavigationLink {
                        ManifestationDetailView(manifestation: manifestation)
                    } label: {
                        HStack(spacing: 10) {
                            DateBlock(date: manifestation.debutDate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manifestation.libelle).font(.cond(15, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                                Text(manifestation.adresse?.commune?.capitalized ?? "Lieu inconnu").font(.barlow(12)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if point.manifestations.count > 4 {
                    Text("… et \(point.manifestations.count - 4) autre(s)").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func apercu(_ point: PointCarte) -> some View {
        if point.manifestations.count == 1, let manifestation = point.manifestations.first {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("APERÇU")
                Text(manifestation.libelle).font(.cond(20, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                Text([manifestation.adresse?.commune?.capitalized, manifestation.modele?.libelle].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(13)).foregroundStyle(Theme.muted)
                trajetApercuLigne(manifestation)
                NavigationLink {
                    ManifestationDetailView(manifestation: manifestation)
                } label: {
                    Label("Ouvrir la fiche", systemImage: "arrow.right.circle.fill")
                        .font(.cond(15, .semibold)).tracking(1.2).textCase(.uppercase)
                }
                .buttonStyle(OutlineButtonStyle())
            }
            .card(radius: 20, padding: 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("\(point.manifestations.count) COURSES PROCHES")
                ForEach(Array(point.manifestations.prefix(5))) { manifestation in
                    NavigationLink {
                        ManifestationDetailView(manifestation: manifestation)
                    } label: {
                        HStack(spacing: 10) {
                            DateBlock(date: manifestation.debutDate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manifestation.libelle).font(.cond(15, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                                Text(manifestation.adresse?.commune?.capitalized ?? "Lieu inconnu").font(.barlow(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if point.manifestations.count > 5 {
                    Text("… et \(point.manifestations.count - 5) autre(s)").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
            }
            .card(radius: 20, padding: 14)
        }
    }

    @ViewBuilder
    private func trajetApercuLigne(_ manifestation: Manifestation) -> some View {
        if trajetApercuManifestationID == manifestation.id, let trajetApercu {
            Label(trajetApercu.texte, systemImage: "car.fill")
                .font(.barlow(13, .semibold))
                .foregroundStyle(Theme.accent)
        } else if trajetApercuManifestationID == manifestation.id, trajetApercuEnCours {
            ProgressView().controlSize(.small)
        } else if trajetApercuManifestationID == manifestation.id, let erreurTrajetApercu {
            Text(erreurTrajetApercu).font(.barlow(12)).foregroundStyle(Theme.danger)
        } else if trajetApercuManifestationID == manifestation.id, TrajetService.nonDemande, manifestation.adresse?.coordinate != nil {
            Button {
                Task { await calculerTrajetApercu(manifestation) }
            } label: {
                Label("Afficher le temps de trajet", systemImage: "car.fill")
                    .font(.barlow(13, .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    private var vueCalendrier: some View {
        Group {
            if estCalendrierPleinEcran {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(titrePage).pageTitle()
                            Spacer()
                            boutonAujourdhui {
                                let aujourdHui = Calendar.current.startOfDay(for: Date())
                                let mois = Self.debutDuMois(aujourdHui)
                                jourSelectionne = aujourdHui
                                moisCourant = mois
                                jourPopupCalendrier = nil
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    proxy.scrollTo(cleMois(mois), anchor: .top)
                                }
                            }
                            boutonFiltres
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                        Text(Self.formatMoisLongAnnee.string(from: moisCourant).capitalized)
                            .font(.cond(42))
                            .textCase(.none)
                            .foregroundStyle(Theme.text)
                            .padding(.horizontal, 12)
                            .padding(.top, 2)

                        HStack {
                            ForEach(Array(Self.joursSemaine.enumerated()), id: \.offset) { _, jour in
                                Text(jour).font(.cond(13, .semibold)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 6)

                        GeometryReader { container in
                            ScrollView(.vertical) {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(moisCalendrier, id: \.self) { mois in
                                        VStack(alignment: .leading, spacing: 0) {
                                            let lignes = lignesDuMois(mois)
                                            if mois != moisCalendrier.first {
                                                miniEnteteMois(
                                                    nom: Self.formatMoisLong.string(from: mois).capitalized,
                                                    colonne: colonneDebutMois(mois)
                                                )
                                            }
                                            ForEach(Array(lignes.enumerated()), id: \.offset) { _, ligne in
                                                let reference = mois
                                                semaineLigne(cases: ligne)
                                                    .background {
                                                        GeometryReader { geo in
                                                            let frame = geo.frame(in: .named("calendar-scroll"))
                                                            Color.clear.preference(
                                                                key: PositionSemainePreferenceKey.self,
                                                                value: [PositionSemaine(date: reference, minY: frame.minY, maxY: frame.maxY)]
                                                            )
                                                        }
                                                    }
                                            }
                                        }
                                        .id(cleMois(mois))
                                    }
                                }
                            }
                            .padding(.horizontal, 8)
                            .padding(.bottom, 24)
                            .coordinateSpace(name: "calendar-scroll")
                            .onAppear {
                                hauteurViewportCalendrier = container.size.height
                            }
                            .onChange(of: container.size.height) { _, nv in
                                hauteurViewportCalendrier = nv
                            }
                            .onPreferenceChange(PositionSemainePreferenceKey.self) { positions in
                                positionsSemaines = positions
                                mettreAJourMoisVisibleDepuisScroll()
                            }
                        }
                    }
                    .onAppear {
                        moisCourant = Self.debutDuMois(jourSelectionne)
                        let mois = Self.debutDuMois(Date())
                        DispatchQueue.main.async {
                            proxy.scrollTo(cleMois(mois), anchor: .top)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let jourPopupCalendrier {
                        popupCalendrier(jourPopupCalendrier)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        IconButton(systemImage: "chevron.left", label: "Mois précédent") {
                            if let precedent = Calendar.current.date(byAdding: .month, value: -1, to: moisCourant) {
                                moisCourant = Self.debutDuMois(precedent)
                                ajusterJourSelectionneAuMois()
                            }
                        }
                        Spacer(minLength: 0)
                        Text(Self.formatMois.string(from: moisCourant)).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        IconButton(systemImage: "chevron.right", label: "Mois suivant") {
                            if let suivant = Calendar.current.date(byAdding: .month, value: 1, to: moisCourant) {
                                moisCourant = Self.debutDuMois(suivant)
                                ajusterJourSelectionneAuMois()
                            }
                        }
                    }
                    .padding(.bottom, 2)

                    grilleCalendrier

                    let courses = manifestationsDuJour(jourSelectionne)
                    Eyebrow("COURSES DU \(Self.formatJourLong.string(from: jourSelectionne).uppercased())",
                            color: courses.isEmpty ? Theme.muted : Theme.accent)
                    if courses.isEmpty {
                        Text("Aucune course ce jour-là avec les filtres actifs.")
                            .font(.barlow(14))
                            .foregroundStyle(Theme.muted)
                            .card(padding: 14)
                    } else {
                        ForEach(courses) { manifestation in
                            ligne(manifestation)
                        }
                    }
                }
            }
        }
        .onAppear { ajusterJourSelectionneAuMois() }
    }

    private var moisCalendrier: [Date] {
        let cal = Calendar.current
        let ancre = Self.debutDuMois(Date())
        return (-18...18).compactMap { decalage in
            cal.date(byAdding: .month, value: decalage, to: ancre).map(Self.debutDuMois)
        }
    }

    private func lignesDuMois(_ mois: Date) -> [[Date?]] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: mois),
              let joursDansMois = cal.range(of: .day, in: .month, for: interval.start) else { return [] }
        let prefix = colonneDebutMois(interval.start)
        let total = prefix + joursDansMois.count
        let lignes = Int(ceil(Double(total) / 7.0))
        var resultat: [[Date?]] = []
        for ligne in 0..<lignes {
            var cases: [Date?] = []
            for colonne in 0..<7 {
                let index = ligne * 7 + colonne
                let numeroJour = index - prefix + 1
                if numeroJour >= 1 && numeroJour <= joursDansMois.count,
                   let date = cal.date(byAdding: .day, value: numeroJour - 1, to: interval.start) {
                    cases.append(date)
                } else {
                    cases.append(nil)
                }
            }
            resultat.append(cases)
        }
        return resultat
    }

    private func colonneDebutMois(_ date: Date) -> Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        return (weekday + 5) % 7 // lundi = 0
    }

    private func semaineLigne(cases: [Date?]) -> some View {
        let cal = Calendar.current
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                if let date = cases[index] {
                    let nbCourses = manifestationsDuJour(date).count
                    let selection = cal.isDate(date, inSameDayAs: jourSelectionne)
                    let estAujourdHui = cal.isDateInToday(date)
                    Button {
                        let jour = cal.startOfDay(for: date)
                        jourSelectionne = jour
                        moisCourant = Self.debutDuMois(jour)
                        jourPopupCalendrier = jour
                    } label: {
                        VStack(spacing: 6) {
                            Text("\(cal.component(.day, from: date))")
                                .font(.cond(34, .semibold))
                                .foregroundStyle(selection ? Theme.bg : (estAujourdHui ? Theme.accent : Theme.text))
                                .frame(width: 56, height: 56)
                                .background(selection ? Theme.accent : .clear, in: Circle())
                            HStack(spacing: 3) {
                                if nbCourses > 0 {
                                    ForEach(0..<min(nbCourses, 3), id: \.self) { _ in
                                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                                            .fill(Theme.accent)
                                            .frame(width: 16, height: 4)
                                    }
                                } else {
                                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                                        .fill(Color.clear)
                                        .frame(width: 16, height: 4)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 84)
                    }
                    .buttonStyle(.plain)
                } else {
                    VStack(spacing: 6) {
                        Text(" ").font(.cond(34, .semibold)).frame(width: 56, height: 56)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.clear)
                            .frame(width: 16, height: 4)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                }
            }
        }
        .padding(.vertical, 4)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private func miniEnteteMois(nom: String, colonne: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                ZStack(alignment: .leading) {
                    if index == colonne {
                        Text(nom)
                            .font(.cond(20, .semibold))
                            .textCase(.none)
                            .foregroundStyle(Theme.text)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(height: 30)
        .padding(.horizontal, 8)
        .padding(.top, 2)
    }

    private func boutonAujourdhui(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Aujourd’hui")
                .font(.cond(14, .semibold))
                .textCase(.none)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 10)
                .frame(height: 36)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func cleMois(_ date: Date) -> String {
        let cal = Calendar.current
        let debut = Self.debutDuMois(date)
        let annee = cal.component(.year, from: debut)
        let mois = cal.component(.month, from: debut)
        return String(format: "%04d-%02d", annee, mois)
    }

    private func popupCalendrier(_ jour: Date) -> some View {
        let courses = manifestationsDuJour(jour)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Self.formatJourLong.string(from: jour).capitalized)
                    .font(.cond(18, .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button {
                    jourPopupCalendrier = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if courses.isEmpty {
                Text("Aucune course ce jour-là avec les filtres actifs.")
                    .font(.barlow(14))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(Array(courses.prefix(4))) { manifestation in
                    NavigationLink {
                        ManifestationDetailView(manifestation: manifestation)
                    } label: {
                        HStack(spacing: 10) {
                            DateBlock(date: manifestation.debutDate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(manifestation.libelle).font(.cond(15, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                                Text([manifestation.adresse?.commune?.capitalized, manifestation.modele?.libelle].compactMap { $0 }.joined(separator: " · "))
                                    .font(.barlow(12))
                                    .foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if courses.count > 4 {
                    Text("… et \(courses.count - 4) autre(s)").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func mettreAJourMoisVisibleDepuisScroll() {
        guard estCalendrierPleinEcran, !positionsSemaines.isEmpty, hauteurViewportCalendrier > 0 else { return }
        let cal = Calendar.current
        let visibles = positionsSemaines.filter { $0.maxY > 0 && $0.minY < hauteurViewportCalendrier }
        guard !visibles.isEmpty else { return }
        let ligneRepere = visibles
            .filter { $0.maxY > 0 }
            .min(by: { abs($0.minY) < abs($1.minY) }) ?? visibles[0]
        let moisVisible = Self.debutDuMois(ligneRepere.date)
        if !cal.isDate(moisVisible, equalTo: moisCourant, toGranularity: .month) {
            moisCourant = moisVisible
        }
    }

    private var grilleCalendrier: some View {
        VStack(spacing: 8) {
            let joursSemaine = ["L", "M", "M", "J", "V", "S", "D"]
            HStack {
                ForEach(Array(joursSemaine.enumerated()), id: \.offset) { _, jour in
                    Text(jour).font(.cond(12, .semibold)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }
            }
            let cases = casesCalendrier()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(cases.indices, id: \.self) { index in
                    if let date = cases[index] {
                        let courses = manifestationsDuJour(date)
                        let selection = Calendar.current.isDate(date, inSameDayAs: jourSelectionne)
                        Button {
                            jourSelectionne = Calendar.current.startOfDay(for: date)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.cond(16, .semibold))
                                    .foregroundStyle(selection ? Theme.bg : Theme.text)
                                Circle()
                                    .fill(courses.isEmpty ? Color.clear : (selection ? Theme.bg : Theme.accent))
                                    .frame(width: 6, height: 6)
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(selection ? Theme.accent : Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selection ? Theme.accent : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .card(radius: 20, padding: 14)
    }

    private func ajusterJourSelectionneAuMois() {
        if Calendar.current.isDate(jourSelectionne, equalTo: moisCourant, toGranularity: .month) { return }
        jourSelectionne = moisCourant
    }

    private func casesCalendrier() -> [Date?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: moisCourant) else { return [] }
        let premier = interval.start
        let jours = cal.range(of: .day, in: .month, for: premier)?.count ?? 0
        let semaine = cal.component(.weekday, from: premier)
        let prefix = (semaine + 5) % 7 // lundi = 0
        var resultat = Array<Date?>(repeating: nil, count: prefix)
        for day in 0..<jours {
            if let date = cal.date(byAdding: .day, value: day, to: premier) {
                resultat.append(date)
            }
        }
        while resultat.count % 7 != 0 { resultat.append(nil) }
        return resultat
    }

    private func manifestationsDuJour(_ date: Date) -> [Manifestation] {
        let cal = Calendar.current
        return manifestations
            .filter { $0.debutDate.map { cal.isDate($0, inSameDayAs: date) } ?? false }
            .sorted { ($0.debutDate ?? .distantFuture, $0.id) < ($1.debutDate ?? .distantFuture, $1.id) }
    }

    private var dateMaxManifestations: Date? {
        manifestations.compactMap(\.debutDate).max()
    }

    private func prechargerCalendrierSiNecessaire(jusqua mois: Date) async {
        guard vueSelectionnee == .calendrier else { return }
        guard !prechargementCalendrierEnCours else { return }
        guard !sportsRestants.isEmpty else { return }
        prechargementCalendrierEnCours = true
        defer { prechargementCalendrierEnCours = false }
        let cal = Calendar.current
        let moisCible = Self.debutDuMois(mois)
        let finCible = (cal.date(byAdding: DateComponents(month: 1, day: -1), to: moisCible) ?? moisCible)
        let seuil = cal.date(byAdding: .month, value: 1, to: finCible) ?? finCible
        var tentatives = 0
        while !sportsRestants.isEmpty && (dateMaxManifestations == nil || (dateMaxManifestations ?? .distantPast) < seuil) {
            if tentatives >= 14 { break }
            tentatives += 1
            await chargerSuite()
            if errorMessage != nil { break }
        }
    }

    private func majDepartementsParDefaut(_ nouveaux: Set<Int>) {
        departementIDs = nouveaux
    }

    private func majSportsParDefaut(_ nouveaux: Set<String>) {
        sportCodes = nouveaux
    }

    private func majVisibiliteTabBar() {
        let popupCarteOuverte = pointCarteSelectionneID != nil && estCartePleinEcran
        let popupCalendrierOuverte = jourPopupCalendrier != nil && estCalendrierPleinEcran
        hideFloatingTabBar = panneauOuvert || popupCarteOuverte || popupCalendrierOuverte
    }

    private func majVueSelectionnee(_ nouvelleVue: Vue) {
        if nouvelleVue == .carte {
            localisation.demarrer()
        }
    }

    private func majManifestations() {
        if !manifestationsDuJour(jourSelectionne).isEmpty { return }
        if let premierJour = premierJourManifestations() {
            jourSelectionne = premierJour
            moisCourant = Self.debutDuMois(premierJour)
        }
    }

    private func majPositionUtilisateur(_ position: CLLocation?) {
        guard vueSelectionnee == .carte, !carteCentreeSurMoi, let position else { return }
        positionCarte = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 70_000, longitudinalMeters: 70_000))
        carteCentreeSurMoi = true
    }

    private func premierJourManifestations() -> Date? {
        for manifestation in manifestations {
            if let date = manifestation.debutDate {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    private func majTrajetApercu() async {
        guard let point = pointSelectionne, point.manifestations.count == 1, let manifestation = point.manifestations.first else {
            trajetApercu = nil
            trajetApercuEnCours = false
            erreurTrajetApercu = nil
            trajetApercuManifestationID = nil
            return
        }
        trajetApercuManifestationID = manifestation.id
        guard TrajetService.autorise else {
            trajetApercu = nil
            trajetApercuEnCours = false
            erreurTrajetApercu = nil
            return
        }
        await calculerTrajetApercu(manifestation)
    }

    private func calculerTrajetApercu(_ manifestation: Manifestation) async {
        guard let c = manifestation.adresse?.coordinate else { return }
        if trajetApercuEnCours { return }
        trajetApercuManifestationID = manifestation.id
        trajetApercuEnCours = true
        defer { trajetApercuEnCours = false }
        do {
            trajetApercu = try await TrajetService.trajet(versLatitude: c.latitude, longitude: c.longitude)
            erreurTrajetApercu = nil
        } catch {
            trajetApercu = nil
            erreurTrajetApercu = error.localizedDescription
        }
    }

    private func chipStatut(_ statut: FiltreStatut, texte: String, icone: String?, couleur: Color, fond: Color, texteCouleur: Color) -> some View {
        Button {
            filtreStatut = statut
        } label: {
            HStack(spacing: 5) {
                if let icone {
                    Image(systemName: icone).font(.system(size: 12, weight: .semibold))
                }
                Text(texte).font(.barlow(12, .semibold))
            }
            .foregroundStyle(filtreStatut == statut ? texteCouleur : couleur)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(filtreStatut == statut ? fond : fond.opacity(0.75))
            )
            .overlay(
                Capsule()
                    .stroke(filtreStatut == statut ? fond.opacity(0.45) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var saisonCourses: String {
        let annee = Calendar.current.component(.year, from: Date())
        return "\(annee)-\(annee + 1)"
    }

    private func ligne(_ m: Manifestation) -> some View {
        NavigationLink {
            ManifestationDetailView(manifestation: m)
        } label: {
            CourseListRow(
                manifestation: m,
                inscrit: inscritIDs.contains(m.id)
            )
        }
        .buttonStyle(.plain)
    }

    /// Département du lieu d'après le code postal (« 59 » pour 59000, « 971 » pour 97100) ; vrai si inconnu.
    private static func dansDepartements(_ m: Manifestation, _ numeros: Set<String>) -> Bool {
        guard let cp = m.adresse?.codePostalFr, cp.count == 5, cp.allSatisfy(\.isNumber) else { return true }
        let outreMer = cp.hasPrefix("97") || cp.hasPrefix("98")
        return numeros.contains(String(cp.prefix(outreMer ? 3 : 2).drop { $0 == "0" }))
    }

    /// Courses où tu es déjà inscrit (badge dans la liste).
    private func chargerInscriptions() async {
        if let inscriptions = try? await auth.withSession({ try await auth.client.fetchInscriptions() }) {
            inscritIDs = Set(inscriptions.map(\.manifestationID))
        }
    }

    private func load() async {
        generation += 1
        isLoading = true
        errorMessage = nil
        prochainePage = 1
        sportsRestants = sportCodes.isEmpty ? [nil] : sportCodes.sorted()
        chargementSuite = false
        defer { isLoading = false }
        do {
            await chargerInscriptions()
            let nouvelles = try await pageSuivante()
            manifestations = nouvelles
            // filtre par département très sélectif : on continue jusqu'à avoir quelque chose à afficher
            if manifestations.isEmpty { await chargerSuite() }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Charge la page suivante quand la fin de la liste devient visible.
    private func chargerSuite() async {
        guard !chargementSuite, !isLoading || manifestations.isEmpty, !sportsRestants.isEmpty else { return }
        chargementSuite = true
        let courante = generation
        defer { if courante == generation { chargementSuite = false } }
        do {
            var ajoutees: [Manifestation] = []
            while ajoutees.isEmpty && !sportsRestants.isEmpty {
                ajoutees = try await pageSuivante()
                guard courante == generation else { return }
            }
            guard courante == generation else { return }
            fusionner(ajoutees)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            if courante == generation { errorMessage = error.localizedDescription }
        }
    }

    /// Récupère la page suivante de chaque sport restant, et met à jour la progression.
    private func pageSuivante() async throws -> [Manifestation] {
        let page = prochainePage
        let sports = sportsRestants
        let client = auth.client, libelle = recherche, structures = departementIDs.sorted()
        let reponses: [(String?, [Manifestation], Bool)] = try await auth.withSession {
            try await withThrowingTaskGroup(of: (String?, [Manifestation], Bool).self) { groupe in
                for sport in sports {
                    groupe.addTask {
                        let r = try await client.manifestationsPage(page: page, libelle: libelle, structureIDs: structures, discipline: sport)
                        return (sport, r.manifestations, r.suite)
                    }
                }
                var tout: [(String?, [Manifestation], Bool)] = []
                for try await r in groupe { tout.append(r) }
                return tout
            }
        }
        prochainePage = page + 1
        sportsRestants = sports.filter { sport in reponses.first { $0.0 == sport }?.2 ?? false }
        let trouvees = reponses.flatMap(\.1)
        // le site filtre sur la structure organisatrice : on garde seulement celles dont le lieu est dans le département
        let numeros = Set(store.departements.filter { departementIDs.contains($0.id) }.map(\.numero))
        return numeros.isEmpty ? trouvees : trouvees.filter { Self.dansDepartements($0, numeros) }
    }

    private func fusionner(_ nouvelles: [Manifestation]) {
        var parID = Dictionary(manifestations.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for m in nouvelles { parID[m.id] = m }
        manifestations = parID.values.sorted { ($0.debutDate ?? .distantFuture, $0.id) < ($1.debutDate ?? .distantFuture, $1.id) }
    }

    private static let formatMois: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let formatJourLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private static let formatMoisLongAnnee: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let formatMoisLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM"
        return f
    }()

    private static let joursSemaine = ["L", "M", "M", "J", "V", "S", "D"]

    private static let regionFrance = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.7, longitude: 2.3),
        span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 9.5)
    )

    private nonisolated static func debutDuMois(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? Calendar.current.startOfDay(for: date)
    }

    private struct PositionSemaine: Equatable {
        let date: Date
        let minY: CGFloat
        let maxY: CGFloat
    }

    private struct PositionSemainePreferenceKey: PreferenceKey {
        static var defaultValue: [PositionSemaine] = []
        static func reduce(value: inout [PositionSemaine], nextValue: () -> [PositionSemaine]) {
            value.append(contentsOf: nextValue())
        }
    }

    private func debutSemaine(_ date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let ecart = (weekday + 5) % 7 // lundi = 0
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -ecart, to: date) ?? date)
    }
}

private struct CourseListRow: View {
    let manifestation: Manifestation
    let inscrit: Bool

    private static let heureFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var heure: String? {
        guard let brut = manifestation.dateDebutHoraire?.trimmingCharacters(in: .whitespacesAndNewlines),
              !brut.isEmpty else { return nil }
        if brut.contains(":") { return brut }
        if let d = Date.fr("HH:mm:ss").date(from: brut) { return Self.heureFormatter.string(from: d) }
        if let d = Date.fr("HH:mm").date(from: brut) { return Self.heureFormatter.string(from: d) }
        return nil
    }

    var body: some View {
        HStack(spacing: 14) {
            DateAndTime(date: manifestation.debutDate, heure: heure, highlighted: inscrit)

            VStack(alignment: .leading, spacing: 6) {
                Text(manifestation.libelle)
                    .font(.barlow(17, .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text([manifestation.adresse?.commune?.capitalized, manifestation.modele?.libelle].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(13))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if inscrit {
                    Label("Inscrit", systemImage: "checkmark.seal.fill")
                        .font(.barlow(12, .semibold))
                        .foregroundStyle(Theme.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
            }
            Spacer()
            Image(systemName: inscrit ? "checkmark.circle.fill" : "chevron.right")
                .font(.system(size: inscrit ? 22 : 14, weight: .semibold))
                .foregroundStyle(inscrit ? Theme.accent : Theme.faint)
        }
        .card(border: inscrit ? Theme.accent.opacity(0.35) : Theme.line, radius: 24, padding: 12)
    }
}

private struct PointCarte: Identifiable {
    struct Element {
        let manifestation: Manifestation
        let latitude: Double
        let longitude: Double
    }

    let id: String
    let latitude: Double
    let longitude: Double
    let manifestations: [Manifestation]

    static func regrouper(_ elements: [Element], rayonKm: Double = 5) -> [PointCarte] {
        struct Groupe {
            var latitude: Double
            var longitude: Double
            var elements: [Element]
        }
        var groupes: [Groupe] = []
        for element in elements {
            if let index = groupes.firstIndex(where: { distanceKm(lat1: $0.latitude, lon1: $0.longitude, lat2: element.latitude, lon2: element.longitude) <= rayonKm }) {
                var groupe = groupes[index]
                groupe.elements.append(element)
                let n = Double(groupe.elements.count)
                groupe.latitude = ((groupe.latitude * (n - 1)) + element.latitude) / n
                groupe.longitude = ((groupe.longitude * (n - 1)) + element.longitude) / n
                groupes[index] = groupe
            } else {
                groupes.append(Groupe(latitude: element.latitude, longitude: element.longitude, elements: [element]))
            }
        }
        return groupes.map { groupe in
            let ids = groupe.elements.map { String($0.manifestation.id) }.sorted().joined(separator: "-")
            let manifestations = groupe.elements.map(\.manifestation).sorted { ($0.debutDate ?? .distantFuture, $0.id) < ($1.debutDate ?? .distantFuture, $1.id) }
            return PointCarte(id: ids, latitude: groupe.latitude, longitude: groupe.longitude, manifestations: manifestations)
        }
    }

    private static func distanceKm(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371.0
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

private final class LocalisationCourses: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var position: CLLocation?
    private let manager = CLLocationManager()
    private var demarre = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func demarrer() {
        guard !demarre else { return }
        demarre = true
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            return
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        default:
            return
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        position = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
