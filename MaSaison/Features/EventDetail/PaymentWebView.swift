import SwiftUI
import WebKit

/// The site's payment page inside the app, with the member's session.
/// The payment (bank card) is confirmed and entered by the user on the bank's page, never by the app.
struct PaymentWebView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.dismiss) private var dismiss
    let url: URL
    @State private var browser = Browser()
    @State private var isReady = false

    /// Isolated web window: its own storage, which only receives the member's session.
    @MainActor private final class Browser {
        let dataStore = WKWebsiteDataStore.nonPersistent()
        let page: WebPage

        init() {
            var configuration = WebPage.Configuration()
            configuration.websiteDataStore = dataStore
            page = WebPage(configuration: configuration)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isReady { WebView(browser.page) } else { ProgressView().tint(Theme.accent) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .screenBackground()
            .navigationTitle(browser.page.title.isEmpty ? "Paiement" : browser.page.title)
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
                    await browser.dataStore.httpCookieStore.setCookie(cookie)
                }
                isReady = true
                browser.page.load(URLRequest(url: url))
            }
        }
        .interactiveDismissDisabled()
    }
}
