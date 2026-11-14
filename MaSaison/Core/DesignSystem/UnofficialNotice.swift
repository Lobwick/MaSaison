import SwiftUI

/// Notice shown on the login and profile screens.
struct UnofficialNotice: View {
    var body: some View {
        Text("Application non officielle : elle n'est pas éditée par l'UFOLEP. Elle est réalisée bénévolement par Félix.")
            .font(.barlow(13)).foregroundStyle(Theme.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
