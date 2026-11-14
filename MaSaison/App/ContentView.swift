import SwiftUI

struct ContentView: View {
    @State private var auth = AuthModel()
    @State private var filters = FilterStore()
    @State private var cardStore = LicenseCardStore()
    @State private var calendarStore = CalendarStore()
    @State private var tracking = RaceTrackingStore()

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
        .environment(filters)
        .environment(cardStore)
        .environment(calendarStore)
        .environment(tracking)
        .task { await auth.restoreSession() }
        // on launch and on sign-in: refresh statuses and reschedule closing reminders
        .task(id: auth.isLoggedIn) { if auth.isLoggedIn { await tracking.refresh(auth) } }
    }
}
