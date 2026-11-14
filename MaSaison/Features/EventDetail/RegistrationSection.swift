import SwiftUI

/// End-to-end registration flow: check → a single confirmation (price shown) →
/// save → validation → in-app card payment page.
/// The bank card is confirmed and entered by the user on the bank's page, never by the app.
struct RegistrationSection: View {
    @Environment(AuthModel.self) private var auth
    @Environment(RaceTrackingStore.self) private var tracking
    let event: Event
    let race: Race

    private enum Phase: Equatable { case idle, loading, saved, validated, registered, failure(String) }
    @State private var phase: Phase = .idle
    @State private var ticket: RegistrationTicket?
    @State private var showsConfirmation = false
    @State private var order: Order?
    @State private var showsPayment = false
    @State private var progressMessage = ""

    var body: some View {
        VStack(spacing: 10) {
            switch phase {
            case .registered:
                Label("Tu es inscrit", systemImage: "checkmark.seal.fill")
                    .font(.cond(17)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            case .validated:
                // registration validated, only the payment is left
                ActionRow(title: order.map { "Payer \(formatEuros($0.amount))" } ?? "Payer",
                          subtitle: "Inscription validée · il reste le paiement par carte",
                          icon: "creditcard", tone: .primary) { showsPayment = true }

            case .saved:
                // registration saved but the flow was interrupted: resume it
                ActionRow(title: "Reprendre l'inscription", subtitle: "Enregistrée mais pas encore validée",
                          icon: "arrow.clockwise", tone: .primary) { Task { await validateAndPay() } }

            case .loading:
                VStack(spacing: 8) {
                    ProgressView().tint(Theme.accent)
                    if !progressMessage.isEmpty { Text(progressMessage).font(.barlow(13)).foregroundStyle(Theme.muted) }
                }
                .frame(maxWidth: .infinity, minHeight: 52)

            case .idle, .failure:
                ActionRow(title: "S'inscrire", subtitle: "Tarif affiché avant confirmation · paiement CB",
                          icon: "square.and.pencil", tone: .primary) { Task { await prepare() } }
                if case .failure(let message) = phase {
                    Text(message).font(.barlow(13)).foregroundStyle(Theme.danger).multilineTextAlignment(.center)
                }
            }
        }
        // after payment: registered → confirmed in race tracking
        .sheet(isPresented: $showsPayment, onDismiss: {
            auth.client.invalidateTracking()   // the payment may have changed registrations and orders
            Task { await restorePhase(); await tracking.refresh(auth) }
        }) {
            PaymentWebView(url: UfolepClient.paymentURL(order))
        }
        .task { await restorePhase() }
        .confirmationDialog("S'inscrire et payer ?", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("Confirmer et payer \(formatEuros(ticket?.total))") { Task { await registerAndPay() } }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("\(event.name) · \(race.level.name)\nTarif : \(formatEuros(ticket?.total)). Ton inscription sera enregistrée et validée, puis tu passeras au paiement par carte bancaire.")
        }
    }

    private func formatEuros(_ amount: Double?) -> String {
        guard let amount else { return "—" }
        return amount.formatted(.currency(code: "EUR").locale(Locale(identifier: "fr_FR")))
    }

    // MARK: flow

    /// Asks the site what is allowed for you, then the ticket (price). Nothing is saved at this stage.
    private func prepare() async {
        phase = .loading
        progressMessage = "Vérification de ton inscription…"
        do {
            ticket = try await auth.withSession {
                let person = try await auth.client.fetchPersonID()
                let detail = try await auth.client.fetchPersonRegistrationDetail(eventID: event.id, personID: person)
                guard let status = detail.levels.first(where: { $0.level.id == race.level.id }) else {
                    throw UfolepError.denied(["Cette course n'est pas proposée pour ton profil."])
                }
                guard status.isOpenForRegistration else { throw UfolepError.denied(status.errors.isEmpty ? ["Inscription impossible."] : status.errors) }
                if !(detail.requestedDocuments ?? []).isEmpty {
                    throw UfolepError.denied(["Des documents sont demandés : termine l'inscription sur le site."])
                }
                return try await auth.client.computeTicket(eventID: event.id, personID: person, levelID: race.level.id)
            }
            phase = .idle
            showsConfirmation = true
        } catch {
            phase = .failure(error.localizedDescription)
        }
    }

    /// After confirmation: saves, validates, then opens the payment.
    private func registerAndPay() async {
        guard let ticket else { return }
        phase = .loading
        progressMessage = "Enregistrement de l'inscription…"
        do {
            try await auth.withSession { try await auth.client.save(ticketID: ticket.id, final: false) }
            auth.client.invalidateTracking()
        } catch {
            phase = .failure(error.localizedDescription)
            return
        }
        await validateAndPay()
    }

    /// Finalizes the registration (it becomes "to pay"), then opens the payment page.
    private func validateAndPay() async {
        phase = .loading
        progressMessage = "Validation de l'inscription…"
        do {
            let validation = try await auth.withSession { try await auth.client.computeFinalTicket(eventID: event.id) }
            try await auth.withSession { try await auth.client.saveFinalRegistration(eventID: event.id, ticketID: validation.id) }
            auth.client.invalidateTracking()
        } catch {
            // the registration is saved: offer to resume where it stopped
            phase = .saved
            progressMessage = ""
            return
        }
        progressMessage = "Préparation du paiement…"
        let orders = (try? await auth.withSession { try await auth.client.fetchOrders() }) ?? []
        order = orders.first { $0.name.localizedCaseInsensitiveContains(event.name) }
        if order != nil {
            phase = .validated
            Task { await tracking.refresh(auth) }   // untracked / wishlist → registered, without delaying the payment
            showsPayment = true
        } else {
            phase = .registered   // free: nothing to pay
            await tracking.refresh(auth)
        }
    }

    /// Resumes where you left off: to pay, registered, saved but not validated, or nothing.
    private func restorePhase() async {
        guard phase == .idle || phase == .validated || phase == .saved || phase == .registered else { return }
        let orders = (try? await auth.withSession { try await auth.client.fetchOrders() }) ?? []
        if let found = orders.first(where: { $0.name.localizedCaseInsensitiveContains(event.name) }) {
            order = found
            phase = .validated
            return
        }
        order = nil
        // no order to pay: check whether the site already lists you as registered
        let registrations = (try? await auth.withSession { try await auth.client.fetchRegistrations() }) ?? []
        if let mine = registrations.first(where: { $0.eventID == event.id }) {
            let status = (mine.entries.first?.status ?? "").lowercased()
            phase = status.contains("saisie") ? .saved : .registered
        } else if ((try? await auth.withSession { try await auth.client.draftRegistrationCount(eventID: event.id) }) ?? 0) > 0 {
            phase = .saved
        } else {
            phase = .idle
        }
    }
}
