import Foundation
import Observation

@Observable
final class AuthModel {
    let client = UfolepClient()
    var isLoggedIn = false
    var isLoading = false
    var isRestoring = true
    var errorMessage: String?

    func login(username: String, password: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await client.login(username: username, password: password)
            CredentialStore.save(.init(username: username, password: password))
            isLoggedIn = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Au lancement : reconnexion automatique avec les identifiants du Keychain.
    func restoreSession() async {
        defer { isRestoring = false }
        guard let saved = CredentialStore.load() else { return }
        do {
            try await client.login(username: saved.username, password: saved.password)
            isLoggedIn = true
        } catch UfolepError.identifiantsInvalides {
            CredentialStore.delete()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Exécute `operation` ; si la session a expiré, se reconnecte une fois et réessaie.
    func withSession<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch UfolepError.sessionExpiree {
            guard let saved = CredentialStore.load() else { isLoggedIn = false; throw UfolepError.sessionExpiree }
            try await client.login(username: saved.username, password: saved.password)
            return try await operation()
        }
    }

    func logout() {
        client.clearSession()
        CredentialStore.delete()
        isLoggedIn = false
    }
}
