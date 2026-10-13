import SwiftUI
import WebKit

/// Page de paiement du site dans l'app, avec la session du licencié.
/// Le paiement (carte bancaire) est confirmé et saisi par l'utilisateur sur la page de la banque, jamais par l'app.
struct PaiementWebView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var navigateur = Navigateur()
    @State private var prepare = false

    /// Fenêtre web isolée : son propre stockage, qui ne reçoit que la session du licencié.
    @MainActor private final class Navigateur {
        let stockage = WKWebsiteDataStore.nonPersistent()
        let page: WebPage

        init() {
            var configuration = WebPage.Configuration()
            configuration.websiteDataStore = stockage
            page = WebPage(configuration: configuration)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if prepare { WebView(navigateur.page) } else { ProgressView().tint(Theme.accent) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(navigateur.page.title.isEmpty ? "Paiement" : navigateur.page.title)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbarBackground(Theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Fermer") { dismiss() } }
            }
            .task {
                for cookie in auth.client.cookies() {
                    await navigateur.stockage.httpCookieStore.setCookie(cookie)
                }
                prepare = true
                navigateur.page.load(URLRequest(url: url))
            }
        }
        .interactiveDismissDisabled()
    }
}
