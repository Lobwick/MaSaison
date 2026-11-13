import Foundation
import Observation
import SwiftUI

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
    private(set) var envies: Set<Int>
    /// Inscrit, paiement en attente (commande à payer ou inscription en cours de saisie).
    private(set) var inscrits: Set<Int> = []
    /// Inscription validée par le paiement.
    private(set) var valides: Set<Int> = []

    init() {
        envies = Set(UserDefaults.standard.array(forKey: Self.cleEnvies) as? [Int] ?? [])
    }

    func etat(_ manifestation: Int) -> EtatCourse {
        if valides.contains(manifestation) { return .valide }
        if inscrits.contains(manifestation) { return .inscrit }
        if envies.contains(manifestation) { return .envie }
        return .aucun
    }

    func basculerEnvie(_ manifestation: Int) {
        guard etat(manifestation).envieModifiable else { return }
        if envies.remove(manifestation) == nil { envies.insert(manifestation) }
        enregistrerEnvies()
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
    }

    private func enregistrerEnvies() {
        UserDefaults.standard.set(Array(envies), forKey: Self.cleEnvies)
    }
}

/// Signet « liste d'envies » tant qu'on n'est pas inscrit, puis badge Inscrit / Validé.
struct BoutonEnvie: View {
    let manifestationID: Int
    var taille: CGFloat = 18
    @Environment(SuiviCoursesStore.self) private var suivi

    var body: some View {
        let etat = suivi.etat(manifestationID)
        if etat.envieModifiable {
            let actif = etat == .envie
            Button {
                suivi.basculerEnvie(manifestationID)
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
