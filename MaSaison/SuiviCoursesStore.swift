import Foundation
import Observation
import SwiftUI
import UserNotifications

/// État d'une manifestation pour l'utilisateur. Progression : aucun ⇄ envie → inscrit → validé.
enum EtatCourse {
    /// Ni envie ni inscription.
    case aucun
    /// Dans la liste d'envies (« bucket list »), choix local à l'appareil.
    case envie
    /// Inscrit sur le site, paiement pas encore validé.
    case inscrit
    /// Inscription payée (ou gratuite) : plus rien à faire.
    case valide

    /// L'envie ne se règle à la main que tant qu'on n'est pas inscrit.
    var envieModifiable: Bool { self == .aucun || self == .envie }
}

/// Suivi des manifestations : envies mémorisées sur l'appareil, inscriptions et paiements lus sur le site.
@Observable
final class SuiviCoursesStore {
    private static let cleEnvies = "enviesManifestations"
    private static let cleEcheances = "echeancesManifestations"

    /// Nom et clôture des inscriptions d'une manifestation suivie, pour les rappels.
    struct Echeance: Codable {
        let libelle: String
        let cloture: Date
        /// Optionnelle : absente des échéances mémorisées avant l'ajout du rappel d'ouverture.
        var ouverture: Date?
    }
    /// Échéances des manifestations en envie ou inscrites (mémorisées : les rappels se reprogramment sans réseau).
    private var echeances: [Int: Echeance]
    private(set) var envies: Set<Int>
    /// Inscrit, paiement en attente (commande à payer ou inscription en cours de saisie).
    private(set) var inscrits: Set<Int> = []
    /// Inscription validée par le paiement.
    private(set) var valides: Set<Int> = []

    init() {
        envies = Set(UserDefaults.standard.array(forKey: Self.cleEnvies) as? [Int] ?? [])
        echeances = UserDefaults.standard.data(forKey: Self.cleEcheances)
            .flatMap { try? JSONDecoder().decode([Int: Echeance].self, from: $0) } ?? [:]
    }

    func etat(_ manifestation: Int) -> EtatCourse {
        if valides.contains(manifestation) { return .valide }
        if inscrits.contains(manifestation) { return .inscrit }
        if envies.contains(manifestation) { return .envie }
        return .aucun
    }

    func basculerEnvie(_ manifestation: Manifestation) {
        guard etat(manifestation.id).envieModifiable else { return }
        if envies.remove(manifestation.id) == nil { envies.insert(manifestation.id) }
        enregistrerEnvies()
        memoriser([manifestation])
    }

    /// Note la clôture des manifestations suivies parmi celles affichées, puis reprogramme les rappels si besoin.
    func memoriser(_ manifestations: [Manifestation]) {
        var change = false
        for m in manifestations where envies.contains(m.id) || inscrits.contains(m.id) {
            guard let cloture = m.clotureInscriptions else { continue }
            let ouverture = m.ouvertureInscriptions
            if echeances[m.id]?.cloture == cloture && echeances[m.id]?.ouverture == ouverture { continue }
            echeances[m.id] = Echeance(libelle: m.libelle, cloture: cloture, ouverture: ouverture)
            change = true
        }
        if change { enregistrerEcheances() }
        Task { await reprogrammerRappels() }
    }

    /// Relit inscriptions et commandes à payer ; garde l'état précédent si le site ne répond pas.
    func actualiser(_ auth: AuthModel) async {
        guard let inscriptions = try? await auth.withSession({ try await auth.client.fetchInscriptions() }) else { return }
        let commandes = (try? await auth.withSession { try await auth.client.fetchCommandes() }) ?? []
        var enAttente = Set<Int>(), payees = Set<Int>()
        for i in inscriptions {
            let enSaisie = i.epreuves.contains { $0.statut.lowercased().contains("saisie") }
            // même rapprochement que InscriptionBloc : la commande porte le nom de la manifestation
            let aPayer = commandes.contains { $0.libelle.localizedCaseInsensitiveContains(i.libelle) }
            if enSaisie || aPayer { enAttente.insert(i.manifestationID) } else { payees.insert(i.manifestationID) }
        }
        inscrits = enAttente
        valides = payees
        // une fois inscrit, l'envie est réalisée : elle quitte la liste
        let realisees = envies.intersection(enAttente.union(payees))
        if !realisees.isEmpty {
            envies.subtract(realisees)
            enregistrerEnvies()
        }
        // inscriptions en attente dont on ignore la clôture : on va la chercher
        let inconnues = inscriptions.filter { enAttente.contains($0.manifestationID) && echeances[$0.manifestationID] == nil }
        var trouvees: [Manifestation] = []
        for i in inconnues {
            if let m = try? await auth.withSession({ try await auth.client.fetchManifestation(id: i.manifestationID, libelle: i.libelle) }) {
                trouvees.append(m)
            }
        }
        memoriser(trouvees)
    }

    // MARK: rappels de clôture

    private static let prefixeRappel = "cloture-"

    /// Envie aux inscriptions pas encore ouvertes : à l'heure d'ouverture.
    /// Le jour de clôture, à 9 h puis à 20 h, pour chaque course en envie ou inscrite non payée.
    /// Tout est recalculé à chaque appel : une course validée ou retirée perd ses rappels.
    func reprogrammerRappels() async {
        let centre = UNUserNotificationCenter.current()
        let anciens = await centre.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefixeRappel) }
        centre.removePendingNotificationRequests(withIdentifiers: anciens)

        // on ne garde que les échéances encore utiles
        let suivis = envies.union(inscrits)
        let avant = echeances.count
        echeances = echeances.filter { suivis.contains($0.key) && $0.value.cloture > Date() }
        if echeances.count != avant { enregistrerEcheances() }

        let demandes = echeances.flatMap { id, e in rappels(id: id, echeance: e) }
        guard !demandes.isEmpty, await autoriserNotifications(centre) else { return }
        for demande in demandes { try? await centre.add(demande) }
    }

    private func rappels(id: Int, echeance e: Echeance) -> [UNNotificationRequest] {
        var paris = Calendar(identifier: .gregorian)
        paris.timeZone = TimeZone(identifier: "Europe/Paris")!
        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let inscrit = inscrits.contains(id)
        let limite = e.cloture.formatted(heure)
        var demandes: [UNNotificationRequest] = []
        if !inscrit, let ouverture = e.ouverture, ouverture > Date(), ouverture < e.cloture {
            let contenu = UNMutableNotificationContent()
            contenu.title = "Inscriptions ouvertes"
            contenu.body = "\(e.libelle) est dans tes envies : tu peux t'inscrire jusqu'au \(e.cloture.formatted(.dateTime.day(.twoDigits).month(.twoDigits).year().locale(Locale(identifier: "fr_FR")))) à \(limite)."
            contenu.sound = .default
            let declencheur = UNCalendarNotificationTrigger(
                dateMatching: paris.dateComponents(in: paris.timeZone, from: ouverture).filtrees, repeats: false)
            demandes.append(UNNotificationRequest(identifier: "\(Self.prefixeRappel)\(id)-ouverture", content: contenu, trigger: declencheur))
        }
        return demandes + [9, 20].compactMap { h -> UNNotificationRequest? in
            // inutile après la clôture ou déjà passé
            guard let quand = paris.date(bySettingHour: h, minute: 0, second: 0, of: e.cloture),
                  quand < e.cloture, quand > Date() else { return nil }
            let contenu = UNMutableNotificationContent()
            contenu.title = h == 9 ? "Clôture des inscriptions aujourd'hui" : "Dernier rappel : clôture ce soir"
            contenu.body = inscrit
                ? "\(e.libelle) : ton inscription n'est pas encore payée. Clôture à \(limite)."
                : "\(e.libelle) est dans tes envies. Inscris-toi avant \(limite)."
            contenu.sound = .default
            let declencheur = UNCalendarNotificationTrigger(
                dateMatching: paris.dateComponents(in: paris.timeZone, from: quand).filtrees, repeats: false)
            return UNNotificationRequest(identifier: "\(Self.prefixeRappel)\(id)-\(h)", content: contenu, trigger: declencheur)
        }
    }

    /// Demande l'autorisation la première fois qu'il y a un rappel à programmer.
    private func autoriserNotifications(_ centre: UNUserNotificationCenter) async -> Bool {
        switch await centre.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: return true
        case .notDetermined: return (try? await centre.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        default: return false
        }
    }

    private func enregistrerEcheances() {
        if let data = try? JSONEncoder().encode(echeances) { UserDefaults.standard.set(data, forKey: Self.cleEcheances) }
    }

    private func enregistrerEnvies() {
        UserDefaults.standard.set(Array(envies), forKey: Self.cleEnvies)
    }
}

/// Signet « liste d'envies » tant qu'on n'est pas inscrit, puis badge Inscrit / Validé.
struct BoutonEnvie: View {
    let manifestation: Manifestation
    var taille: CGFloat = 18
    @Environment(SuiviCoursesStore.self) private var suivi

    var body: some View {
        let manifestationID = manifestation.id
        let etat = suivi.etat(manifestationID)
        if etat.envieModifiable {
            let actif = etat == .envie
            Button {
                suivi.basculerEnvie(manifestation)
            } label: {
                Image(systemName: actif ? "bookmark.fill" : "bookmark")
                    .font(.system(size: taille, weight: .semibold))
                    .foregroundStyle(actif ? Theme.warning : Theme.faint)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .sensoryFeedback(.selection, trigger: actif)
            .accessibilityLabel(actif ? "Retirer de ma liste d'envies" : "Ajouter à ma liste d'envies")
        } else {
            EtatCourseBadge(etat: etat)
        }
    }
}

/// Pastille « Envie », « Inscrit · à payer » ou « Validé » ; rien pour `.aucun`.
struct EtatCourseBadge: View {
    let etat: EtatCourse

    var body: some View {
        if let (texte, icone, couleur) = apparence {
            Label(texte, systemImage: icone)
                .font(.barlow(12, .semibold))
                .foregroundStyle(couleur)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(couleur.opacity(0.12), in: Capsule())
        }
    }

    private var apparence: (String, String, Color)? {
        switch etat {
        case .aucun: nil
        case .envie: ("Envie", "bookmark.fill", Theme.warning)
        case .inscrit: ("Inscrit · à payer", "hourglass", Theme.secondary)
        case .valide: ("Validé", "checkmark.seal.fill", Theme.accent)
        }
    }
}

private extension DateComponents {
    /// Composantes utiles à un déclencheur calendaire (avec le fuseau), sans les champs qui le perturbent.
    var filtrees: DateComponents {
        DateComponents(timeZone: timeZone, year: year, month: month, day: day, hour: hour, minute: minute)
    }
}
