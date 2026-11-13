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
    @AppStorage("hideFloatingTabBar") private var hideFloatingTabBar = false

    var body: some View {
        ZStack {
            switch onglet {
            case 0:
                NavigationStack { MesInscriptionsView() }
            case 1:
                NavigationStack {
                    ManifestationsView(vueInitiale: .liste, afficherSelecteurVue: false, afficherRecherche: true)
                }
            case 2:
                NavigationStack {
                    ManifestationsView(vueInitiale: .carte, afficherSelecteurVue: false, afficherRecherche: false)
                }
            case 3:
                NavigationStack {
                    ManifestationsView(vueInitiale: .calendrier, afficherSelecteurVue: false, afficherRecherche: false)
                }
            default:
                NavigationStack { ProfilView() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !hideFloatingTabBar {
                FloatingTabBar(selection: $onglet)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
        .task {
            await filtres.loadIfNeeded(auth: auth)
            await cartes.load(auth: auth)
            filtres.appliquerOrigine(cartes: cartes.cartes)
        }
    }
}

private struct FloatingTabBar: View {
    @Binding var selection: Int

    private let items: [(index: Int, title: String, icon: String, selectedIcon: String)] = [
        (0, "Accueil", "house", "house.fill"),
        (1, "Courses", "bicycle", "bicycle"),
        (2, "Carte", "map", "map.fill"),
        (3, "Calendrier", "calendar", "calendar"),
        (4, "Profil", "person", "person.fill")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.index) { item in
                let actif = selection == item.index
                Button {
                    selection = item.index
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: actif ? item.selectedIcon : item.icon)
                            .font(.system(size: 20, weight: actif ? .semibold : .medium))
                        Text(item.title)
                            .font(.barlow(11, actif ? .semibold : .medium))
                        Circle()
                            .fill(actif ? Theme.accent : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(actif ? Theme.accent : Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 4)
    }
}

#Preview {
    ContentView()
}
