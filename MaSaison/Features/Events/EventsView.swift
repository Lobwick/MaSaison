import Combine
import CoreLocation
import MapKit
import SwiftUI

struct EventsView: View {
    enum ViewMode: String, CaseIterable, Identifiable {
        case list, map, calendar
        var id: String { rawValue }
        var title: String {
            switch self {
            case .list: "Liste"
            case .map: "Carte"
            case .calendar: "Calendrier"
            }
        }
    }

    @Environment(AuthModel.self) private var auth
    @Environment(FilterStore.self) private var store
    @Environment(LicenseCardStore.self) private var cardStore
    @Environment(RaceTrackingStore.self) private var tracking
    @AppStorage("hideFloatingTabBar") private var hideFloatingTabBar = false
    private let showsViewPicker: Bool
    private let showsSearch: Bool
    @State private var selectedMode: ViewMode = .list
    @State private var departmentIDs: Set<Int> = []
    @State private var sportCodes: Set<String> = []
    @State private var filtersInitialized = false
    @State private var searchText = ""
    @FocusState private var isSearchFocused: Bool
    @State private var events: [Event] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showsFilterPanel = false
    // pagination: the site accepts only one sport at a time, so we track the next page of each sport not yet exhausted
    @State private var nextPage = 1
    @State private var remainingSports: [String?] = [nil]
    @State private var isLoadingMore = false
    @State private var generation = 0
    @State private var selectedPinID: String?
    @State private var currentMonth = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: Date())) ?? Calendar.current.startOfDay(for: Date())
    @State private var selectedDay = Calendar.current.startOfDay(for: Date())
    @State private var mapPosition: MapCameraPosition = .region(Self.franceRegion)
    @State private var didCenterOnUser = false
    @StateObject private var locationProvider = MapLocationProvider()
    @State private var previewTravelTime: TravelTime?
    @State private var isComputingPreviewTravelTime = false
    @State private var previewTravelTimeError: String?
    @State private var previewTravelTimeEventID: Int?
    @State private var calendarPopupDay: Date?
    @State private var weekRowPositions: [WeekRowPosition] = []
    @State private var calendarViewportHeight: CGFloat = 0
    @State private var isPrefetchingCalendar = false
    @State private var statusFilter: StatusFilter = .all
    @State private var photo: UIImage?
    /// False until a load has succeeded: avoids announcing "no event" before searching.
    @State private var hasLoadedOnce = false

    private struct SearchQuery: Equatable {
        var departmentIDs: Set<Int>
        var sportCodes: Set<String>
        var searchText: String
        /// Default filters are applied in `onAppear`: nothing is queried before that.
        var filtersReady: Bool
    }

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all
        case wishlist
        case registered
        case confirmed
        var id: String { rawValue }
    }

    private var isFullScreenMap: Bool { !showsViewPicker && selectedMode == .map }
    private var isFullScreenCalendar: Bool { !showsViewPicker && selectedMode == .calendar }
    private var activeFilterCount: Int { (departmentIDs.isEmpty ? 0 : 1) + (sportCodes.isEmpty ? 0 : 1) }
    private var screenTitle: String {
        if showsViewPicker { return "Manifestations" }
        switch selectedMode {
        case .list: return "Courses"
        case .map: return "Carte"
        case .calendar: return "Calendrier"
        }
    }

    init(initialMode: ViewMode = .list, showsViewPicker: Bool = true, showsSearch: Bool = true) {
        self.showsViewPicker = showsViewPicker
        self.showsSearch = showsSearch
        _selectedMode = State(initialValue: initialMode)
    }

    var body: some View {
        Group {
            if isFullScreenMap {
                mapView
            } else if isFullScreenCalendar {
                calendarView
            } else {
                ScrollView(.vertical) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if selectedMode == .list && !showsViewPicker {
                            searchHeader
                        } else {
                            TitleAndProfileActions(title: screenTitle, photo: photo, accent: Theme.accent)
                            .padding(.top, -4)

                            HStack(spacing: 10) {
                                if showsSearch {
                                    HStack(spacing: 10) {
                                        Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                                        TextField("", text: $searchText, prompt: Text("Nom de la manifestation").foregroundStyle(Theme.muted))
                                            .font(.barlow(15)).foregroundStyle(Theme.text)
                                            .autocorrectionDisabled()
                                    }
                                    .padding(.horizontal, 14).frame(height: 48)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
                                } else {
                                    Spacer(minLength: 0)
                                }
                                filterButton
                            }
                        }

                        if showsViewPicker {
                            Picker("Vue", selection: $selectedMode) {
                                ForEach(ViewMode.allCases) { mode in
                                    Text(mode.title).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.top, 2)
                        }

                        selectedContent

                        if selectedMode == .list && !remainingSports.isEmpty && !events.isEmpty && errorMessage == nil {
                            ProgressView().tint(Theme.accent)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .onAppear { Task { await loadMore() } }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 120)
                    .containerRelativeFrame(.horizontal)
                }
            }
        }
        .overlay { stateOverlay }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsFilterPanel) {
            FilterPanel(departments: $departmentIDs, sports: $sportCodes)
        }
        .refreshable { await auth.client.bypassingCache { await load() } }
        // back from a detail page: the registration may have changed
        .onAppear {
            Task { await refreshTracking() }
            // profile default filters, applied once on appear
            if !filtersInitialized { departmentIDs = store.defaultDepartments; sportCodes = store.defaultSports; filtersInitialized = true }
        }
        // a change in the profile overwrites the current selection
        .onChange(of: store.defaultDepartments) { _, newValues in
            applyDefaultDepartments(newValues)
        }
        .onChange(of: store.defaultSports) { _, newValues in
            applyDefaultSports(newValues)
        }
        .onChange(of: selectedMode) { _, newMode in
            handleViewModeChange(newMode)
        }
        .onChange(of: showsFilterPanel) { _, _ in
            updateTabBarVisibility()
        }
        .onChange(of: selectedPinID) { _, _ in
            updateTabBarVisibility()
        }
        .onChange(of: calendarPopupDay) { _, _ in
            updateTabBarVisibility()
        }
        .task(id: selectedMode) {
            if selectedMode == .calendar {
                await prefetchCalendarIfNeeded(through: currentMonth)
            }
        }
        .task(id: currentMonth) {
            if selectedMode == .calendar {
                await prefetchCalendarIfNeeded(through: currentMonth)
            }
        }
        .onChange(of: eventIDs) { _, _ in
            syncSelectedDay()
        }
        .onReceive(locationProvider.$position) { position in
            handleUserLocation(position)
        }
        .task(id: SearchQuery(departmentIDs: departmentIDs, sportCodes: sportCodes, searchText: searchText, filtersReady: filtersInitialized)) {
            guard filtersInitialized else { return }
            // debounce only typing and filter changes: the first load starts immediately
            if hasLoadedOnce {
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
            }
            await load()
        }
        .task { await loadProfilePhoto() }
        .onAppear { updateTabBarVisibility() }
        .onDisappear { hideFloatingTabBar = false }
    }

    private var filterButton: some View {
        let showActiveState = !isFullScreenMap && !isFullScreenCalendar
        return Button { showsFilterPanel = true } label: {
            Image(systemName: "slider.horizontal.3").font(.system(size: 20, weight: .semibold))
                .foregroundStyle(showActiveState && activeFilterCount > 0 ? Theme.accent : Theme.text)
                .frame(width: 48, height: 48)
                .background(showActiveState && activeFilterCount > 0 ? Theme.accent.opacity(0.13) : Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(showActiveState && activeFilterCount > 0 ? Theme.accent : Theme.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if showActiveState && activeFilterCount > 0 {
                        Text("\(activeFilterCount)").font(.cond(13)).foregroundStyle(Theme.bg)
                            .frame(minWidth: 20, minHeight: 20).background(Theme.accent, in: Capsule())
                            .offset(x: 7, y: -7)
                    }
                }
        }
        .accessibilityLabel("Filtres, \(activeFilterCount) actif(s)")
    }

    @ViewBuilder
    private var selectedContent: some View {
        switch selectedMode {
        case .list:
            listView
        case .map:
            mapView
        case .calendar:
            calendarView
        }
    }

    @ViewBuilder
    private var stateOverlay: some View {
        if (isLoading || !hasLoadedOnce) && events.isEmpty && errorMessage == nil {
            ProgressView().tint(Theme.accent)
        } else if let errorMessage {
            ContentUnavailableView("Erreur", systemImage: "exclamationmark.triangle", description: Text(errorMessage))
        } else if !isLoading && hasLoadedOnce && events.isEmpty {
            ContentUnavailableView("Aucune manifestation", systemImage: "flag.slash",
                                   description: Text(activeFilterCount > 0 ? "Essayez de retirer un filtre." : ""))
        }
    }

    private var cardsSummary: String {
        var parts: [String] = []
        for card in cardStore.activeCards {
            let level = card.level?
                .replacingOccurrences(of: "ème catégorie", with: "e")
                .replacingOccurrences(of: "ère catégorie", with: "re")
            let age = card.ageCategory?.split(separator: " ").last.map(String.init)
            let detail = level ?? age
            parts.append([card.discipline, detail].compactMap { $0 }.joined(separator: " "))
        }
        return parts.joined(separator: " · ")
    }

    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            TitleAndProfileActions(title: "COURSES", photo: photo, accent: Theme.accent)
            .padding(.top, -4)

            HStack(spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                    TextField("", text: $searchText, prompt: Text("Nom de la manifestation").foregroundStyle(Theme.muted))
                        .focused($isSearchFocused)
                        .font(.barlow(15))
                        .foregroundStyle(Theme.text)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(Theme.faint)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(isSearchFocused ? Theme.accent : Theme.line, lineWidth: isSearchFocused ? 2 : 1)
                )
                filterButton
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    statusChip(.all, text: "Tous", icon: nil, color: Theme.text, fill: Theme.text, textColor: Theme.bg)
                    statusChip(.wishlist, text: "Envies (\(tracking.wishlistIDs.count))", icon: "bookmark.fill", color: Theme.wishlist, fill: Theme.wishlist.opacity(0.12), textColor: Theme.wishlist)
                    statusChip(.registered, text: "Inscrit (\(tracking.registeredIDs.count))", icon: "hourglass", color: Theme.secondary, fill: Theme.secondary.opacity(0.12), textColor: Theme.secondary)
                    statusChip(.confirmed, text: "Validé (\(tracking.confirmedIDs.count))", icon: "checkmark.circle.fill", color: Theme.accent, fill: Theme.accent.opacity(0.12), textColor: Theme.accent)
                }
                .padding(.horizontal, 1)
            }
        }
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

    private var emptyListMessage: String {
        switch statusFilter {
        case .all: "Aucune course trouvée avec les filtres actifs."
        case .wishlist: "Aucune course de ta liste d'envies avec les filtres actifs. Touche le signet d'une course pour l'ajouter."
        case .registered: "Aucune inscription en attente de paiement avec les filtres actifs."
        case .confirmed: "Aucune inscription validée avec les filtres actifs."
        }
    }

    private var listView: some View {
        let source = switch statusFilter {
        case .all: events
        case .wishlist: events.filter { tracking.status($0.id) == .wishlist }
        case .registered: events.filter { tracking.status($0.id) == .registered }
        case .confirmed: events.filter { tracking.status($0.id) == .confirmed }
        }
        let forMe = source.filter(cardStore.matches)
        let others = source.filter { !cardStore.matches($0) }
        return Group {
            if !forMe.isEmpty {
                HStack(alignment: .firstTextBaseline) {
                    Eyebrow("POUR MOI", color: Theme.accent)
                    Spacer()
                    Text(cardsSummary).font(.barlow(13)).foregroundStyle(Theme.muted)
                }
                ForEach(forMe) { row($0) }
            }
            if !others.isEmpty {
                Eyebrow(forMe.isEmpty ? "\(source.count) manifestation(s)" : "Autres (\(others.count))")
                    .padding(.top, 4)
                ForEach(others) { row($0) }
            }
            if source.isEmpty {
                Text(emptyListMessage)
                    .font(.barlow(14))
                    .foregroundStyle(Theme.muted)
                    .card(padding: 14)
            }
        }
    }

    private var mapPins: [MapPin] {
        MapPin.cluster(events.compactMap { m in
            guard let c = m.address?.coordinate else { return nil }
            return MapPin.Element(event: m, latitude: c.latitude, longitude: c.longitude)
        })
    }

    private var eventIDs: [Int] {
        events.map(\.id)
    }

    private var selectedPin: MapPin? {
        guard let selectedPinID else { return nil }
        return mapPins.first { $0.id == selectedPinID }
    }

    private var mapPinIDs: [String] {
        mapPins.map(\.id)
    }

    private var mapView: some View {
        Group {
            if isFullScreenMap {
                ZStack(alignment: .top) {
                    Map(position: $mapPosition) {
                        mapPinAnnotations
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .bottom)

                    VStack(alignment: .leading, spacing: 8) {
                        TitleAndProfileActions(title: screenTitle, photo: photo, accent: Theme.accent)
                        HStack {
                            Spacer()
                            mapFilterButton
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            mapControlButton(systemImage: "location.fill", label: "Me recentrer") {
                                guard let position = locationProvider.position else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    mapPosition = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 24_000, longitudinalMeters: 24_000))
                                }
                            }
                            mapControlButton(systemImage: "safari", label: "Nord") {
                                guard let position = locationProvider.position else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    mapPosition = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 70_000, longitudinalMeters: 70_000))
                                }
                            }
                            mapControlButton(systemImage: "square.stack.3d.up", label: "Style de carte") {
                                // Visual placeholder matching the Stitch mockup; style is already handled by MapKit.
                            }
                        }
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 130)
                }
                .safeAreaInset(edge: .bottom) {
                    if let selectedPin {
                        mapPopup(selectedPin)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    Text("Plans · Données UFOLEP")
                        .font(.barlow(10))
                        .foregroundStyle(Theme.muted.opacity(0.8))
                        .padding(.leading, 12)
                        .padding(.bottom, 8)
                }
                .onAppear {
                    locationProvider.start()
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Eyebrow("AUTOUR DE MOI", color: Theme.accent)
                        Spacer()
                        if locationProvider.position != nil {
                            Text("Position détectée").font(.barlow(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    Map(position: $mapPosition) {
                        mapPinAnnotations
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay { RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1) }
                    .onAppear {
                        locationProvider.start()
                        if selectedPinID == nil { selectedPinID = mapPins.first?.id }
                    }
                    if let selectedPin {
                        preview(selectedPin)
                    } else {
                        Text("Touchez un marqueur pour afficher un aperçu.")
                            .font(.barlow(13))
                            .foregroundStyle(Theme.muted)
                            .card(padding: 14)
                    }
                }
            }
        }
        .onChange(of: mapPinIDs) { _, ids in
            if ids.contains(selectedPinID ?? "") { return }
            selectedPinID = isFullScreenMap ? nil : ids.first
        }
        .task(id: selectedPinID) {
            await refreshPreviewTravelTime()
        }
    }

    @MapContentBuilder
    private var mapPinAnnotations: some MapContent {
        ForEach(mapPins) { point in
            Annotation("", coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)) {
                Button {
                    selectedPinID = point.id
                } label: {
                    if point.events.count == 1 {
                        VStack(spacing: 4) {
                            if let date = point.events.first?.startDate {
                                HStack(spacing: 4) {
                                    Circle().fill(Theme.accent).frame(width: 5, height: 5)
                                    Text(Date.fr("d MMM").string(from: date).capitalized)
                                        .font(.barlow(10, .semibold))
                                        .foregroundStyle(Theme.text)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Theme.surface, in: Capsule())
                            }
                            ZStack {
                                Circle()
                                    .fill(Theme.accent)
                                    .frame(width: selectedPinID == point.id ? 46 : 36, height: selectedPinID == point.id ? 46 : 36)
                                Image(systemName: "bicycle")
                                    .font(.system(size: selectedPinID == point.id ? 18 : 15, weight: .bold))
                                    .foregroundStyle(Theme.bg)
                            }
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                            .shadow(color: Theme.accent.opacity(0.35), radius: 10, x: 0, y: 4)
                        }
                    } else {
                        ZStack {
                            Circle().fill(Theme.accent).frame(width: 34, height: 34)
                            Text("\(point.events.count)")
                                .font(.cond(14, .semibold))
                                .foregroundStyle(Theme.bg)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        if locationProvider.position != nil { UserAnnotation() }
    }

    private var mapFilterButton: some View {
        Button { showsFilterPanel = true } label: {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.barlow(10, .semibold))
                            .foregroundStyle(Theme.bg)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Theme.accent, in: Capsule())
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filtres, \(activeFilterCount) actif(s)")
    }

    private func mapControlButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSoft)
                .frame(width: 40, height: 40)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func mapPopup(_ point: MapPin) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(point.events.count == 1 ? "APERÇU" : "\(point.events.count) COURSES PROCHES")
                    .font(.cond(14, .semibold)).tracking(1.4).foregroundStyle(Theme.muted)
                Spacer()
                Button {
                    selectedPinID = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if point.events.count == 1, let event = point.events.first {
                Text(event.name).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                Text([event.address?.city?.capitalized, event.kind?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(14)).foregroundStyle(Theme.muted)
                previewTravelTimeRow(event)
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    ActionRowLabel(title: "Ouvrir la fiche", subtitle: "Courses, horaires, météo et tracé", icon: "doc.text.magnifyingglass", tone: .primary)
                }
                .buttonStyle(ActionRowStyle())
            } else {
                ForEach(Array(point.events.prefix(4))) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        HStack(spacing: 10) {
                            DateBlock(date: event.startDate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.name).font(.cond(15, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                                Text(event.address?.city?.capitalized ?? "Lieu inconnu").font(.barlow(12)).foregroundStyle(Theme.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if point.events.count > 4 {
                    Text("… et \(point.events.count - 4) autre(s)").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 16, y: 4)
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private func preview(_ point: MapPin) -> some View {
        if point.events.count == 1, let event = point.events.first {
            VStack(alignment: .leading, spacing: 8) {
                Eyebrow("APERÇU")
                Text(event.name).font(.cond(20, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                Text([event.address?.city?.capitalized, event.kind?.name].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(13)).foregroundStyle(Theme.muted)
                previewTravelTimeRow(event)
                NavigationLink {
                    EventDetailView(event: event)
                } label: {
                    ActionRowLabel(title: "Ouvrir la fiche", subtitle: "Courses, horaires, météo et tracé", icon: "doc.text.magnifyingglass", tone: .primary)
                }
                .buttonStyle(ActionRowStyle())
            }
            .card(radius: 20, padding: 14)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("\(point.events.count) COURSES PROCHES")
                ForEach(Array(point.events.prefix(5))) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        HStack(spacing: 10) {
                            DateBlock(date: event.startDate)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.name).font(.cond(15, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                                Text(event.address?.city?.capitalized ?? "Lieu inconnu").font(.barlow(12)).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                    }
                    .buttonStyle(.plain)
                }
                if point.events.count > 5 {
                    Text("… et \(point.events.count - 5) autre(s)").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
            }
            .card(radius: 20, padding: 14)
        }
    }

    @ViewBuilder
    private func previewTravelTimeRow(_ event: Event) -> some View {
        if previewTravelTimeEventID == event.id, let previewTravelTime {
            Label(previewTravelTime.text, systemImage: "car.fill")
                .font(.barlow(13, .semibold))
                .foregroundStyle(Theme.accent)
        } else if previewTravelTimeEventID == event.id, isComputingPreviewTravelTime {
            ProgressView().controlSize(.small)
        } else if previewTravelTimeEventID == event.id, let previewTravelTimeError {
            Text(previewTravelTimeError).font(.barlow(12)).foregroundStyle(Theme.danger)
        } else if previewTravelTimeEventID == event.id, TravelTimeService.isNotDetermined, event.address?.coordinate != nil {
            Button {
                Task { await computePreviewTravelTime(event) }
            } label: {
                Label("Afficher le temps de trajet", systemImage: "car.fill")
                    .font(.barlow(13, .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.accent)
        }
    }

    private var calendarView: some View {
        Group {
            if isFullScreenCalendar {
                ScrollViewReader { proxy in
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 14) {
                            TitleAndProfileActions(title: screenTitle, photo: photo, accent: Theme.accent)
                            HStack(alignment: .center, spacing: 10) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(Self.monthNameFormatter.string(from: currentMonth))
                                        .font(.cond(26, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                                    Text(String(Calendar.current.component(.year, from: currentMonth)))
                                        .font(.barlow(12, .semibold)).tracking(1).foregroundStyle(Theme.muted)
                                }
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: currentMonth)
                                Spacer()
                                todayButton {
                                    let today = Calendar.current.startOfDay(for: Date())
                                    let month = Self.startOfMonth(today)
                                    selectedDay = today
                                    currentMonth = month
                                    calendarPopupDay = nil
                                    withAnimation(.easeInOut(duration: 0.25)) {
                                        proxy.scrollTo(monthKey(month), anchor: .top)
                                    }
                                }
                                filterButton
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                        HStack(spacing: 0) {
                            ForEach(Array(Self.weekdaySymbols.enumerated()), id: \.offset) { index, day in
                                Text(day)
                                    .font(.barlow(11, .semibold)).tracking(1)
                                    .foregroundStyle(index >= 5 ? Theme.faint : Theme.muted)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }

                        GeometryReader { container in
                            ScrollView(.vertical) {
                                LazyVStack(alignment: .leading, spacing: 10) {
                                    ForEach(calendarMonths, id: \.self) { month in
                                        VStack(alignment: .leading, spacing: 0) {
                                            let rows = weeksOfMonth(month)
                                            if month != calendarMonths.first {
                                                monthLabelRow(
                                                    name: Self.monthNameFormatter.string(from: month).capitalized,
                                                    column: firstWeekdayColumn(month)
                                                )
                                            }
                                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                                                let reference = month
                                                weekRow(cells: row)
                                                    .background {
                                                        GeometryReader { geo in
                                                            let frame = geo.frame(in: .named("calendar-scroll"))
                                                            Color.clear.preference(
                                                                key: WeekRowPositionKey.self,
                                                                value: [WeekRowPosition(date: reference, minY: frame.minY, maxY: frame.maxY)]
                                                            )
                                                        }
                                                    }
                                            }
                                        }
                                        .id(monthKey(month))
                                    }
                                }
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 24)
                            .coordinateSpace(name: "calendar-scroll")
                            .onAppear {
                                calendarViewportHeight = container.size.height
                            }
                            .onChange(of: container.size.height) { _, newHeight in
                                calendarViewportHeight = newHeight
                            }
                            .onPreferenceChange(WeekRowPositionKey.self) { positions in
                                weekRowPositions = positions
                                updateVisibleMonthFromScroll()
                            }
                        }
                    }
                    .onAppear {
                        currentMonth = Self.startOfMonth(selectedDay)
                        let month = Self.startOfMonth(Date())
                        DispatchQueue.main.async {
                            proxy.scrollTo(monthKey(month), anchor: .top)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    if let calendarPopupDay {
                        calendarPopup(calendarPopupDay)
                            .padding(.horizontal, 10)
                            .padding(.top, 8)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        IconButton(systemImage: "chevron.left", label: "Mois précédent") {
                            if let previous = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) {
                                currentMonth = Self.startOfMonth(previous)
                                clampSelectedDayToMonth()
                            }
                        }
                        Spacer(minLength: 0)
                        Text(Self.monthYearFormatter.string(from: currentMonth)).font(.cond(24, .semibold)).textCase(.uppercase).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                        IconButton(systemImage: "chevron.right", label: "Mois suivant") {
                            if let nextMonth = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) {
                                currentMonth = Self.startOfMonth(nextMonth)
                                clampSelectedDayToMonth()
                            }
                        }
                    }
                    .padding(.bottom, 2)

                    calendarGrid

                    let races = eventsOnDay(selectedDay)
                    Eyebrow("COURSES DU \(Self.longDayFormatter.string(from: selectedDay).uppercased())",
                            color: races.isEmpty ? Theme.muted : Theme.accent)
                    if races.isEmpty {
                        Text("Aucune course ce jour-là avec les filtres actifs.")
                            .font(.barlow(14))
                            .foregroundStyle(Theme.muted)
                            .card(padding: 14)
                    } else {
                        ForEach(races) { event in
                            row(event)
                        }
                    }
                }
            }
        }
        .onAppear { clampSelectedDayToMonth() }
    }

    private var calendarMonths: [Date] {
        let cal = Calendar.current
        let anchorMonth = Self.startOfMonth(Date())
        return (-18...18).compactMap { offset in
            cal.date(byAdding: .month, value: offset, to: anchorMonth).map(Self.startOfMonth)
        }
    }

    private func weeksOfMonth(_ month: Date) -> [[Date?]] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: month),
              let daysInMonth = cal.range(of: .day, in: .month, for: interval.start) else { return [] }
        let prefix = firstWeekdayColumn(interval.start)
        let total = prefix + daysInMonth.count
        let rows = Int(ceil(Double(total) / 7.0))
        var result: [[Date?]] = []
        for row in 0..<rows {
            var cells: [Date?] = []
            for column in 0..<7 {
                let index = row * 7 + column
                let dayNumber = index - prefix + 1
                if dayNumber >= 1 && dayNumber <= daysInMonth.count,
                   let date = cal.date(byAdding: .day, value: dayNumber - 1, to: interval.start) {
                    cells.append(date)
                } else {
                    cells.append(nil)
                }
            }
            result.append(cells)
        }
        return result
    }

    private func firstWeekdayColumn(_ date: Date) -> Int {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        return (weekday + 5) % 7 // Monday = 0
    }

    private func weekRow(cells: [Date?]) -> some View {
        let cal = Calendar.current
        return HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                if let date = cells[index] {
                    let races = eventsOnDay(date)
                    let selection = cal.isDate(date, inSameDayAs: selectedDay)
                    let isToday = cal.isDateInToday(date)
                    Button {
                        let day = cal.startOfDay(for: date)
                        selectedDay = day
                        currentMonth = Self.startOfMonth(day)
                        calendarPopupDay = day
                    } label: {
                        VStack(spacing: 5) {
                            Text("\(cal.component(.day, from: date))")
                                .font(.cond(19, .semibold))
                                .foregroundStyle(selection ? Color.white : isToday ? Theme.accent : index >= 5 ? Theme.textSoft : Theme.text)
                                .frame(width: 36, height: 36)
                                .background(selection ? Theme.accent : .clear, in: Circle())
                                .overlay { if isToday && !selection { Circle().stroke(Theme.accent, lineWidth: 1.5) } }
                            raceDots(races)
                        }
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(Self.longDayFormatter.string(from: date)), \(races.count) course(s)")
                } else {
                    Color.clear.frame(maxWidth: .infinity, minHeight: 58)
                }
            }
        }
        .padding(.vertical, 3)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    /// One dot per race (3 max), colored by status: wishlist, registered, confirmed, otherwise accent.
    private func raceDots(_ races: [Event]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(races.prefix(3))) { m in
                Circle().fill(tracking.status(m.id).color ?? Theme.accent).frame(width: 5, height: 5)
            }
        }
        .frame(height: 5)
    }

    private func monthLabelRow(name: String, column: Int) -> some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                ZStack(alignment: .leading) {
                    if index == column {
                        Text(name)
                            .font(.cond(16, .semibold)).tracking(1).textCase(.uppercase)
                            .foregroundStyle(Theme.accent)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(height: 34, alignment: .bottom)
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    private func todayButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("Aujourd’hui")
                .font(.cond(15, .semibold)).tracking(1).textCase(.uppercase)
                .foregroundStyle(Theme.text)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    /// "13:30:00" or "13:30" → "13:30".
    private static func shortTime(_ raw: String?) -> String? {
        guard let h = raw?.trimmingCharacters(in: .whitespaces), h.count >= 5, h.contains(":") else { return nil }
        return String(h.prefix(5))
    }

    private func monthKey(_ date: Date) -> String {
        let cal = Calendar.current
        let start = Self.startOfMonth(date)
        let year = cal.component(.year, from: start)
        let month = cal.component(.month, from: start)
        return String(format: "%04d-%02d", year, month)
    }

    private func calendarPopup(_ day: Date) -> some View {
        let races = eventsOnDay(day)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(races.isEmpty ? "AUCUNE COURSE" : "\(races.count) COURSE(S)",
                            color: races.isEmpty ? Theme.muted : Theme.accent)
                    Text(Self.longDayFormatter.string(from: day))
                        .font(.cond(22, .semibold)).textCase(.uppercase)
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                Button {
                    calendarPopupDay = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 34, height: 34)
                        .background(Theme.surface2, in: Circle())
                }
                .buttonStyle(.plain)
            }
            if races.isEmpty {
                Text("Aucune course ce jour-là avec les filtres actifs.")
                    .font(.barlow(14))
                    .foregroundStyle(Theme.muted)
            } else {
                ForEach(Array(races.prefix(4))) { event in
                    NavigationLink {
                        EventDetailView(event: event)
                    } label: {
                        let status = tracking.status(event.id)
                        let tint = status.color ?? Theme.accent
                        HStack(spacing: 12) {
                            Text(Self.shortTime(event.startTimeText) ?? "—")
                                .font(.barlow(13, .semibold))
                                .foregroundStyle(tint)
                                .frame(width: 52, height: 40)
                                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.name)
                                    .font(.barlow(15, .semibold)).foregroundStyle(Theme.text).lineLimit(1)
                                Text([event.address?.city?.capitalized, event.kind?.name].compactMap { $0 }.joined(separator: " · "))
                                    .font(.barlow(12)).foregroundStyle(Theme.muted).lineLimit(1)
                            }
                            Spacer(minLength: 6)
                            if status != .untracked {
                                Image(systemName: status == .wishlist ? "bookmark.fill" : status == .registered ? "hourglass.circle.fill" : "checkmark.circle.fill")
                                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(tint)
                            }
                            Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.faint)
                        }
                        .padding(8)
                        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if races.count > 4 {
                    Text("… et \(races.count - 4) autre(s)").font(.barlow(12)).foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Theme.surface.opacity(0.98), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func updateVisibleMonthFromScroll() {
        guard isFullScreenCalendar, !weekRowPositions.isEmpty, calendarViewportHeight > 0 else { return }
        let cal = Calendar.current
        let visibleRows = weekRowPositions.filter { $0.maxY > 0 && $0.minY < calendarViewportHeight }
        guard !visibleRows.isEmpty else { return }
        let anchorRow = visibleRows
            .filter { $0.maxY > 0 }
            .min(by: { abs($0.minY) < abs($1.minY) }) ?? visibleRows[0]
        let visibleMonth = Self.startOfMonth(anchorRow.date)
        if !cal.isDate(visibleMonth, equalTo: currentMonth, toGranularity: .month) {
            currentMonth = visibleMonth
        }
    }

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            let weekdaySymbols = ["L", "M", "M", "J", "V", "S", "D"]
            HStack {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, day in
                    Text(day).font(.cond(12, .semibold)).foregroundStyle(Theme.muted).frame(maxWidth: .infinity)
                }
            }
            let cells = calendarCells()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(cells.indices, id: \.self) { index in
                    if let date = cells[index] {
                        let races = eventsOnDay(date)
                        let selection = Calendar.current.isDate(date, inSameDayAs: selectedDay)
                        Button {
                            selectedDay = Calendar.current.startOfDay(for: date)
                        } label: {
                            VStack(spacing: 4) {
                                Text("\(Calendar.current.component(.day, from: date))")
                                    .font(.cond(16, .semibold))
                                    .foregroundStyle(selection ? Theme.bg : Theme.text)
                                if selection || races.isEmpty {
                                    Circle().fill(races.isEmpty ? Color.clear : Theme.bg).frame(width: 6, height: 6)
                                } else {
                                    raceDots(races)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 42)
                            .background(selection ? Theme.accent : Theme.surface2, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(selection ? Theme.accent : Theme.line, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
        .card(radius: 20, padding: 14)
    }

    private func clampSelectedDayToMonth() {
        if Calendar.current.isDate(selectedDay, equalTo: currentMonth, toGranularity: .month) { return }
        selectedDay = currentMonth
    }

    private func calendarCells() -> [Date?] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: .month, for: currentMonth) else { return [] }
        let first = interval.start
        let days = cal.range(of: .day, in: .month, for: first)?.count ?? 0
        let weekday = cal.component(.weekday, from: first)
        let prefix = (weekday + 5) % 7 // Monday = 0
        var result = Array<Date?>(repeating: nil, count: prefix)
        for day in 0..<days {
            if let date = cal.date(byAdding: .day, value: day, to: first) {
                result.append(date)
            }
        }
        while result.count % 7 != 0 { result.append(nil) }
        return result
    }

    private func eventsOnDay(_ date: Date) -> [Event] {
        let cal = Calendar.current
        return events
            .filter { $0.startDate.map { cal.isDate($0, inSameDayAs: date) } ?? false }
            .sorted { ($0.startDate ?? .distantFuture, $0.id) < ($1.startDate ?? .distantFuture, $1.id) }
    }

    private var latestEventDate: Date? {
        events.compactMap(\.startDate).max()
    }

    private func prefetchCalendarIfNeeded(through month: Date) async {
        guard selectedMode == .calendar else { return }
        // during a reload, load() restarts the prefetch at the end
        guard !isLoading, !isPrefetchingCalendar else { return }
        guard !remainingSports.isEmpty else { return }
        isPrefetchingCalendar = true
        defer { isPrefetchingCalendar = false }
        let cal = Calendar.current
        let targetMonth = Self.startOfMonth(month)
        let targetMonthEnd = (cal.date(byAdding: DateComponents(month: 1, day: -1), to: targetMonth) ?? targetMonth)
        let threshold = cal.date(byAdding: .month, value: 1, to: targetMonthEnd) ?? targetMonthEnd
        var attempts = 0
        while !remainingSports.isEmpty && (latestEventDate == nil || (latestEventDate ?? .distantPast) < threshold) {
            if attempts >= 14 { break }
            attempts += 1
            await loadMore()
            if errorMessage != nil { break }
        }
    }

    private func applyDefaultDepartments(_ newValues: Set<Int>) {
        departmentIDs = newValues
    }

    private func applyDefaultSports(_ newValues: Set<String>) {
        sportCodes = newValues
    }

    private func updateTabBarVisibility() {
        let isMapPopupOpen = selectedPinID != nil && isFullScreenMap
        let isCalendarPopupOpen = calendarPopupDay != nil && isFullScreenCalendar
        hideFloatingTabBar = showsFilterPanel || isMapPopupOpen || isCalendarPopupOpen
    }

    private func handleViewModeChange(_ newMode: ViewMode) {
        if newMode == .map {
            locationProvider.start()
        }
    }

    private func syncSelectedDay() {
        if !eventsOnDay(selectedDay).isEmpty { return }
        if let firstDay = firstEventDay() {
            selectedDay = firstDay
            currentMonth = Self.startOfMonth(firstDay)
        }
    }

    private func handleUserLocation(_ position: CLLocation?) {
        guard selectedMode == .map, !didCenterOnUser, let position else { return }
        mapPosition = .region(MKCoordinateRegion(center: position.coordinate, latitudinalMeters: 70_000, longitudinalMeters: 70_000))
        didCenterOnUser = true
    }

    private func firstEventDay() -> Date? {
        for event in events {
            if let date = event.startDate {
                return Calendar.current.startOfDay(for: date)
            }
        }
        return nil
    }

    private func refreshPreviewTravelTime() async {
        guard let point = selectedPin, point.events.count == 1, let event = point.events.first else {
            previewTravelTime = nil
            isComputingPreviewTravelTime = false
            previewTravelTimeError = nil
            previewTravelTimeEventID = nil
            return
        }
        previewTravelTimeEventID = event.id
        guard TravelTimeService.isAuthorized else {
            previewTravelTime = nil
            isComputingPreviewTravelTime = false
            previewTravelTimeError = nil
            return
        }
        await computePreviewTravelTime(event)
    }

    private func computePreviewTravelTime(_ event: Event) async {
        guard let c = event.address?.coordinate else { return }
        if isComputingPreviewTravelTime { return }
        previewTravelTimeEventID = event.id
        isComputingPreviewTravelTime = true
        defer { isComputingPreviewTravelTime = false }
        do {
            previewTravelTime = try await TravelTimeService.travelTime(toLatitude: c.latitude, longitude: c.longitude)
            previewTravelTimeError = nil
        } catch {
            previewTravelTime = nil
            previewTravelTimeError = error.localizedDescription
        }
    }

    private func statusChip(_ status: StatusFilter, text: String, icon: String?, color: Color, fill: Color, textColor: Color) -> some View {
        Button {
            statusFilter = status
        } label: {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                }
                Text(text).font(.barlow(12, .semibold))
            }
            .foregroundStyle(statusFilter == status ? textColor : color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(statusFilter == status ? fill : fill.opacity(0.75))
            )
            .overlay(
                Capsule()
                    .stroke(statusFilter == status ? fill.opacity(0.45) : Theme.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func row(_ m: Event) -> some View {
        NavigationLink {
            EventDetailView(event: m)
        } label: {
            EventListRow(
                event: m,
                status: tracking.status(m.id)
            )
        }
        .buttonStyle(.plain)
        // bookmark outside the NavigationLink so tapping it does not open the detail; space reserved in the row
        .overlay(alignment: .trailing) {
            if tracking.status(m.id).isWishlistEditable {
                WishlistButton(event: m).padding(.trailing, 40)
            }
        }
    }

    /// Department of the location from the postal code ("59" for 59000, "971" for 97100); true if unknown.
    private static func isInDepartments(_ m: Event, _ numbers: Set<String>) -> Bool {
        guard let zip = m.address?.postalCode, zip.count == 5, zip.allSatisfy(\.isNumber) else { return true }
        let isOverseas = zip.hasPrefix("97") || zip.hasPrefix("98")
        return numbers.contains(String(zip.prefix(isOverseas ? 3 : 2).drop { $0 == "0" }))
    }

    /// Registrations and payments (list badges and filters).
    private func refreshTracking() async {
        await tracking.refresh(auth)
    }

    private func load() async {
        generation += 1
        isLoading = true
        errorMessage = nil
        nextPage = 1
        remainingSports = sportCodes.isEmpty ? [nil] : sportCodes.sorted()
        isLoadingMore = false
        defer { isLoading = false }
        // show the first cached page immediately (even if stale); pagination then restarts from zero
        if events.isEmpty, let cachedItems = await auth.client.fromCacheOnly({ try await fetchNextPage() }), !cachedItems.isEmpty {
            events = cachedItems
            nextPage = 1
            remainingSports = sportCodes.isEmpty ? [nil] : sportCodes.sorted()
        }
        do {
            await refreshTracking()
            let fetched = try await fetchNextPage()
            events = fetched
            tracking.rememberDeadlines(fetched)
            // very selective department filter: keep loading until there is something to show
            if events.isEmpty { await loadMore() }
            hasLoadedOnce = true
            // the calendar prefetch may have stopped during the reload: restart it
            if selectedMode == .calendar {
                isLoading = false
                await prefetchCalendarIfNeeded(through: currentMonth)
            }
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Loads the next page when the end of the list becomes visible.
    private func loadMore() async {
        guard !isLoadingMore, !isLoading || events.isEmpty, !remainingSports.isEmpty else { return }
        isLoadingMore = true
        let currentGeneration = generation
        defer { if currentGeneration == generation { isLoadingMore = false } }
        do {
            var added: [Event] = []
            while added.isEmpty && !remainingSports.isEmpty {
                added = try await fetchNextPage()
                guard currentGeneration == generation else { return }
            }
            guard currentGeneration == generation else { return }
            merge(added)
        } catch is CancellationError {
        } catch let error as URLError where error.code == .cancelled {
        } catch {
            if currentGeneration == generation { errorMessage = error.localizedDescription }
        }
    }

    /// Fetches the next page of each remaining sport and updates the pagination state.
    private func fetchNextPage() async throws -> [Event] {
        let currentGeneration = generation
        let page = nextPage
        let sports = remainingSports
        let client = auth.client, name = searchText, structures = departmentIDs.sorted()
        let responses: [(String?, [Event], Bool)] = try await auth.withSession {
            try await withThrowingTaskGroup(of: (String?, [Event], Bool).self) { group in
                for sport in sports {
                    group.addTask {
                        let r = try await client.eventsPage(page: page, name: name, structureIDs: structures, discipline: sport)
                        return (sport, r.events, r.hasMore)
                    }
                }
                var collected: [(String?, [Event], Bool)] = []
                for try await r in group { collected.append(r) }
                return collected
            }
        }
        // a reload (load) started during the request: this page is stale and must not
        // overwrite the pagination it just reset
        guard currentGeneration == generation else { throw CancellationError() }
        nextPage = page + 1
        remainingSports = sports.filter { sport in responses.first { $0.0 == sport }?.2 ?? false }
        let found = responses.flatMap(\.1)
        // the site filters on the organizing structure: keep only events located in the department
        let numbers = Set(store.departments.filter { departmentIDs.contains($0.id) }.map(\.number))
        return numbers.isEmpty ? found : found.filter { Self.isInDepartments($0, numbers) }
    }

    private func merge(_ fetched: [Event]) {
        var byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for m in fetched { byID[m.id] = m }
        events = byID.values.sorted { ($0.startDate ?? .distantFuture, $0.id) < ($1.startDate ?? .distantFuture, $1.id) }
        tracking.rememberDeadlines(events)
    }

    private static let monthYearFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private static let longDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    private static let monthNameFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "MMMM"
        return f
    }()

    private static let weekdaySymbols = ["L", "M", "M", "J", "V", "S", "D"]

    private static let franceRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 46.7, longitude: 2.3),
        span: MKCoordinateSpan(latitudeDelta: 9.5, longitudeDelta: 9.5)
    )

    private nonisolated static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: date)) ?? Calendar.current.startOfDay(for: date)
    }

    private struct WeekRowPosition: Equatable {
        let date: Date
        let minY: CGFloat
        let maxY: CGFloat
    }

    private struct WeekRowPositionKey: PreferenceKey {
        static var defaultValue: [WeekRowPosition] = []
        static func reduce(value: inout [WeekRowPosition], nextValue: () -> [WeekRowPosition]) {
            value.append(contentsOf: nextValue())
        }
    }

    private func startOfWeek(_ date: Date) -> Date {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: date)
        let dayOffset = (weekday + 5) % 7 // Monday = 0
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -dayOffset, to: date) ?? date)
    }
}
