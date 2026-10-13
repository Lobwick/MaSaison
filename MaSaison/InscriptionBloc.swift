import SwiftUI

/// Parcours d'inscription de bout en bout : vérification → une seule confirmation (tarif affiché) →
/// enregistrement → validation → page de paiement par carte dans l'app.
/// La carte bancaire est confirmée et saisie par l'utilisateur sur la page de la banque, jamais par l'app.
struct InscriptionBloc: View {
    @Environment(AuthModel.self) private var auth
    let manifestation: Manifestation
    let course: ConfigNiveau

    private enum Etat: Equatable { case repos, chargement, enregistree, validee, inscrit, erreur(String) }
    @State private var etat: Etat = .repos
    @State private var ticket: TicketInscription?
    @State private var confirmation = false
    @State private var commande: Commande?
    @State private var paiementOuvert = false
    @State private var progression = ""

    var body: some View {
        VStack(spacing: 10) {
            switch etat {
            case .inscrit:
                Label("Tu es inscrit", systemImage: "checkmark.seal.fill")
                    .font(.cond(17)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .validee:
                // inscription validée, il ne reste que le paiement
                Text("Inscription validée : il reste le paiement par carte bancaire.")
                    .font(.barlow(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Button { paiementOuvert = true } label: {
                    Label(commande.map { "Payer \(euros($0.montant))" } ?? "Payer", systemImage: "creditcard")
                }
                .buttonStyle(PrimaryButtonStyle())

            case .enregistree:
                // inscription enregistrée mais parcours interrompu : on le reprend
                Text("Ton inscription est enregistrée mais pas encore validée.")
                    .font(.barlow(13)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Button { Task { await validerEtPayer() } } label: { Label("Reprendre l'inscription", systemImage: "arrow.clockwise") }
                    .buttonStyle(PrimaryButtonStyle())

            case .chargement:
                VStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    if !progression.isEmpty { Text(progression).font(.barlow(13)).foregroundStyle(Theme.muted) }
                }
                .frame(maxWidth: .infinity, minHeight: 52)

            case .repos, .erreur:
                Button { Task { await preparer() } } label: { Label("S'inscrire", systemImage: "square.and.pencil") }
                    .buttonStyle(OutlineButtonStyle())
                if case .erreur(let message) = etat {
                    Text(message).font(.barlow(13)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                }
            }
        }
        .sheet(isPresented: $paiementOuvert, onDismiss: { Task { await etatInitial() } }) {
            PaiementWebView(url: UfolepClient.urlPaiement(commande))
        }
        .task { await etatInitial() }
        .confirmationDialog("S'inscrire et payer ?", isPresented: $confirmation, titleVisibility: .visible) {
            Button("Confirmer et payer \(euros(ticket?.total))") { Task { await inscrireEtPayer() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("\(manifestation.libelle) · \(course.niveau.libelle)\nTarif : \(euros(ticket?.total)). Ton inscription sera enregistrée et validée, puis tu passeras au paiement par carte bancaire.")
        }
    }

    private func euros(_ montant: Double?) -> String {
        guard let montant else { return "—" }
        return montant.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
    }

    // MARK: parcours

    /// Demande au site ce qui est permis pour toi, puis le ticket (tarif). Rien n'est enregistré à ce stade.
    private func preparer() async {
        etat = .chargement
        progression = "Vérification de ton inscription…"
        do {
            ticket = try await auth.withSession {
                let personne = try await auth.client.fetchPersonneID()
                let detail = try await auth.client.fetchDetailPersonne(manifestationID: manifestation.id, personneID: personne)
                guard let statut = detail.niveaux.first(where: { $0.niveau.id == course.niveau.id }) else {
                    throw UfolepError.refuse(["Cette course n'est pas proposée pour ton profil."])
                }
                guard statut.inscriptible else { throw UfolepError.refuse(statut.erreurs.isEmpty ? ["Inscription impossible."] : statut.erreurs) }
                if !(detail.documentsDemandes ?? []).isEmpty {
                    throw UfolepError.refuse(["Des documents sont demandés : termine l'inscription sur le site."])
                }
                return try await auth.client.calculerTicket(manifestationID: manifestation.id, personneID: personne, niveauID: course.niveau.id)
            }
            etat = .repos
            confirmation = true
        } catch {
            etat = .erreur(error.localizedDescription)
        }
    }

    /// Après la confirmation : enregistre, valide, puis ouvre le paiement.
    private func inscrireEtPayer() async {
        guard let ticket else { return }
        etat = .chargement
        progression = "Enregistrement de l'inscription…"
        do {
            try await auth.withSession { try await auth.client.enregistrer(ticketID: ticket.id, final: false) }
        } catch {
            etat = .erreur(error.localizedDescription)
            return
        }
        await validerEtPayer()
    }

    /// Valide définitivement l'inscription (elle devient « à payer »), puis ouvre la page de paiement.
    private func validerEtPayer() async {
        etat = .chargement
        progression = "Validation de l'inscription…"
        do {
            let validation = try await auth.withSession { try await auth.client.calculerTicketUnique(manifestationID: manifestation.id) }
            try await auth.withSession { try await auth.client.enregistrerInscriptionUnique(manifestationID: manifestation.id, ticketID: validation.id) }
        } catch {
            // l'inscription est enregistrée : on propose de reprendre là où ça s'est arrêté
            etat = .enregistree
            progression = ""
            return
        }
        progression = "Préparation du paiement…"
        let commandes = (try? await auth.withSession { try await auth.client.fetchCommandes() }) ?? []
        commande = commandes.first { $0.libelle.localizedCaseInsensitiveContains(manifestation.libelle) }
        if commande != nil {
            etat = .validee
            paiementOuvert = true
        } else {
            etat = .inscrit   // gratuit : rien à payer
        }
    }

    /// Reprend là où tu t'étais arrêté : à payer, inscrit, enregistré non validé, ou rien.
    private func etatInitial() async {
        guard etat == .repos || etat == .validee || etat == .enregistree || etat == .inscrit else { return }
        let commandes = (try? await auth.withSession { try await auth.client.fetchCommandes() }) ?? []
        if let trouvee = commandes.first(where: { $0.libelle.localizedCaseInsensitiveContains(manifestation.libelle) }) {
            commande = trouvee
            etat = .validee
            return
        }
        commande = nil
        // pas de commande à payer : on regarde si le site te compte déjà parmi les inscrits
        let inscriptions = (try? await auth.withSession { try await auth.client.fetchInscriptions() }) ?? []
        if let mienne = inscriptions.first(where: { $0.manifestationID == manifestation.id }) {
            let statut = (mienne.epreuves.first?.statut ?? "").lowercased()
            etat = statut.contains("saisie") ? .enregistree : .inscrit
        } else if ((try? await auth.withSession { try await auth.client.inscriptionsEnCoursDeSaisie(manifestationID: manifestation.id) }) ?? 0) > 0 {
            etat = .enregistree
        } else {
            etat = .repos
        }
    }
}
