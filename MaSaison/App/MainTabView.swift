import SwiftUI

struct MainTabView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(FilterStore.self) private var filters
    @Environment(LicenseCardStore.self) private var cardStore
    @AppStorage("ongletSelectionne") private var selectedTab = 0
    @AppStorage("hideFloatingTabBar") private var hideFloatingTabBar = false
    /// Identity of each tab's navigation stack: changing it pops the tab back to its root screen.
    @State private var rootIDs: [Int: UUID] = [:]

    /// Tabs already opened: created on first visit then kept alive (state, loaded list, scroll position).
    @State private var visitedTabs: Set<Int> = []

    var body: some View {
        ZStack {
            ForEach(Array(visitedTabs.union([selectedTab])).sorted(), id: \.self) { index in
                let isActive = index == selectedTab
                screen(index)
                    // tapping the active tab changes this identifier and pops the tab back to its root screen
                    .id(rootIDs[index])
                    .opacity(isActive ? 1 : 0)
                    .allowsHitTesting(isActive)
                    .accessibilityHidden(!isActive)
            }
        }
        .onChange(of: selectedTab, initial: true) { _, updated in visitedTabs.insert(updated) }
        .safeAreaInset(edge: .bottom) {
            if !hideFloatingTabBar {
                // tapping the already active tab returns to its root screen (like an iOS tab bar)
                FloatingTabBar(selection: $selectedTab) { rootIDs[$0] = UUID() }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
            }
        }
        .task {
            await filters.loadIfNeeded(auth: auth)
            await cardStore.load(auth: auth)
            filters.applyCardDefaults(cards: cardStore.cards)
        }
    }

    @ViewBuilder
    private func screen(_ index: Int) -> some View {
        switch index {
        case 0:
            NavigationStack { HomeView() }
        case 1:
            NavigationStack {
                EventsView(initialMode: .list, showsViewPicker: false, showsSearch: true)
            }
        case 2:
            NavigationStack {
                EventsView(initialMode: .map, showsViewPicker: false, showsSearch: false)
            }
        case 3:
            NavigationStack {
                EventsView(initialMode: .calendar, showsViewPicker: false, showsSearch: false)
            }
        default:
            NavigationStack { ProfileView() }
        }
    }
}

private struct FloatingTabBar: View {
    @Binding var selection: Int
    /// Called when the already selected tab is tapped.
    var reselection: (Int) -> Void = { _ in }

    private let items: [(index: Int, title: String, icon: String, selectedIcon: String)] = [
        (0, "Accueil", "house", "house.fill"),
        (1, "Courses", "bicycle", "bicycle"),
      //  (2, "Carte", "map", "map.fill"),
        //(3, "Calendrier", "calendar", "calendar"),
        (4, "Profil", "person", "person.fill")
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.index) { item in
                let isActive = selection == item.index
                Button {
                    if selection == item.index { reselection(item.index) } else { selection = item.index }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: isActive ? item.selectedIcon : item.icon)
                            .font(.system(size: 20, weight: isActive ? .semibold : .medium))
                        Text(item.title)
                            .font(.barlow(11, isActive ? .semibold : .medium))
                        Circle()
                            .fill(isActive ? Theme.accent : .clear)
                            .frame(width: 4, height: 4)
                    }
                    .foregroundStyle(isActive ? Theme.accent : Theme.muted)
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
