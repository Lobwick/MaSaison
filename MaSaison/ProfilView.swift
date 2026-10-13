import SwiftUI
import TipKit

struct ProfilView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(FiltresStore.self) private var store
    @Environment(CartesStore.self) private var cartes
    @AppStorage("boutonAgenda") private var boutonAgenda = true
    @AppStorage("echauffementMinutes") private var echauffement = 60
    @State private var profil: Profil?
    @State private var anciennesOuvert = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                entete

                section("MES CARTES") {
                    if cartes.cartes.isEmpty {
                        Text("Aucune carte trouvée.").font(.barlow(14)).foregroundStyle(Theme.muted).card()
                    }
                    ForEach(cartes.cartesActives) { CarteRow(carte: $0) }
                    if !anciennesCartes.isEmpty { anciennesCartesBloc }
                }

                section("RECHERCHE DE MANIFESTATIONS") {
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

                section("AGENDA") {
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

                section("À PROPOS") {
                    MentionNonOfficielle().card()
                }

                Button("Se déconnecter") { auth.logout() }
                    .buttonStyle(PrimaryButtonStyle(danger: true))
            }
            .padding(.horizontal, 20).padding(.top, 24).padding(.bottom, 24)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .task { profil = try? await auth.withSession { try await auth.client.fetchProfil() } }
        .onAppear { AppTips.accueil.invalidate(reason: .actionPerformed) }
    }

    // MARK: en-tête

    private var entete: some View {
        HStack(spacing: 16) {
            Text(initiales).font(.cond(30)).foregroundStyle(Theme.text)
                .frame(width: 76, height: 76).background(Theme.surface2, in: Circle())
                .overlay(Circle().stroke(Theme.accent, lineWidth: 3))
            VStack(alignment: .leading, spacing: 4) {
                Text(nomAffiche).font(.cond(34)).textCase(.uppercase).foregroundStyle(Theme.text).lineLimit(2)
                if let carte = cartes.cartesActives.first {
                    Text([carte.comite, carte.club].filter { !$0.isEmpty }.joined(separator: " · ")).font(.barlow(14)).foregroundStyle(Theme.muted)
                }
            }
        }
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
