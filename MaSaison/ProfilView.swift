import SwiftUI
import TipKit

struct ProfilView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(FiltresStore.self) private var store
    @Environment(CartesStore.self) private var cartes
    @AppStorage("boutonAgenda") private var boutonAgenda = true
    @AppStorage("echauffementMinutes") private var echauffement = 60
    @State private var profil: Profil?
    @State private var photo: UIImage?
    @State private var anciennesOuvert = false
    @State private var carteSelectionnee = 0

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 22) {
                entete

                section("MES CARTES") { mesCartesSection }

                section("RÉGLAGES ET PRÉFÉRENCES") { reglagesSection }

                section("À PROPOS") {
                    MentionNonOfficielle().card()
                }

                Button("Se déconnecter") { auth.logout() }
                    .buttonStyle(PrimaryButtonStyle(danger: true))
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            profil = try? await auth.withSession { try await auth.client.fetchProfil() }
            // la photo du site demande la session du licencié ; sans photo, on garde les initiales
            if let url = profil?.photoURL,
               let data = try? await auth.withSession({ try await auth.client.download(url) }) {
                photo = UIImage(data: data)
            }
        }
        .onAppear { AppTips.accueil.invalidate(reason: .actionPerformed) }
    }

    // MARK: en-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("PROFIL")
                    .font(.cond(34))
                    .foregroundStyle(Theme.text)
                Spacer()
                TopRightProfileActions(photo: photo, accent: Theme.accent)
            }
            HStack(spacing: 16) {
                Group {
                    if let photo {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .accessibilityLabel("Photo de profil")
                    } else {
                        Text(initiales).font(.cond(30)).foregroundStyle(Theme.text)
                    }
                }
                .frame(width: 76, height: 76).background(Theme.surface2).clipShape(Circle())
                .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
                VStack(alignment: .leading, spacing: 4) {
                    Text(nomAffiche).font(.cond(34)).textCase(.uppercase).foregroundStyle(Theme.text).lineLimit(2)
                    if let carte = cartes.cartesActives.first {
                        Text([carte.comite, carte.club].filter { !$0.isEmpty }.joined(separator: " · ")).font(.barlow(14)).foregroundStyle(Theme.muted)
                    }
                }
                Spacer(minLength: 8)
            }
        }
        .padding(.top, -4)
    }

    /// « Monsieur MOULIN Felix » → « MOULIN Felix »
    private var jetons: [String] {
        (profil?.nom ?? "").split(separator: " ").map(String.init).filter { !["monsieur", "madame", "mademoiselle", "m.", "mme", "mlle"].contains($0.lowercased()) }
    }
    private var nomAffiche: String { jetons.isEmpty ? "Mon profil" : jetons.joined(separator: " ") }
    private var initiales: String {
        guard jetons.count >= 2 else { return String(jetons.first?.prefix(1) ?? "?") }
        return (String(jetons[1].prefix(1)) + String(jetons[0].prefix(1))).uppercased()
    }

    // MARK: anciennes cartes

    private var anciennesCartes: [Carte] { cartes.cartes.filter { !$0.estActive } }

    private var anciennesCartesBloc: some View {
        VStack(spacing: 0) {
            Button { withAnimation { anciennesOuvert.toggle() } } label: {
                HStack {
                    Text("Anciennes cartes").font(.cond(17, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.text)
                    Text("(\(anciennesCartes.count))").font(.cond(17, .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(anciennesOuvert ? 180 : 0))
                }
                .padding(18)
            }
            .buttonStyle(.plain)
            if anciennesOuvert {
                VStack(spacing: 8) { ForEach(anciennesCartes) { CarteRow(carte: $0) } }
                    .padding(.horizontal, 10).padding(.bottom, 12)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: briques

    private func section<Content: View>(_ titre: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(titre)
            content()
        }
    }

    private var mesCartesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle().fill(Theme.accent).frame(width: 6, height: 6)
                Text("\(cartesActives.count) actives")
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Text(etiquetteSaison)
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Theme.accent.opacity(0.1), in: Capsule())
            }

            if cartesActives.isEmpty {
                Text("Aucune carte trouvée.").font(.barlow(14)).foregroundStyle(Theme.muted).card()
            } else {
                TabView(selection: $carteSelectionnee) {
                    ForEach(Array(cartesActives.enumerated()), id: \.offset) { index, carte in
                        LicenceWalletCard(carte: carte)
                            .padding(.horizontal, 2)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 238)

                HStack {
                    HStack(spacing: 6) {
                        ForEach(cartesActives.indices, id: \.self) { index in
                            Capsule()
                                .fill(index == carteSelectionnee ? Theme.accent : Theme.faint.opacity(0.5))
                                .frame(width: index == carteSelectionnee ? 20 : 6, height: 6)
                        }
                    }
                    Spacer()
                    Label("Balayer pour changer de licence", systemImage: "hand.draw")
                        .font(.barlow(11))
                        .foregroundStyle(Theme.muted)
                }

                Button {
                    // Aligné avec la maquette : CTA présent, comportement déjà géré dans le détail de manifestation.
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

            if !anciennesCartes.isEmpty { anciennesCartesBloc }
        }
    }

    private var reglagesSection: some View {
        VStack(spacing: 0) {
            NavigationLink {
                ReglagesManifestationsView()
            } label: {
                ReglageLinkRow(
                    icone: "slider.horizontal.3",
                    iconeCouleur: Theme.accent,
                    titre: "Filtres de manifestation",
                    sousTitre: resumeManifestations
                )
            }
            .buttonStyle(.plain)

            Divider().overlay(Theme.line)

            NavigationLink {
                ReglagesAgendaView()
            } label: {
                ReglageLinkRow(
                    icone: "calendar",
                    iconeCouleur: Theme.secondary,
                    titre: "Synchronisation Agenda",
                    sousTitre: resumeAgenda,
                    sousTitreCouleur: Theme.accent
                )
            }
            .buttonStyle(.plain)
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func dureeTexte(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    private var resumeManifestations: String {
        let sports = store.resumeSports(store.sportsParDefaut)
        let deps = store.resumeDepartements(store.departementsParDefaut)
        return "\(sports) • Dép. \(deps)"
    }

    private var resumeAgenda: String {
        guard boutonAgenda else { return "Inactif" }
        return "Actif (+\(dureeTexte(echauffement)) échauffement)"
    }

    private var cartesActives: [Carte] { cartes.cartesActives }

    private var etiquetteSaison: String {
        guard let saison = cartesActives.first?.saison, !saison.isEmpty else { return "Saison" }
        return "Saison \(saison)"
    }
}

private struct ReglageLinkRow: View {
    let icone: String
    let iconeCouleur: Color
    let titre: String
    let sousTitre: String
    var sousTitreCouleur: Color = Theme.muted

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icone)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(iconeCouleur)
                .frame(width: 36, height: 36)
                .background(iconeCouleur.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(titre)
                    .font(.barlow(20, .semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.leading)
                Text(sousTitre)
                    .font(.barlow(14, .semibold))
                    .foregroundStyle(sousTitreCouleur)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.faint)
        }
        .padding(16)
    }
}

private struct LicenceWalletCard: View {
    let carte: Carte

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
                    Text(carte.discipline.uppercased()).font(.cond(22, .semibold)).foregroundStyle(Color.white)
                    Text(carte.saison).font(.cond(22, .semibold)).foregroundStyle(Color(hex: 0x85F8C4))
                }
                Text(carte.niveau ?? "Licence Compétition Nationale")
                    .font(.barlow(11))
                    .foregroundStyle(Color.white.opacity(0.75))

                FlowPills {
                    if let niveau = carte.niveau {
                        Pill(text: niveau, systemImage: "medal.fill", fg: Color(hex: 0x85F8C4), bg: Color.white.opacity(0.1))
                    }
                    if let age = carte.categorieAge {
                        Pill(text: age, systemImage: "person.fill", fg: Color.white.opacity(0.9), bg: Color.white.opacity(0.1))
                    }
                }

                Divider().overlay(Color.white.opacity(0.12))
                HStack {
                    Label("Expire le \(carte.expireLe)", systemImage: "calendar")
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

private struct ReglagesManifestationsView: View {
    @Environment(FiltresStore.self) private var store
    @Environment(CartesStore.self) private var cartes

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("RÉGLAGES MANIFESTATIONS")
                AstuceView(tip: AppTips.profil)
                filtreRow("Sport par défaut", valeur: store.resumeSports(store.sportsParDefaut), actif: !store.sportsParDefaut.isEmpty,
                          modifier: MultiSelectView.sports(store.sports, selection: $store.sportsParDefaut),
                          supprimer: { store.sportsParDefaut = [] })
                filtreRow("Départements par défaut", valeur: store.resumeDepartements(store.departementsParDefaut), actif: !store.departementsParDefaut.isEmpty,
                          modifier: MultiSelectView.departements(store.departements, selection: $store.departementsParDefaut),
                          supprimer: { store.departementsParDefaut = [] })
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        store.retablir(cartes: cartes.cartes)
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

    private func filtreRow<Destination: View>(_ titre: String, valeur: String, actif: Bool, modifier: Destination, supprimer: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(titre).font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                Spacer()
                Text(valeur).font(.cond(20)).foregroundStyle(actif ? Theme.accent : Theme.muted).multilineTextAlignment(.trailing)
            }
            HStack(spacing: 10) {
                NavigationLink { modifier } label: {
                    Label("Modifier", systemImage: "pencil").font(.cond(14)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                Button(action: supprimer) {
                    Label("Supprimer", systemImage: "trash").font(.cond(14)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.danger)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color(hex: 0x4A2229), lineWidth: 1))
                }
                .disabled(!actif).opacity(actif ? 1 : 0.4)
            }
        }
        .card(padding: 16)
    }
}

private struct ReglagesAgendaView: View {
    @AppStorage("boutonAgenda") private var boutonAgenda = true
    @AppStorage("echauffementMinutes") private var echauffement = 60

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("RÉGLAGES AGENDA")
                VStack(spacing: 0) {
                    HStack {
                        Text("Bouton « Ajouter à l'agenda »").font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                        Spacer()
                        Toggle("", isOn: $boutonAgenda).labelsHidden().tint(Theme.accent)
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
                            pas("minus", "Réduire l'échauffement") { echauffement = max(0, echauffement - 5) }
                            Text(dureeTexte(echauffement)).font(.cond(26)).foregroundStyle(Theme.text).frame(minWidth: 64)
                            pas("plus", "Augmenter l'échauffement") { echauffement = min(240, echauffement + 5) }
                        }
                    }
                    .padding(16)
                    .disabled(!boutonAgenda).opacity(boutonAgenda ? 1 : 0.4)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
                Text("Exemple : appel à 13:45, échauffement à \(exemple). Ce créneau est ajouté à l'agenda.")
                    .font(.barlow(12)).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20).padding(.vertical, 24)
        }
        .screenBackground()
        .navigationTitle("Agenda")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func pas(_ icone: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icone).font(.system(size: 16, weight: .bold)).foregroundStyle(Theme.text)
                .frame(width: 44, height: 44).background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .accessibilityLabel(label)
    }

    private func dureeTexte(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    private var exemple: String {
        let total = 13 * 60 + 45 - echauffement
        return String(format: "%02d:%02d", max(0, total) / 60, max(0, total) % 60)
    }
}

private struct CarteRow: View {
    let carte: Carte

    var body: some View {
        if carte.estActive {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(carte.discipline).textCase(.uppercase).foregroundStyle(Theme.text)
                        Text(carte.saison).foregroundStyle(Theme.muted)
                    }
                    .font(.cond(28))
                    Spacer()
                    StatusTag(text: carte.statut)
                }
                FlowPills {
                    if let n = carte.niveau { Pill(text: n, fg: Theme.accent, bg: Theme.accent.opacity(0.13)) }
                    if let a = carte.categorieAge { Pill(text: a) }
                }
                Text("Expire le \(carte.expireLe)").font(.barlow(13)).foregroundStyle(Theme.muted)
            }
            .card(border: Theme.accent, radius: 24, padding: 18)
        } else {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(carte.discipline) \(carte.saison)").font(.cond(20)).textCase(.uppercase).foregroundStyle(Theme.text)
                    Text("\(carte.niveau ?? carte.categorieAge ?? "") · expirée le \(carte.expireLe)").font(.barlow(13)).foregroundStyle(Theme.muted)
                }
                Spacer()
                StatusTag(text: "Expirée", plein: false)
            }
            .card(radius: 24, padding: 14)
            .opacity(0.6)
        }
    }
}
