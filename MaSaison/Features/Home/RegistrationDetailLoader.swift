import SwiftUI

/// Loads the full event (calendar API) of a registration then shows its detail.
struct RegistrationDetailLoader: View {
    @Environment(AuthModel.self) private var auth
    let registration: Registration
    @State private var event: Event?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let event {
                EventDetailView(event: event)
            } else if let errorMessage {
                ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(errorMessage)).screenBackground()
            } else {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground()
            }
        }
        .task {
            do {
                event = try await auth.withSession {
                    try await auth.client.fetchEvent(id: registration.eventID, name: registration.name)
                }
                if event == nil { errorMessage = "Manifestation introuvable." }
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
