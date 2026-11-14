import Foundation

enum UfolepError: LocalizedError {
    case tokenNotFound
    case invalidCredentials
    case sessionExpired
    case http(Int)
    case denied([String])

    var errorDescription: String? {
        switch self {
        case .tokenNotFound: "Impossible de trouver le jeton _token sur la page de connexion."
        case .invalidCredentials: "Identifiant ou mot de passe incorrect."
        case .sessionExpired: "Session expirée, reconnectez-vous."
        case .http(let code): "Erreur HTTP \(code)."
        case .denied(let messages): messages.joined(separator: "\n")
        }
    }
}

/// Client for the UFOLEP « Mon espace licencié » site.
/// The session (XSRF-TOKEN / ufolep_session cookies) is handled by URLSession's cookie storage.
final class UfolepClient {
    static let baseURL = URL(string: "https://licencies-monespace.ufolep.org")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    /// 1. GET /auth/login to get the CSRF `_token` (and the session cookies)
    /// 2. POST /auth/login as x-www-form-urlencoded
    func login(username: String, password: String) async throws {
        let loginURL = Self.baseURL.appending(path: "auth/login")

        let (pageData, pageResponse) = try await session.data(from: loginURL)
        try check(pageResponse)
        let html = String(decoding: pageData, as: UTF8.self)
        guard let token = Self.extractToken(from: html) else { throw UfolepError.tokenNotFound }

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue(loginURL.absoluteString, forHTTPHeaderField: "Referer")
        request.httpBody = Self.formEncode([
            ("_token", token),
            ("username", username),
            ("password", password),
        ])

        // URLSession follows the redirect; on failure Laravel redirects to /auth/login.
        let (_, response) = try await session.data(for: request)
        try check(response)
        if response.url?.path.hasSuffix("/auth/login") == true {
            throw UfolepError.invalidCredentials
        }
    }

    /// GET /manifestations/liste (authenticated) — returns the HTML.
    func fetchEventListPage() async throws -> String {
        let url = Self.baseURL.appending(path: "manifestations/liste")
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")

        let data = try await withCache(request, freshness: .disciplines)
        return String(decoding: data, as: UTF8.self)
    }

    /// One page of the federal calendar (from today on, like the site).
    /// `name` filters on the name, `structureIDs` on departments (including their clubs),
    /// `discipline` on the sport: the site only accepts one code at a time.
    func eventsPage(page: Int, name: String = "", structureIDs: [Int] = [], discipline: String? = nil, since: String? = nil) async throws -> (events: [Event], hasMore: Bool) {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "par_page", value: String(Self.eventsPerPage)),
            URLQueryItem(name: "date_debut", value: since ?? Self.todayString),
        ]
        if !name.isEmpty { query.append(.init(name: "libelle", value: name)) }
        if let discipline { query.append(.init(name: "discipline_code", value: discipline)) }
        // Laravel: structures_ids[]=75&structures_ids[]=78
        for id in structureIDs { query.append(.init(name: "structures_ids[]", value: String(id))) }
        let data = try await getJSON("manifestations/calendrier-federal/query", query, freshness: .eventList)
        let response = try JSONDecoder().decode(Page<Event>.self, from: data)
        let hasMore = response.lastPage.map { page < $0 } ?? (response.data.count >= Self.eventsPerPage)
        return (response.data, hasMore && !response.data.isEmpty)
    }

    private static let eventsPerPage = 50

    /// All pages of a search (safety cap of 40 pages).
    func searchEvents(name: String = "", structureIDs: [Int] = [], since: String? = nil) async throws -> [Event] {
        var results: [Event] = []
        for page in 1...40 {
            let (found, hasMore) = try await eventsPage(page: page, name: name, structureIDs: structureIDs, since: since)
            results += found
            if !hasMore { break }
        }
        return results
    }

    /// Finds an event (even past) by its name, then its id.
    func fetchEvent(id: Int, name: String) async throws -> Event? {
        try await searchEvents(name: name, since: "01-01-2000").first { $0.id == id }
    }

    /// Contact (email and phone): only in the event page, whose `:manifestation` prop embeds the whole JSON.
    func fetchContact(eventID: Int) async throws -> EventContact? {
        struct Envelope: Decodable {
            let contacts: [EventContact]?
            enum CodingKeys: String, CodingKey { case contacts = "correspondants" }
        }
        let html = try await getHTML("manifestations/show/\(eventID)", freshness: .eventPage)
        guard let start = html.range(of: ":manifestation=\""),
              let end = html[start.upperBound...].firstIndex(of: "\"") else { return nil }
        let json = String(html[start.upperBound..<end])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return try JSONDecoder().decode(Envelope.self, from: Data(json.utf8)).contacts?.first
    }

    /// The member's registrations (upcoming and past).
    func fetchRegistrations() async throws -> [Registration] {
        HTMLParsing.registrations(from: try await getHTML("manifestations/liste-inscriptions", freshness: .registrations))
    }

    /// The member's rankings in past events.
    func fetchResults() async throws -> [RaceResult] {
        HTMLParsing.results(from: try await getHTML("manifestations/resultats", freshness: .results))
    }

    func fetchCards() async throws -> [LicenseCard] {
        HTMLParsing.cards(from: try await getHTML("cartes-pass/cartes", freshness: .cards))
    }

    func fetchProfile() async throws -> Profile {
        HTMLParsing.profile(from: try await getHTML("infos", freshness: .profile))
    }

    private func getHTML(_ path: String, freshness: Freshness = .uncached) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        return String(decoding: try await withCache(request, freshness: freshness), as: UTF8.self)
    }

    /// Disciplines are injected into the page HTML (`disciplines` prop).
    func fetchDisciplines() async throws -> [Discipline] {
        let html = try await fetchEventListPage()
        guard let match = html.firstMatch(of: #/:disciplines="([^"]*)"/#) else { return [] }
        let json = String(match.output.1)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        let disciplines = try JSONDecoder().decode([Discipline].self, from: Data(json.utf8))
        return disciplines.filter { $0.active != false }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Downloads a file with the member's session (GPX).
    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try check(response)
        return data
    }

    /// Departmental committees: federation → regions → departments tree (`/structures/lazy-tree`).
    func fetchDepartments() async throws -> [Department] {
        func nodes(_ structureID: Int, mode: String) async throws -> [TreeNode] {
            let data = try await getJSON("structures/lazy-tree", [
                URLQueryItem(name: "structure_id", value: String(structureID)),
                URLQueryItem(name: "mode", value: mode),
            ], freshness: .departments)
            return try JSONDecoder().decode([TreeNode].self, from: data)
        }
        let regions = try await nodes(1, mode: "root").first?.children ?? []
        let departments = try await withThrowingTaskGroup(of: [TreeNode].self) { group in
            for region in regions { group.addTask { try await nodes(region.key, mode: "children") } }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        return departments.compactMap(\.department).sorted { $0.code < $1.code }
    }

    private static var todayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MM-yyyy"
        return f.string(from: Date())
    }

    /// Race groups (Adultes, Jeunes, …) of an event, in display order.
    func fetchLevelGroups(eventID: Int) async throws -> [LevelGroup] {
        let data = try await getJSON("manifestations/calendrier-federal/niveaux", [
            URLQueryItem(name: "manifestation_id", value: String(eventID)),
        ], freshness: .groups)
        return try JSONDecoder().decode([LevelGroup].self, from: data)
    }

    private func getJSON(_ path: String, _ query: [URLQueryItem], freshness: Freshness = .uncached) async throws -> Data {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return try await withCache(request, freshness: freshness)
    }

    // MARK: response cache

    /// GET with cache: a stored response is reused while fresh, otherwise network then cached.
    /// Offline, the old response is used as a fallback. A login page (expired session) is never stored.
    private func withCache(_ request: URLRequest, freshness: Freshness) async throws -> Data {
        guard let url = request.url else { throw UfolepError.http(0) }
        let cache = ResponseCache.shared
        guard case .duration(let duration) = freshness else { return try await fetchFromNetwork(request) }

        let cached = cache.read(url)
        if ResponseCache.cacheOnly {
            guard let cached else { throw CancellationError() }
            return cached.data
        }
        if !ResponseCache.bypassCache, let cached, cached.age < duration { return cached.data }
        do {
            let data = try await fetchFromNetwork(request)
            cache.write(data, for: url)
            return data
        } catch let failure as URLError where cached != nil && failure.code != .cancelled {
            return cached!.data
        }
    }

    private func fetchFromNetwork(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if response.url?.path.contains("/auth/login") == true { throw UfolepError.sessionExpired }
        try check(response)
        return data
    }

    /// Runs `operation` reading only the cache (even if stale): immediate display before the network call.
    /// `nil` if one of the required responses is not cached.
    func fromCacheOnly<T>(_ operation: () async throws -> T) async -> T? {
        try? await ResponseCache.$cacheOnly.withValue(true) { try await operation() }
    }

    /// Runs `operation` without cache (pull to refresh); the received responses replace the cache.
    func bypassingCache<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await ResponseCache.$bypassCache.withValue(true) { try await operation() }
    }

    /// Personal data changed by an action (registration, payment): reload on the next call.
    func invalidateTracking() {
        ResponseCache.shared.invalidate(paths: ["manifestations/liste-inscriptions", "commandes"])
    }

    func clearSession() {
        ResponseCache.shared.clear()
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    // MARK: race registration

    private var cachedPersonID: Int?

    /// Orders awaiting payment.
    func fetchOrders() async throws -> [Order] {
        HTMLParsing.orders(from: try await getHTML("commandes"))
    }

    /// Session cookies, to open a site page (payment) in an embedded window.
    func cookies() -> [HTTPCookie] {
        session.configuration.httpCookieStorage?.cookies(for: Self.baseURL) ?? []
    }

    /// "Choix du mode de paiement" page of an order.
    static func paymentURL(_ order: Order?) -> URL {
        guard let order else { return baseURL.appending(path: "commandes") }
        var c = URLComponents(url: baseURL.appending(path: "commandes/choix-paiement"), resolvingAgainstBaseURL: false)!
        c.percentEncodedQuery = "commandes%5B%5D=\(order.id)"
        return c.url!
    }

    /// Registrations "en cours de saisie" (saved, not yet validated) for this event.
    func draftRegistrationCount(eventID: Int) async throws -> Int {
        let data = try await getJSON("manifestations/licencie/inscription-manifestation/manifestation/\(eventID)/inscriptions-solo-saisies", [])
        return ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [Any])?.count ?? 0
    }

    /// Identifier of the licensed person (`personne` prop of the calendar page).
    func fetchPersonID() async throws -> Int {
        if let cachedPersonID { return cachedPersonID }
        let html = try await fetchEventListPage()
        guard let m = html.firstMatch(of: #/:personne="([^"]*)"/#) else { throw UfolepError.denied(["Profil introuvable."]) }
        let json = String(m.output.1).replacingOccurrences(of: "&quot;", with: "\"")
        guard let id = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["id"] as? Int else {
            throw UfolepError.denied(["Profil introuvable."])
        }
        cachedPersonID = id
        return id
    }

    /// What the site allows for this person on this event (open races, rejection reasons).
    func fetchPersonRegistrationDetail(eventID: Int, personID: Int) async throws -> PersonRegistrationDetail {
        let data = try await getJSON("manifestations/manifestation/\(eventID)/detail-personne/\(personID)", [])
        return try JSONDecoder().decode(PersonRegistrationDetail.self, from: data)
    }

    /// Step 1: the site computes the ticket (creates the registration "en cours de saisie").
    func computeTicket(eventID: Int, personID: Int, levelID: Int) async throws -> RegistrationTicket {
        let level: [String: Any] = ["niveau_id": levelID, "poids": NSNull(), "principal": false, "infos_complementaires": [String: Any]()]
        let registration: [String: Any] = [
            "id": NSNull(), "personne_id": personID, "commentaire": NSNull(), "certificat_medical": NSNull(),
            "roles": [Int](), "infos_complementaires": [String: Any](),
            "payeur_id": personID, "payeur_type": "ELicence\\Core\\Models\\Personne",
            "libelle": NSNull(), "carte_etranger_id": NSNull(), "gratuit": false, "groupe_id": NSNull(),
            "niveaux": [level],
        ]
        let payload: [String: Any] = ["inscription": [registration], "structure_id": NSNull(), "entente_id": NSNull()]
        let data = try await postJSON("manifestations/manifestation/\(eventID)/generation-ticket", payload)
        return try Self.ticket(from: data)
    }

    /// Step 3: validation ticket for all your "en cours de saisie" registrations on this event.
    func computeFinalTicket(eventID: Int) async throws -> RegistrationTicket {
        let data = try await postJSON("manifestations/licencie/inscription-manifestation/manifestation/\(eventID)/calcul-inscription-unique", [:])
        return try Self.ticket(from: data)
    }

    /// Step 4: final validation (the registration becomes "to pay"; payment then happens in Orders).
    func saveFinalRegistration(eventID: Int, ticketID: String) async throws {
        _ = try await postJSON("manifestations/licencie/inscription-manifestation/manifestation/\(eventID)/enregistrer-inscription-unique/\(ticketID)", [:])
    }

    private static func ticket(from data: Data) throws -> RegistrationTicket {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? String ?? (json["id"] as? Int).map(String.init) else {
            throw UfolepError.denied(["Réponse inattendue du site (ticket)."])
        }
        let rows = (json["data"] as? [[String: Any]] ?? []).map {
            RegistrationTicket.LineItem(name: $0["libelle"] as? String ?? "", amount: ($0["montant"] as? NSNumber)?.doubleValue ?? 0)
        }
        return RegistrationTicket(id: id, total: (json["total"] as? NSNumber)?.doubleValue ?? rows.reduce(0) { $0 + $1.amount }, rows: rows, raw: data)
    }

    /// Step 2: saves the ticket. `final: false` = registration "en cours de saisie" (validation and payment afterwards).
    func save(ticketID: String, final: Bool) async throws {
        _ = try await postJSON("manifestations/ticket/\(ticketID)", ["enregistrementFinal": final])
    }

    /// JSON POST with the CSRF token that Laravel reads from the `X-XSRF-TOKEN` header (value of the XSRF-TOKEN cookie).
    private func postJSON(_ path: String, _ payload: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        if let cookie = session.configuration.httpCookieStorage?.cookies(for: Self.baseURL)?.first(where: { $0.name == "XSRF-TOKEN" }) {
            request.setValue(cookie.value.removingPercentEncoding ?? cookie.value, forHTTPHeaderField: "X-XSRF-TOKEN")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        let (data, response) = try await session.data(for: request)
        if response.url?.path.contains("/auth/login") == true { throw UfolepError.sessionExpired }
        if let http = response as? HTTPURLResponse, http.statusCode == 422 || http.statusCode == 403 {
            throw UfolepError.denied(Self.messages(from: data))
        }
        try check(response)
        return data
    }

    /// Extracts error messages from a Laravel 422 response (`{"errors": {...}}` or `{"message": "..."}`).
    private static func messages(from data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return ["Le site a refusé la demande."] }
        if let errors = json["errors"] as? [String: Any] {
            return errors.values.flatMap { ($0 as? [String]) ?? [String(describing: $0)] }
        }
        return [json["message"] as? String ?? "Le site a refusé la demande."]
    }

    private func check(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw UfolepError.http(http.statusCode)
        }
    }

    private static func extractToken(from html: String) -> String? {
        // <input type="hidden" name="_token" value="..."> (or <meta name="csrf-token" content="...">)
        let patterns = [
            #"name=["']_token["'][^>]*value=["']([^"']+)["']"#,
            #"value=["']([^"']+)["'][^>]*name=["']_token["']"#,
            #"name=["']csrf-token["'][^>]*content=["']([^"']+)["']"#,
        ]
        for pattern in patterns {
            if let match = html.firstMatch(of: try! Regex(pattern)),
               let range = match.output[1].range {
                return String(html[range])
            }
        }
        return nil
    }

    private static func formEncode(_ fields: [(String, String)]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields
            .map { "\($0.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($1.addingPercentEncoding(withAllowedCharacters: allowed)!)" }
            .joined(separator: "&")
            .data(using: .utf8)!
    }
}
