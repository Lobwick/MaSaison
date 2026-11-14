import Charts
import MapKit
import QuickLook
import SwiftUI

/// Event detail: registration status, my races, location and track, other races.
struct EventDetailView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(LicenseCardStore.self) private var cardStore
    @Environment(CalendarStore.self) private var calendarStore
    @Environment(RaceTrackingStore.self) private var tracking
    @AppStorage("boutonAgenda") private var showsCalendarButton = true
    @AppStorage("echauffementMinutes") private var warmUp = 60
    @Environment(\.dismiss) private var dismiss

    let event: Event
    @State private var groups: [LevelGroup] = []
    @State private var errorMessage: String?
    @State private var track: GPXTrack?
    @State private var gpxFile: URL?
    @State private var othersExpanded = false
    @State private var calendarError: String?
    @State private var weather: WeatherSummary?
    @State private var weatherError: String?
    @State private var trackRequested = false
    @State private var weatherRequested = false
    @State private var travelTime: TravelTime?
    @State private var isComputingTravelTime = false
    @State private var calendarInfo: String?
    @State private var travelTimeError: String?
    @State private var isUpdatingTravelTime = false
    @State private var weatherCredits: WeatherCredits?
    @State private var preview: URL?
    @State private var loadingDocument: URL?
    @State private var documentError: String?
    @State private var contact: EventContact?
    @State private var profilePhoto: UIImage?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 22) {
                detailNavigationBar
                header

                if myRaces.isEmpty {
                    if !others.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow("COURSES")
                            VStack(spacing: 0) { ForEach(others, id: \.race.id) { otherRaceRow($0) } }.card(padding: 4)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("POUR MOI", color: Theme.accent)
                        ForEach(myRaces, id: \.race.id) { raceCard($0.race, group: $0.group) }
                    }
                }

                if isWeatherAvailable { weatherSection }

                locationAndTrack

                if !myRaces.isEmpty && !others.isEmpty { otherRacesSection }

                if !event.pdfDocuments.isEmpty { documentsSection }

                organizerSection

                if let errorMessage { Text(errorMessage).font(.barlow(14)).foregroundStyle(Theme.danger) }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 120)
            .containerRelativeFrame(.horizontal)
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        // three independent loads, started on appear: none waits for the others
        .task { await loadGroups() }
        .task { await loadTrack() }
        .task { await loadWeather() }
        .task { contact = try? await auth.withSession { try await auth.client.fetchContact(eventID: event.id) } }
        .task { await loadProfilePhoto() }
        .task {
            tracking.rememberDeadlines([event])
            await tracking.refresh(auth)
        }
        // already authorized: travel time is computed without asking; otherwise a button offers to do it
        .task { if TravelTimeService.isAuthorized { await computeTravelTime() } }
        .quickLookPreview($preview)
    }

    // MARK: documents and organizer

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("DOCUMENTS")
            VStack(spacing: 0) {
                ForEach(Array(event.pdfDocuments.enumerated()), id: \.offset) { _, doc in
                    Button { Task { await openDocument(doc.url, name: doc.name) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(Theme.accent)
                            Text(doc.name).font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            if loadingDocument == doc.url { ProgressView().controlSize(.small) }
                            else { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted) }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(loadingDocument != nil)
                }
            }
            .card(padding: 4)
            if let documentError { Text(documentError).font(.barlow(13)).foregroundStyle(Theme.danger) }
        }
    }

    /// Downloads the PDF with the member's session then opens it in the QuickLook preview.
    private func openDocument(_ url: URL, name: String) async {
        documentError = nil
        loadingDocument = url
        defer { loadingDocument = nil }
        do {
            let data = try await auth.client.download(url)
            let fileName = "\(event.name.capitalized) - \(name)".replacingOccurrences(of: "/", with: "-")
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(fileName).pdf")
            try data.write(to: file)
            preview = file
        } catch {
            documentError = "Impossible d'ouvrir « \(name) » : \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var organizerSection: some View {
        if let structure = event.structure {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("ORGANISATEUR")
                Text(structure.name).font(.barlow(16)).foregroundStyle(Theme.text)
                if let name = contact?.fullName {
                    Text("Correspondant : \(name)").font(.barlow(14)).foregroundStyle(Theme.muted)
                }
                if let contact, contact.phoneURL != nil || contact.emailURL != nil {
                    VStack(spacing: 8) {
                        if let tel = contact.phoneURL {
                            Link(destination: tel) {
                                ActionRowLabel(title: "Appeler", subtitle: contact.contactPhone, icon: "phone")
                            }
                            .buttonStyle(ActionRowStyle())
                        }
                        if let mail = contact.emailURL {
                            Link(destination: mail) {
                                ActionRowLabel(title: "Écrire", subtitle: contact.contactEmail, icon: "envelope")
                            }
                            .buttonStyle(ActionRowStyle())
                        }
                    }
                }
            }
        }
    }

    // MARK: data

    private var allRaces: [(group: String, race: Race)] {
        groups.flatMap { group in
            event.races
                .filter { $0.level.groupID == group.id }
                .sorted { ($0.level.position ?? 0) < ($1.level.position ?? 0) }
                .map { (group.name, $0) }
        }
    }
    private var myRaces: [(group: String, race: Race)] { allRaces.filter { cardStore.matches(race: $0.race, in: event) } }
    private var others: [(group: String, race: Race)] { allRaces.filter { !cardStore.matches(race: $0.race, in: event) } }

    private func loadGroups() async {
        do {
            groups = try await auth.withSession { try await auth.client.fetchLevelGroups(eventID: event.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// GPX track: downloaded in parallel on appear; the map and profile update when it arrives.
    private func loadTrack() async {
        guard !trackRequested else { return }
        trackRequested = true
        guard let url = event.gpxURL, let data = try? await auth.client.download(url) else { return }
        track = GPXTrack.parse(data)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(event.name.capitalized).gpx")
        if (try? data.write(to: file)) != nil { gpxFile = file }
    }

    /// Weather: requested in parallel on appear; the card updates when it arrives.
    private func loadWeather() async {
        guard !weatherRequested else { return }
        weatherRequested = true
        guard let start = event.startDate else { weatherError = WeatherDiagnostic.unreadableDate(event.startDateText).localizedDescription; return }
        guard let c = event.address?.coordinate else { weatherError = WeatherDiagnostic.noCoordinates.localizedDescription; return }
        do {
            weather = try await ForecastService.forecast(latitude: c.latitude, longitude: c.longitude, day: start)
            if weather != nil { weatherCredits = await ForecastService.attribution() }
        } catch {
            weatherError = "\(error.localizedDescription)\n\(String(describing: error))"
        }
    }

    /// Travel time from my location (asks for permission the first time).
    private func computeTravelTime() async {
        guard let c = event.address?.coordinate, !isComputingTravelTime else { return }
        isComputingTravelTime = true
        defer { isComputingTravelTime = false }
        do {
            travelTime = try await TravelTimeService.travelTime(toLatitude: c.latitude, longitude: c.longitude)
            travelTimeError = nil
        } catch {
            travelTimeError = error.localizedDescription
        }
    }

    @ViewBuilder
    private var travelTimeRow: some View {
        if let travelTime {
            Label(travelTime.text, systemImage: "car.fill")
                .font(.barlow(13, .semibold)).foregroundStyle(Theme.accent).padding(.top, 4)
        } else if isComputingTravelTime {
            ProgressView().controlSize(.small).padding(.top, 4)
        } else if let travelTimeError {
            Text(travelTimeError).font(.barlow(12)).foregroundStyle(Theme.danger).padding(.top, 4)
        } else if TravelTimeService.isNotDetermined, event.address?.coordinate != nil {
            VStack(alignment: .leading, spacing: 2) {
                Button { Task { await computeTravelTime() } } label: {
                    Label("Temps de trajet depuis ma position", systemImage: "car")
                        .font(.barlow(13, .semibold)).foregroundStyle(Theme.accent)
                }
                Text("Ta position sert uniquement à ce calcul.").font(.barlow(11)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 4)
        }
    }

    // MARK: weather

    private var isWeatherAvailable: Bool {
        guard let start = event.startDate, event.address?.coordinate != nil else { return false }
        return ForecastService.isWithinHorizon(start)
    }

    @ViewBuilder
    private var weatherSection: some View {
        Group {
            if let weather {
                weatherCard(weather)
            } else if let weatherError {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("MÉTÉO")
                    Text("Météo indisponible").font(.barlow(15, .semibold)).foregroundStyle(Theme.textSoft)
                    Text(weatherError).font(.barlow(12)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                .card(radius: 24, padding: 16)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    /// Races time range (from call-up to finish): mine, otherwise all; `nil` if no times are known.
    private var racesTimeRange: DateInterval? {
        CalendarService.timeRange(event: event, races: (myRaces.isEmpty ? allRaces : myRaces).map(\.race))
    }

    private func weatherCard(_ day: WeatherSummary) -> some View {
        let m = racesTimeRange.map { day.during($0) } ?? day
        func degrees(_ t: Double) -> String { "\(Int(t.rounded()))°" }
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let temperature = Int(m.minTemp.rounded()) == Int(m.maxTemp.rounded())
            ? degrees(m.maxTemp) : "\(degrees(m.minTemp)) – \(degrees(m.maxTemp))"
        let rain = m.rainMm >= 0.1 ? String(format: "%.1f mm", m.rainMm).replacingOccurrences(of: ".", with: ",") : "Sec"
        let gusts = m.gustsKmh.map { "Rafales \(Int($0.rounded()))" } ?? "km/h"
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("MÉTÉO")
                Spacer()
                Text(m.timeRange.map { "\($0.start.formatted(time)) – \($0.end.formatted(time))" } ?? "Journée")
                    .font(.barlow(12, .semibold)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 14) {
                WeatherIcon(symbol: m.symbol, size: 44)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text(temperature).font(.cond(36)).foregroundStyle(Theme.text)
                    Text(m.condition).font(.barlow(15, .semibold)).foregroundStyle(Theme.textSoft)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                weatherTile(icon: "thermometer.medium", color: .orange, title: "TEMP.", value: degrees(m.maxTemp), detail: "min \(degrees(m.minTemp))")
                weatherTile(icon: "cloud.rain.fill", color: .blue, title: "PLUIE", value: "\(m.rainChance)%", detail: rain)
                weatherTile(icon: "wind", color: .teal, title: "VENT", value: "\(Int(m.windKmh.rounded()))", detail: gusts)
            }
            HStack(spacing: 10) {
                Text(m.timeRange == nil ? "Prévision pour le jour de l'épreuve" : "Prévision pendant la course")
                    .font(.barlow(12)).foregroundStyle(Theme.muted)
                Spacer()
                if let credits = weatherCredits {
                    VStack(alignment: .trailing, spacing: 2) {
                        // cards stay light even with forced dark mode: use the light-background logo
                        AsyncImage(url: credits.lightLogo) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                            .frame(height: 14)
                        Link("Autres sources de données", destination: credits.legalPage)
                            .font(.barlow(11)).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .padding(16)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }

    private func weatherTile(icon: String, color: Color, title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icon).symbolRenderingMode(.hierarchical).foregroundStyle(color)
                    .font(.system(size: 13, weight: .semibold))
                Text(title).font(.barlow(10, .semibold)).tracking(1).foregroundStyle(Theme.muted)
            }
            Text(value).font(.cond(26)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.barlow(11)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: header

    private var detailNavigationBar: some View {
        // back, event name (page title, wrapping if needed), then notifications / profile
        HStack(alignment: .top, spacing: 12) {
            HeaderCircleButton(systemImage: "chevron.left", label: "Retour") { dismiss() }
            Text(event.name)
                .font(.cond(28)).textCase(.uppercase).foregroundStyle(Theme.text)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            ProfileActions(photo: profilePhoto, accent: Theme.accent)
        }
        .padding(.top, 4)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let start = event.startDate {
                    Text(dateText(start)).font(.barlow(14, .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                WishlistButton(event: event, size: 22)
            }
            statusBanner
        }
    }

    private func dateText(_ start: Date) -> String {
        let f = Date.fr("EEEE d MMMM yyyy")
        var s = f.string(from: start).uppercased().replacingOccurrences(of: ".", with: ".")
        if let end = Date.fr("dd/MM/yyyy").date(from: event.endDateText), end > start {
            s += " → " + Date.fr("EEE d MMMM").string(from: end).uppercased()
        }
        return s
    }

    private func loadProfilePhoto() async {
        do {
            let profile = try await auth.withSession { try await auth.client.fetchProfile() }
            guard let url = profile.photoURL else { return }
            if let data = try? await auth.withSession({ try await auth.client.download(url) }) {
                profilePhoto = UIImage(data: data)
            }
        } catch {
            profilePhoto = nil
        }
    }

    // MARK: registration status

    private var status: RegistrationWindow {
        let now = Date()
        let start = Self.dateTimeText(event.registrationStartDate, event.registrationStartTime)
        let end = Self.dateTimeText(event.registrationEndDate, event.registrationEndTime)
        if let opensAt = Self.parse(event.registrationStartDate, event.registrationStartTime), now < opensAt {
            return .upcoming("Inscriptions ouvrent le \(start)")
        }
        if let closesAt = event.registrationClosesAt, now > closesAt {
            return .closed("Inscriptions fermées depuis le \(end)")
        }
        guard event.isOpenForRegistration == true else { return .closed("Inscriptions fermées") }
        return .open(end.isEmpty ? "Inscriptions ouvertes" : "Inscriptions ouvertes jusqu'au \(end)")
    }

    /// "18/11/2026 - 23:59"; date only if the time is missing.
    private static func dateTimeText(_ date: String?, _ time: String?) -> String {
        guard let date, !date.isEmpty else { return "" }
        guard let h = shortTime(time) else { return date }
        return "\(date) - \(h)"
    }

    /// "23:59:00" or "23:59" → "23:59".
    private static func shortTime(_ time: String?) -> String? {
        guard let h = time?.trimmingCharacters(in: .whitespaces), h.count >= 5 else { return nil }
        return String(h.prefix(5))
    }

    private static func parse(_ date: String?, _ time: String?) -> Date? {
        Event.registrationDate(date, time)
    }

    enum RegistrationWindow {
        case open(String), closed(String), upcoming(String)
    }

    @ViewBuilder
    private var statusBanner: some View {
        switch status {
        case .closed(let text):
            Label(text, systemImage: "lock.fill")
                .font(.barlow(13, .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.2), lineWidth: 1))
        default:
            RegistrationWindowBadge(status: status)
        }
    }

    // MARK: my race

    private func raceCard(_ race: Race, group: String) -> some View {
        let info = race.info
        let slot = CalendarService.slot(event: event, race: race, warmUpMinutes: warmUp)
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group).font(.barlow(13)).foregroundStyle(Theme.muted)
                Text(race.level.name).font(.cond(30)).textCase(.uppercase).foregroundStyle(Theme.text)
            }
            if info.isEmpty {
                Text("Horaires non communiqués").font(.barlow(14)).foregroundStyle(Theme.muted)
            } else {
                HStack(spacing: 0) {
                    stripColumn("ÉCHAUFF.", value: slot.map { $0.warmUp.formatted(time) } ?? "—", accent: .warning)
                    stripSeparator
                    stripColumn("APPEL", value: info.callTime ?? "—")
                    stripSeparator
                    stripColumn("DÉPART", value: info.startTime ?? "—", accent: .accent)
                    stripSeparator
                    stripColumn("TOURS", value: info.lapCount ?? info.km ?? "—", suffix: lapsSuffix(info))
                }
                .padding(10)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            if case .open = status { RegistrationSection(event: event, race: race) }
            if showsCalendarButton, let slot { calendarButton(race: race, slot: slot) }
        }
        .padding(18)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func tile(_ title: String, _ value: String, accent: Bool = false, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(title).font(.cond(11, .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value).font(.cond(34)).foregroundStyle(accent ? Theme.accent : Theme.text)
                if let suffix { Text(suffix).font(.cond(15, .semibold)).foregroundStyle(Theme.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var stripSeparator: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 46)
            .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func stripColumn(_ title: String, value: String, accent: ColumnAccent? = nil, suffix: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.barlow(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(accent?.color ?? Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.barlow(17, .semibold))
                    .foregroundStyle(accent?.color ?? Theme.text)
                    .lineLimit(1)
                if let suffix {
                    Text(suffix)
                        .font(.barlow(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lapsSuffix(_ info: Race.Info) -> String? {
        if info.lapCount != nil { return info.lapDistance.map { "× \($0) km" } }
        if info.km != nil { return "km" }
        return nil
    }

    private func durationText(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    // MARK: calendar

    @ViewBuilder
    private func calendarButton(race: Race, slot: CalendarService.TimeSlot) -> some View {
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let timeRange = "\(slot.start.formatted(time)) – \(slot.end.formatted(time))"
        let isAdded = calendarStore.isAdded(event: event.id, race: race.id)
        VStack(spacing: 10) {
            if isAdded {
                HStack(spacing: 12) {
                    Label("Inscrit à l'agenda (\(timeRange))", systemImage: "checkmark.circle.fill")
                        .font(.barlow(13, .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if event.address?.coordinate != nil {
                        Button {
                            updateTravelTime(race)
                        } label: {
                            Label("TRAJET", systemImage: "car")
                                .font(.barlow(12, .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        .buttonStyle(.plain)
                        .disabled(isUpdatingTravelTime)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ActionRow(title: "Ajouter à l'agenda", subtitle: "\(timeRange) · \(includedItemsText)",
                          icon: "calendar.badge.plus") { addToCalendar(race) }
            }
            if let calendarInfo { Text(calendarInfo).font(.barlow(13)).foregroundStyle(Theme.accent) }
            if let calendarError { Text(calendarError).font(.barlow(13)).foregroundStyle(Theme.danger) }
        }
    }

    /// What the event will contain; travel time is only included if location is already authorized.
    private var includedItemsText: String {
        var elements = ["lieu"]
        if event.gpxURL != nil { elements.append("tracé GPX") }
        if travelTime != nil || TravelTimeService.isAuthorized { elements.append("trajet") }
        return elements.formatted(.list(type: .and, width: .standard).locale(Locale(identifier: "fr_FR"))) + " inclus"
    }

    private func addToCalendar(_ race: Race) {
        calendarError = nil
        calendarInfo = nil
        Task {
            do {
                // travel time: only if location is already authorized (no new prompt when adding)
                if travelTime == nil, TravelTimeService.isAuthorized { await computeTravelTime() }
                let id = try await CalendarService.addToCalendar(event: event, race: race, warmUpMinutes: warmUp, travelTime: travelTime)
                calendarStore.save(event: event.id, race: race.id, identifier: id)
                if travelTime == nil {
                    calendarInfo = "Événement créé sans temps de trajet. "
                        + (travelTimeError ?? "Touche « Mettre à jour le temps de trajet » pour l'ajouter (la position est demandée une seule fois).")
                }
            } catch {
                calendarError = error.localizedDescription
            }
        }
    }

    /// Recomputes travel time from my current location and updates the already-created event.
    private func updateTravelTime(_ race: Race) {
        calendarError = nil
        calendarInfo = nil
        guard let c = event.address?.coordinate,
              let identifier = calendarStore.identifier(event: event.id, race: race.id) else { return }
        isUpdatingTravelTime = true
        Task {
            defer { isUpdatingTravelTime = false }
            let updated: TravelTime
            do {
                updated = try await TravelTimeService.travelTime(toLatitude: c.latitude, longitude: c.longitude)
            } catch {
                calendarError = error.localizedDescription
                return
            }
            travelTime = updated
            do {
                let update = try await CalendarService.updateTravelTimeInEvents(identifier: identifier, event: event, race: race,
                                                                   warmUpMinutes: warmUp, travelTime: updated)
                if !update.identifier.isEmpty { calendarStore.save(event: event.id, race: race.id, identifier: update.identifier) }
                let location = update.calendarNames.joined(separator: ", ")
                calendarInfo = "Trajet mis à jour : \(updated.text). \(update.count) événement\(update.count > 1 ? "s" : "") modifié\(update.count > 1 ? "s" : "") (calendrier « \(location) »)."
            } catch CalendarError.eventNotFound {
                calendarStore.remove(event: event.id, race: race.id)
                calendarError = CalendarError.eventNotFound.localizedDescription
            } catch {
                calendarError = error.localizedDescription
            }
        }
    }

    // MARK: location and track

    private var locationAndTrack: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("LIEU ET TRACÉ")
            if let address = event.address {
                VStack(spacing: 0) {
                    locationMap(address: address)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !address.street.isEmpty { Text(address.street.capitalized).font(.barlow(15, .semibold)).foregroundStyle(Theme.text) }
                            Text((address.city ?? "").capitalized).font(.barlow(15, .semibold)).foregroundStyle(Theme.text)
                            Text(address.postalCode ?? "")
                                .font(.barlow(14)).foregroundStyle(Theme.muted)
                            travelTimeRow
                        }
                        Spacer()
                        if let c = address.coordinate {
                            Link(destination: URL(string: "http://maps.apple.com/?ll=\(c.latitude),\(c.longitude)&q=\(event.name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                                Text("Ouvrir dans Plans").font(.cond(13, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            if let track {
                if track.hasElevationProfile { elevationProfile(track) }
                if let gpxFile {
                    ShareLink(item: gpxFile) {
                        ActionRowLabel(title: "Tracé GPX", subtitle: "Télécharger ou envoyer vers une app GPS", icon: "arrow.down.circle")
                    }
                    .buttonStyle(ActionRowStyle())
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Pas de tracé fourni", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.cond(18, .semibold)).tracking(1).textCase(.uppercase).foregroundStyle(Theme.textSoft)
                    Text("L'organisateur n'a pas publié de fichier GPX.").font(.barlow(14)).foregroundStyle(Theme.muted)
                }
                .card(padding: 16)
            }
        }
    }

    @ViewBuilder
    private func locationMap(address: Event.Address) -> some View {
        if let c = address.coordinate {
            let center = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
            Map(initialPosition: region(center: center)) {
                if let track {
                    MapPolyline(coordinates: track.coordinates).stroke(Theme.accent, lineWidth: 4)
                    if let departure = track.coordinates.first {
                        Annotation("Départ · arrivée", coordinate: departure) {
                            Circle().fill(Theme.accent).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                        }
                    }
                } else {
                    // no track: always show the pin of the start location
                    Marker(event.name.capitalized, coordinate: center).tint(Theme.accent)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 200)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                if let track {
                    Text("TRACÉ GPX · \(track.distanceKm.formatted(.number.precision(.fractionLength(1)))) KM")
                        .font(.cond(12, .semibold)).tracking(1.5).foregroundStyle(Theme.bg)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Theme.accent, in: Capsule()).padding(12)
                } else {
                    Text("LIEU DE DÉPART").font(.cond(12, .semibold)).tracking(1.5).foregroundStyle(Theme.text)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(.black.opacity(0.6), in: Capsule()).padding(12)
                }
            }
        } else {
            ZStack {
                Theme.surface2
                Text("Plan indisponible").font(.barlow(14)).foregroundStyle(Theme.muted)
            }
            .frame(height: 120)
        }
    }

    private func region(center: CLLocationCoordinate2D) -> MapCameraPosition {
        if let track, track.coordinates.count > 1 {
            return .rect(MKMapRect(coordinates: track.coordinates).insetBy(dx: -500, dy: -500))
        }
        return .region(MKCoordinateRegion(center: center, latitudinalMeters: 3000, longitudinalMeters: 3000))
    }

    private func elevationProfile(_ track: GPXTrack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("PROFIL ALTIMÉTRIQUE")
            Chart(Array(track.points.enumerated()), id: \.offset) { _, p in
                if let alt = p.altitude {
                    AreaMark(x: .value("Distance", p.distanceKm), y: .value("Altitude", alt))
                        .foregroundStyle(Theme.accent.opacity(0.18))
                    LineMark(x: .value("Distance", p.distanceKm), y: .value("Altitude", alt))
                        .foregroundStyle(Theme.accent)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks { v in AxisValueLabel { if let d = v.as(Double.self) { Text("\(d.formatted(.number.precision(.fractionLength(0)))) km").foregroundStyle(Theme.muted) } } } }
            .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(Theme.line); AxisValueLabel().foregroundStyle(Theme.muted) } }
            .frame(height: 140)
            HStack(spacing: 10) {
                tile("D+", track.elevationGain.formatted(.number.precision(.fractionLength(0))), suffix: "m")
                tile("ALT. MAX", (track.maxAltitude ?? 0).formatted(.number.precision(.fractionLength(0))), suffix: "m")
                tile("ALT. MIN", (track.minAltitude ?? 0).formatted(.number.precision(.fractionLength(0))), suffix: "m")
            }
        }
        .card(radius: 24, padding: 16)
    }

    // MARK: other races

    private var otherRacesSection: some View {
        VStack(spacing: 0) {
            Button { withAnimation { othersExpanded.toggle() } } label: {
                HStack {
                    Text("Autres courses").font(.cond(17, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.text)
                    Text("(\(others.count))").font(.cond(17, .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(othersExpanded ? 180 : 0))
                }
                .padding(18)
            }
            .buttonStyle(.plain)
            if othersExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groups) { group in
                        let rows = others.filter { $0.group == group.name }
                        if !rows.isEmpty {
                            Eyebrow(group.name).padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
                            ForEach(rows, id: \.race.id) { otherRaceRow($0) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func otherRaceRow(_ item: (group: String, race: Race)) -> some View {
        let info = item.race.info
        let slot = CalendarService.slot(event: event, race: item.race, warmUpMinutes: warmUp)
        let isAdded = calendarStore.isAdded(event: event.id, race: item.race.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.race.level.name).font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                Text(info.isEmpty ? "Horaires non communiqués" : [info.callTime.map { "Appel \($0)" }, info.startTime.map { "Départ \($0)" }, info.lapCount.map { n in info.lapDistance.map { "\(n) × \($0) km" } ?? "\(n) tours" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if showsCalendarButton, slot != nil {
                Button { addToCalendar(item.race) } label: {
                    Image(systemName: isAdded ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(isAdded ? Theme.accent : Theme.textSoft)
                        .frame(width: 44, height: 44)
                }
                .disabled(isAdded)
                .accessibilityLabel(isAdded ? "Déjà dans l'agenda" : "Ajouter à l'agenda")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
    }
}

private struct RegistrationWindowBadge: View {
    let status: EventDetailView.RegistrationWindow

    var body: some View {
        let (text, color, icon): (String, Color, String) = switch status {
        case .open(let t): (t, Theme.accent, "checkmark.circle")
        case .closed(let t): (t, Theme.danger, "xmark.circle")
        case .upcoming(let t): (t, Theme.warning, "clock")
        }
        Label(text, systemImage: icon)
            .font(.barlow(14, .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(color.opacity(0.14), in: Capsule())
    }
}

private extension MKMapRect {
    init(coordinates: [CLLocationCoordinate2D]) {
        var rect = MKMapRect.null
        for c in coordinates {
            let p = MKMapPoint(c)
            rect = rect.union(MKMapRect(x: p.x, y: p.y, width: 0, height: 0))
        }
        self = rect
    }
}

private enum WeatherDiagnostic: LocalizedError {
    case unreadableDate(String), noCoordinates
    var errorDescription: String? {
        switch self {
        case .unreadableDate(let d): "Date de début illisible : « \(d) »."
        case .noCoordinates: "Pas de coordonnées exploitables pour ce lieu."
        }
    }
}

private enum ColumnAccent {
    case accent
    case warning

    var color: Color {
        switch self {
        case .accent: Theme.accent
        case .warning: Theme.warning
        }
    }
}
