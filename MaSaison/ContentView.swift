import SwiftUI

struct ContentView: View {
    @State private var auth = AuthModel()
    @State private var filtres = FiltresStore()
    @State private var cartes = CartesStore()
    @State private var agenda = AgendaStore()

    var body: some View {
        Group {
            if auth.isRestoring {
                ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity).screenBackground()
            } else if auth.isLoggedIn {
                MainTabView()
            } else {
                NavigationStack { LoginView() }
            }
        }
        .environment(auth)
        .environment(filtres)
        .environment(cartes)
        .environment(agenda)
        .task { await auth.restoreSession() }
    }
}

struct MainTabView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(FiltresStore.self) private var filtres
    @Environment(CartesStore.self) private var cartes
    @AppStorage("ongletSelectionne") private var onglet = 0

    var body: some View {
        TabView(selection: $onglet) {
            Tab("Accueil", systemImage: "house", value: 0) {
                NavigationStack { MesInscriptionsView() }
            }
            Tab("Courses", systemImage: "flag.checkered", value: 1) {
                NavigationStack { ManifestationsView() }
            }
            Tab("Profil", systemImage: "person.crop.circle", value: 2) {
                NavigationStack { ProfilView() }
            }
        }
        .tint(Theme.accent)
        .task {
            await filtres.loadIfNeeded(auth: auth)
            await cartes.load(auth: auth)
            filtres.appliquerOrigine(cartes: cartes.cartes)
        }
    }
}

#Preview {
    ContentView()
}
