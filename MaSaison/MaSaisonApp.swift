import SwiftUI
import TipKit

@main struct MaSaisonApp: App {
    init() {
        Theme.registerFonts()
        try? Tips.configure([.displayFrequency(.immediate)])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
