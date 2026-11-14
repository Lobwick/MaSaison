import SwiftUI

/// Home: next race with countdown, then upcoming and finished registrations.
struct HomeView: View {
    private enum Segment: String, CaseIterable, Identifiable {
        case upcoming = "À venir"
        case finished = "Terminées"
        var id: String { rawValue }
    }

    @Environment(AuthModel.self) private var auth
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(RaceTrackingStore.self) private var tracking
    @State private var registrations: [Registration] = []
    @State private var results: [RaceResult] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var segment: Segment = .upcoming
    @State private var nextRaceWeather: WeatherSummary?
    @State private var weatherEventID: Int?
    @State private var eventStartTimes: [Int: String] = [:]
    @State private var nextRaceNavigationURL: URL?
    @State private var photo: UIImage?
    private let homeAccent = Color(hex: 0x006948)

    private var upcoming: [Registration] {
        registrations.filter { !$0.isFinished }.sorted { ($0.startDate ?? .distantFuture) < ($1.startDate ?? .distantFuture) }
    }
    private var finished: [Registration] {
        registrations.filter(\.isFinished).sorted { ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast) }
    }

    private var displayedRegistrations: [Registration] {
        segment == .upcoming ? upcoming : finished
    }

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                homeHeader

                if let nextRace = upcoming.first {
                    NavigationLink { RegistrationDetailLoader(registration: nextRace) } label: {
                        NextRaceCard(
                            registration: nextRace,
                            status: tracking.status(nextRace.eventID),
                            isInCalendar: calendarStore.isAdded(event: nextRace.eventID),
                            weather: weatherEventID == nextRace.eventID ? nextRaceWeather : nil,
                            accent: homeAccent,
                            startTime: displayedTime(nextRace),
                            calendarURL: calendarURL(for: nextRace.startDate),
                            navigationURL: nextRaceNavigationURL
                        )
                    }
                    .buttonStyle(.plain)
                } else if !isLoading && errorMessage == nil {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("PROCHAINE COURSE")
                        Text("Aucune inscription à venir").font(.cond(24, .semibold)).textCase(.uppercase)
                        Text("Cherchez une manifestation dans l'onglet Courses.").font(.barlow(14)).foregroundStyle(Theme.muted)
                    }
                    .card(radius: 24, padding: 20)
                }

                segmentControl

                if !displayedRegistrations.isEmpty {
                    section(segment == .upcoming ? "Prochain départ" : "Historique des courses",
                            trailing: segment == .upcoming ? upcoming.first.flatMap(relativeDepartureLabel) : nil) {
                        ForEach(displayedRegistrations) { row($0) }
                    }
                } else {
                    Text(segment == .upcoming ? "Aucune course à venir." : "Aucune course terminée.")
                        .font(.barlow(14))
                        .foregroundStyle(Theme.muted)
                        .card(padding: 14)
                }

                if let errorMessage {
                    Text(errorMessage).font(.barlow(14)).foregroundStyle(Theme.danger)
                }
            }
            .padding(.horizontal, 20).padding(.top, 0).padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .overlay { if isLoading && registrations.isEmpty { ProgressView().tint(Theme.accent) } }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await auth.client.bypassingCache { await load() } }
        .task { await load() }
        .task { await loadProfilePhoto() }
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            TitleAndProfileActions(title: "ACCUEIL", photo: photo, accent: homeAccent)
            .padding(.top, -10)
            Rectangle().fill(Theme.line).frame(height: 1)
        }
    }

    private var segmentControl: some View {
        HStack(spacing: 4) {
            segmentButton(.upcoming, count: upcoming.count)
            segmentButton(.finished, count: finished.count)
        }
        .padding(4)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func segmentButton(_ target: Segment, count: Int) -> some View {
        let isActive = segment == target
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { segment = target }
        } label: {
            HStack(spacing: 6) {
                Text(target.rawValue).font(.barlow(13, .semibold))
                Text("\(count)")
                    .font(.barlow(11, .semibold))
                    .foregroundStyle(isActive ? Color.white : Theme.textSoft)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(isActive ? homeAccent : Theme.surface, in: Capsule())
            }
            .foregroundStyle(isActive ? Theme.text : Theme.muted)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(isActive ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func section<Content: View>(_ title: String, trailing: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(title)
                Spacer()
                if let trailing {
                    Text(trailing).font(.barlow(13, .semibold)).foregroundStyle(homeAccent)
                }
            }
            content()
        }
    }

    private func row(_ i: Registration) -> some View {
        NavigationLink { RegistrationDetailLoader(registration: i) } label: {
            HStack(spacing: 14) {
                DateAndTime(date: i.startDate, time: displayedTime(i), highlighted: !i.isFinished)
                    .frame(width: 60)
                VStack(alignment: .leading, spacing: 3) {
                    Text(i.name).font(.cond(20, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                    Text([i.organizer, i.entries.flatMap(\.levels).first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.barlow(13))
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
                Spacer()
                if i.isFinished, let r = result(for: i) {
                    Text(r.shortText)
                        .font(.barlow(12, .semibold))
                        .foregroundStyle(Theme.textSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.surface2, in: Capsule())
                }
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
            }
            .padding(12)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(!i.isFinished ? homeAccent.opacity(0.25) : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func displayedTime(_ registration: Registration) -> String? {
        if let time = eventStartTimes[registration.eventID] { return time }
        if let date = registration.startDate {
            let cal = Calendar.current
            let h = cal.component(.hour, from: date)
            let m = cal.component(.minute, from: date)
            if h != 0 || m != 0 {
                return Date.fr("HH:mm").string(from: date)
            }
        }
        guard let match = registration.dateText.firstMatch(of: #/\b(\d{1,2})[:hH](\d{2})\b/#),
              let time = Int(match.output.1), time >= 0, time <= 23 else { return nil }
        return String(format: "%02d:%@", time, String(match.output.2))
    }

    /// When the next race starts, relative to today: "Ce matin", "Demain après-midi", "Dans 4 jours", "Le 21 nov."…
    /// The part of the day is only given for today and tomorrow, when the start time is known.
    private func relativeDepartureLabel(_ registration: Registration) -> String? {
        guard let start = registration.startDate else { return nil }
        let cal = Calendar.current
        guard let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: start)).day,
              days >= 0 else { return nil }
        let hour = displayedTime(registration).flatMap { Int($0.prefix(while: \.isNumber)) }
        switch days {
        case 0:
            guard let hour else { return "Aujourd'hui" }
            return hour < 12 ? "Ce matin" : hour < 18 ? "Cet après-midi" : "Ce soir"
        case 1:
            guard let hour else { return "Demain" }
            return "Demain " + (hour < 12 ? "matin" : hour < 18 ? "après-midi" : "soir")
        case 2...6:
            return "Dans \(days) jours"
        default:
            return "Le " + Date.fr("d MMM").string(from: start)
        }
    }

    private func normalizeTime(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let d = Date.fr("HH:mm:ss").date(from: raw) { return Date.fr("HH:mm").string(from: d) }
        if let d = Date.fr("HH:mm").date(from: raw) { return Date.fr("HH:mm").string(from: d) }
        if raw.contains(":") { return raw }
        return nil
    }

    /// By event identifier, otherwise by date (names differ from one page to another).
    private func result(for i: Registration) -> RaceResult? {
        results.first { $0.eventID == i.eventID }
            ?? results.first { $0.date != nil && $0.date == i.startDate }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        // show the last known data immediately, then update if the cache is stale
        if registrations.isEmpty, let cachedItems = await auth.client.fromCacheOnly({ try await auth.client.fetchRegistrations() }) {
            registrations = cachedItems
            results = await auth.client.fromCacheOnly { try await auth.client.fetchResults() } ?? results
        }
        do {
            registrations = try await auth.withSession { try await auth.client.fetchRegistrations() }
            // registered / confirmed status of the next race card (also refreshed on pull to refresh)
            await tracking.refresh(auth)
            await loadRegistrationTimes()
            // results are a bonus: their failure does not block the home screen
            results = (try? await auth.withSession { try await auth.client.fetchResults() }) ?? results
            await loadNextRaceWeather()
        } catch {
            errorMessage = error.localizedDescription
            nextRaceWeather = nil
            weatherEventID = nil
        }
    }

    private func loadNextRaceWeather() async {
        nextRaceWeather = nil
        weatherEventID = nil
        nextRaceNavigationURL = nil
        guard let nextRace = upcoming.first else { return }
        do {
            guard let event = try await auth.withSession({
                try await auth.client.fetchEvent(id: nextRace.eventID, name: nextRace.name)
            }) else { return }
            if let time = normalizeTime(event.startTimeText) {
                eventStartTimes[nextRace.eventID] = time
            }
            if let c = event.address?.coordinate {
                nextRaceNavigationURL = navigationURL(for: c.latitude, longitude: c.longitude)
                if let day = nextRace.startDate, ForecastService.isWithinHorizon(day) {
                    let fullDay = try await ForecastService.forecast(latitude: c.latitude, longitude: c.longitude, day: day)
                    // restricted to the time range of the entered races (all if none match) rather than the whole day
                    let timeRange = CalendarService.timeRange(event: event, races: enteredRaces(nextRace, in: event))
                    nextRaceWeather = timeRange.flatMap { p in fullDay?.during(p) } ?? fullDay
                }
            }
            weatherEventID = nextRace.eventID
        } catch {
            nextRaceWeather = nil
            weatherEventID = nextRace.eventID
        }
    }

    /// Races of the event whose level ("Adultes - 3e catégorie" → "3e catégorie") appears in the registration.
    private func enteredRaces(_ registration: Registration, in event: Event) -> [Race] {
        let levels = Set(registration.entries.flatMap(\.levels).map {
            ($0.components(separatedBy: " - ").last ?? $0).trimmingCharacters(in: .whitespaces).lowercased()
        })
        let entered = event.races.filter { levels.contains($0.level.name.lowercased()) }
        return entered.isEmpty ? event.races : entered
    }

    private func loadRegistrationTimes() async {
        let targets = Array(registrations.prefix(10))
        var map = eventStartTimes
        for registration in targets {
            do {
                let event = try await auth.withSession {
                    try await auth.client.fetchEvent(id: registration.eventID, name: registration.name)
                }
                if let time = normalizeTime(event?.startTimeText) {
                    map[registration.eventID] = time
                }
            } catch {
                continue
            }
        }
        eventStartTimes = map
    }

    private func loadProfilePhoto() async {
        do {
            let profile = try await auth.withSession { try await auth.client.fetchProfile() }
            guard let url = profile.photoURL else { return }
            if let data = try? await auth.withSession({ try await auth.client.download(url) }) {
                photo = UIImage(data: data)
            }
        } catch {
            photo = nil
        }
    }

    private func calendarURL(for date: Date?) -> URL? {
        guard let date else { return nil }
        let t = Int(date.timeIntervalSinceReferenceDate)
        return URL(string: "calshow:\(t)")
    }

    private func navigationURL(for latitude: Double, longitude: Double) -> URL? {
        var components = URLComponents(string: "https://maps.apple.com")
        components?.queryItems = [
            URLQueryItem(name: "daddr", value: "\(latitude),\(longitude)"),
            URLQueryItem(name: "dirflg", value: "d")
        ]
        return components?.url
    }
}

private struct NextRaceCard: View {
    let registration: Registration
    /// Registration status from `RaceTrackingStore`: only `.confirmed` means paid.
    let status: TrackingStatus
    let isInCalendar: Bool
    let weather: WeatherSummary?
    let accent: Color
    let startTime: String?
    let calendarURL: URL?
    let navigationURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("BRIEF JOUR DE COURSE")
                Spacer()
                Pill(text: statusPillText, fg: statusTint, bg: statusTint.opacity(0.12))
            }
            HStack(spacing: 18) {
                countdownRing
                VStack(alignment: .leading, spacing: 6) {
                    Text(registration.name).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    Text([registration.organizer, registration.entries.flatMap(\.levels).first].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.barlow(14)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                    Text("Départ \(startTimeLabel)")
                        .font(.barlow(12, .semibold))
                        .foregroundStyle(Theme.textSoft)
                    HStack(spacing: 8) {
                        Label(registration.organizer, systemImage: "mappin")
                    }
                    .font(.barlow(12, .semibold))
                    .foregroundStyle(Theme.muted)
                }
            }
            if let weather {
                weatherSummary(weather)
            }
            Divider().overlay(Theme.line)
            HStack {
                Label(statusFooter.text, systemImage: statusFooter.icon)
                    .font(.barlow(13, .semibold))
                    .foregroundStyle(statusTint)
                Spacer()
                if let navigationURL {
                    Link(destination: navigationURL) {
                        Pill(text: "Naviguer", systemImage: "location.fill", fg: Theme.textSoft, bg: Theme.surface2)
                    }
                } else {
                    Pill(text: "Naviguer", systemImage: "location.fill", fg: Theme.faint, bg: Theme.surface2)
                }
                if let calendarURL {
                    Link(destination: calendarURL) {
                        Pill(
                            text: "Agenda",
                            systemImage: "calendar.badge.plus",
                            fg: isInCalendar ? accent : Theme.textSoft,
                            bg: isInCalendar ? accent.opacity(0.12) : Theme.surface2
                        )
                    }
                } else {
                    Pill(text: "Agenda", systemImage: "calendar.badge.plus", fg: Theme.faint, bg: Theme.surface2)
                }
            }
        }
        .padding(20)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .overlay(alignment: .top) {
            LinearGradient(colors: [accent, Color(hex: 0x85F8C4), Theme.secondary],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 4)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    private var daysLeft: Int {
        guard let start = registration.startDate else { return 0 }
        let cal = Calendar.current
        return max(0, cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: start)).day ?? 0)
    }

    private var secondsLeft: TimeInterval {
        guard let start = registration.startDate else { return 0 }
        return start.timeIntervalSinceNow
    }

    private var hoursLeft: Int {
        max(1, Int(ceil(secondsLeft / 3600)))
    }

    /// The ring is decorative: it fills up as the race approaches (over 30 days).
    private var countdownRing: some View {
        ZStack {
            Circle().stroke(Theme.line, lineWidth: 9)
            Circle().trim(from: 0, to: max(0.05, 1 - Double(min(daysLeft, 30)) / 30))
                .stroke(accent, style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(countdownLabel).font(.cond(40)).foregroundStyle(Theme.text)
                Text(registration.startDate.map { Date.fr("EEE d MMM").string(from: $0).uppercased().replacingOccurrences(of: ".", with: "") } ?? "")
                    .font(.cond(11, .medium)).tracking(1.5).foregroundStyle(Theme.muted)
            }
        }
        .frame(width: 112, height: 112)
    }

    private var countdownLabel: String {
        if secondsLeft <= 0 { return "J" }
        if secondsLeft < 86_400 { return "H-\(hoursLeft)" }
        return "J-\(daysLeft)"
    }

    private var shortStatus: String {
        if secondsLeft <= 0 { return "Jour J" }
        if secondsLeft < 86_400 { return "H-\(hoursLeft)" }
        return "J-\(daysLeft)"
    }

    /// Confirmed in the accent color, payment pending in blue, unknown (tracking not loaded yet) in grey.
    private var statusTint: Color {
        switch status {
        case .confirmed: accent
        case .registered: Theme.secondary
        case .untracked, .wishlist: Theme.muted
        }
    }

    private var statusPillText: String {
        switch status {
        case .confirmed: "\(shortStatus) CONFIRMÉ"
        case .registered: "\(shortStatus) À PAYER"
        case .untracked, .wishlist: shortStatus
        }
    }

    private var statusFooter: (text: String, icon: String) {
        switch status {
        case .confirmed: ("Engagement validé", "checkmark.seal")
        case .registered: ("Inscrit · paiement en attente", "hourglass")
        case .untracked, .wishlist: ("Inscrit", "checkmark.circle")
        }
    }

    private var startTimeLabel: String {
        if let startTime { return startTime.replacingOccurrences(of: ":", with: "h") }
        if let date = registration.startDate { return Date.fr("HH'h'mm").string(from: date) }
        return "—"
    }

    private func weatherSummary(_ weather: WeatherSummary) -> some View {
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let min = Int(weather.minTemp.rounded()), max = Int(weather.maxTemp.rounded())
        let rain = weather.rainMm >= 0.1 ? String(format: "%.1f mm", weather.rainMm).replacingOccurrences(of: ".", with: ",") : "Sec"
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                WeatherIcon(symbol: weather.symbol, size: 26)
                    .frame(width: 34)
                Text(weather.condition).font(.barlow(14, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Spacer()
                Text(weather.timeRange.map { "\($0.start.formatted(time)) – \($0.end.formatted(time))" } ?? "Journée")
                    .font(.barlow(11, .semibold)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 0) {
                weatherCell("TEMP.", min == max ? "\(max)°" : "\(min)°/\(max)°", icon: "thermometer.medium", tint: Color(hex: 0xD97706))
                Divider().frame(height: 40)
                weatherCell("PLUIE", "\(weather.rainChance)%", icon: "cloud.rain.fill", tint: Theme.secondary, detail: rain)
                Divider().frame(height: 40)
                weatherCell("VENT", "\(Int(weather.windKmh.rounded())) km/h", icon: "wind", tint: Color(hex: 0x2563EB),
                          detail: weather.gustsKmh.map { "Rafales \(Int($0.rounded()))" })
            }
        }
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func weatherCell(_ title: String, _ value: String, icon: String, tint: Color, detail: String? = nil) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.barlow(10, .semibold)).foregroundStyle(Theme.muted)
                Text(value).font(.barlow(14, .semibold)).foregroundStyle(Theme.text)
                if let detail {
                    Text(detail).font(.barlow(10)).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }
}
