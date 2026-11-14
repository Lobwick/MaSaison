import Foundation

enum UfolepError: LocalizedError {
    case tokenIntrouvable
    case identifiantsInvalides
    case sessionExpiree
    case http(Int)
    case refuse([String])

    var errorDescription: String? {
        switch self {
        case .tokenIntrouvable: "Impossible de trouver le jeton _token sur la page de connexion."
        case .identifiantsInvalides: "Identifiant ou mot de passe incorrect."
        case .sessionExpiree: "Session expirée, reconnectez-vous."
        case .http(let code): "Erreur HTTP \(code)."
        case .refuse(let messages): messages.joined(separator: "\n")
        }
    }
}

/// Client du site « Mon espace licencié » UFOLEP.
/// La session (cookies XSRF-TOKEN / ufolep_session) est gérée par le cookie storage de URLSession.
final class UfolepClient {
    static let baseURL = URL(string: "https://licencies-monespace.ufolep.org")!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        session = URLSession(configuration: config)
    }

    /// 1. GET /auth/login pour récupérer le `_token` CSRF (et les cookies de session)
    /// 2. POST /auth/login en x-www-form-urlencoded
    func login(username: String, password: String) async throws {
        let loginURL = Self.baseURL.appending(path: "auth/login")

        let (pageData, pageResponse) = try await session.data(from: loginURL)
        try check(pageResponse)
        let html = String(decoding: pageData, as: UTF8.self)
        guard let token = Self.extractToken(from: html) else { throw UfolepError.tokenIntrouvable }

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

        // URLSession suit la redirection ; en cas d'échec Laravel renvoie sur /auth/login.
        let (_, response) = try await session.data(for: request)
        try check(response)
        if response.url?.path.hasSuffix("/auth/login") == true {
            throw UfolepError.identifiantsInvalides
        }
    }

    /// GET /manifestations/liste (authentifié) — renvoie le HTML.
    func fetchManifestations() async throws -> String {
        let url = Self.baseURL.appending(path: "manifestations/liste")
        var request = URLRequest(url: url)
        request.setValue("text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8", forHTTPHeaderField: "Accept")
        request.setValue("fr-FR,fr;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(Self.baseURL.absoluteString + "/", forHTTPHeaderField: "Referer")

        let data = try await viaCache(request, fraicheur: .disciplines)
        return String(decoding: data, as: UTF8.self)
    }

    /// Une page du calendrier fédéral (à partir d'aujourd'hui, comme le site).
    /// `libelle` filtre sur le nom, `structureIDs` sur les départements (inclut leurs clubs),
    /// `discipline` sur le sport : le site n'accepte qu'un code à la fois.
    func manifestationsPage(page: Int, libelle: String = "", structureIDs: [Int] = [], discipline: String? = nil, depuis: String? = nil) async throws -> (manifestations: [Manifestation], suite: Bool) {
        var query = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "par_page", value: String(Self.manifestationsParPage)),
            URLQueryItem(name: "date_debut", value: depuis ?? Self.todayString),
        ]
        if !libelle.isEmpty { query.append(.init(name: "libelle", value: libelle)) }
        if let discipline { query.append(.init(name: "discipline_code", value: discipline)) }
        // Laravel : structures_ids[]=75&structures_ids[]=78
        for id in structureIDs { query.append(.init(name: "structures_ids[]", value: String(id))) }
        let data = try await getJSON("manifestations/calendrier-federal/query", query, fraicheur: .listeCourses)
        let reponse = try JSONDecoder().decode(Page<Manifestation>.self, from: data)
        let suite = reponse.lastPage.map { page < $0 } ?? (reponse.data.count >= Self.manifestationsParPage)
        return (reponse.data, suite && !reponse.data.isEmpty)
    }

    private static let manifestationsParPage = 50

    /// Toutes les pages d'une recherche (plafond de sécurité à 40 pages).
    func searchManifestations(libelle: String = "", structureIDs: [Int] = [], depuis: String? = nil) async throws -> [Manifestation] {
        var resultats: [Manifestation] = []
        for page in 1...40 {
            let (trouvees, suite) = try await manifestationsPage(page: page, libelle: libelle, structureIDs: structureIDs, depuis: depuis)
            resultats += trouvees
            if !suite { break }
        }
        return resultats
    }

    /// Retrouve une manifestation (même passée) par son nom, puis son id.
    func fetchManifestation(id: Int, libelle: String) async throws -> Manifestation? {
        try await searchManifestations(libelle: libelle, depuis: "01-01-2000").first { $0.id == id }
    }

    /// Correspondant (mail et téléphone) : seulement dans la page de la fiche, dont la prop `:manifestation` embarque tout le JSON.
    func fetchCorrespondant(manifestationID: Int) async throws -> Correspondant? {
        struct Enveloppe: Decodable { let correspondants: [Correspondant]? }
        let html = try await getHTML("manifestations/show/\(manifestationID)", fraicheur: .ficheManifestation)
        guard let debut = html.range(of: ":manifestation=\""),
              let fin = html[debut.upperBound...].firstIndex(of: "\"") else { return nil }
        let json = String(html[debut.upperBound..<fin])
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        return try JSONDecoder().decode(Enveloppe.self, from: Data(json.utf8)).correspondants?.first
    }

    /// Inscriptions du licencié (à venir et passées).
    func fetchInscriptions() async throws -> [Inscription] {
        HTMLParsing.inscriptions(from: try await getHTML("manifestations/liste-inscriptions", fraicheur: .inscriptions))
    }

    /// Classements du licencié dans les manifestations passées.
    func fetchResultats() async throws -> [Resultat] {
        HTMLParsing.resultats(from: try await getHTML("manifestations/resultats", fraicheur: .resultats))
    }

    func fetchCartes() async throws -> [Carte] {
        HTMLParsing.cartes(from: try await getHTML("cartes-pass/cartes", fraicheur: .cartes))
    }

    func fetchProfil() async throws -> Profil {
        HTMLParsing.profil(from: try await getHTML("infos", fraicheur: .profil))
    }

    private func getHTML(_ path: String, fraicheur: Fraicheur = .aucune) async throws -> String {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.setValue("text/html,application/xhtml+xml", forHTTPHeaderField: "Accept")
        return String(decoding: try await viaCache(request, fraicheur: fraicheur), as: UTF8.self)
    }

    /// Les disciplines sont injectées dans le HTML de la page (prop `disciplines`).
    func fetchDisciplines() async throws -> [Discipline] {
        let html = try await fetchManifestations()
        guard let match = html.firstMatch(of: #/:disciplines="([^"]*)"/#) else { return [] }
        let json = String(match.output.1)
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&amp;", with: "&")
        let disciplines = try JSONDecoder().decode([Discipline].self, from: Data(json.utf8))
        return disciplines.filter { $0.active != false }.sorted { $0.libelle.localizedCaseInsensitiveCompare($1.libelle) == .orderedAscending }
    }

    /// Télécharge un fichier avec la session du licencié (GPX).
    func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        try check(response)
        return data
    }

    /// Comités départementaux : arborescence fédération → régions → départements (`/structures/lazy-tree`).
    func fetchDepartements() async throws -> [Departement] {
        func nodes(_ structureID: Int, mode: String) async throws -> [TreeNode] {
            let data = try await getJSON("structures/lazy-tree", [
                URLQueryItem(name: "structure_id", value: String(structureID)),
                URLQueryItem(name: "mode", value: mode),
            ], fraicheur: .departements)
            return try JSONDecoder().decode([TreeNode].self, from: data)
        }
        let regions = try await nodes(1, mode: "root").first?.children ?? []
        let departements = try await withThrowingTaskGroup(of: [TreeNode].self) { group in
            for region in regions { group.addTask { try await nodes(region.key, mode: "children") } }
            return try await group.reduce(into: []) { $0 += $1 }
        }
        return departements.compactMap(\.departement).sorted { $0.code < $1.code }
    }

    private static var todayString: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "dd-MM-yyyy"
        return f.string(from: Date())
    }

    /// Groupes de courses (Adultes, Jeunes, …) d'une manifestation, dans l'ordre d'affichage.
    func fetchGroupes(manifestationID: Int) async throws -> [GroupeNiveaux] {
        let data = try await getJSON("manifestations/calendrier-federal/niveaux", [
            URLQueryItem(name: "manifestation_id", value: String(manifestationID)),
        ], fraicheur: .groupes)
        return try JSONDecoder().decode([GroupeNiveaux].self, from: data)
    }

    private func getJSON(_ path: String, _ query: [URLQueryItem], fraicheur: Fraicheur = .aucune) async throws -> Data {
        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        components.queryItems = query
        var request = URLRequest(url: components.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return try await viaCache(request, fraicheur: fraicheur)
    }

    // MARK: cache des réponses

    /// GET avec cache : réponse gardée réutilisée tant qu'elle est fraîche, sinon réseau puis mise en cache.
    /// Hors ligne, l'ancienne réponse sert de secours. Une page de connexion (session expirée) n'est jamais gardée.
    private func viaCache(_ request: URLRequest, fraicheur: Fraicheur) async throws -> Data {
        guard let url = request.url else { throw UfolepError.http(0) }
        let cache = ReponsesCache.shared
        guard case .duree(let duree) = fraicheur else { return try await reseau(request) }

        let gardee = cache.lire(url)
        if ReponsesCache.cacheSeulement {
            guard let gardee else { throw CancellationError() }
            return gardee.data
        }
        if !ReponsesCache.ignorer, let gardee, gardee.age < duree { return gardee.data }
        do {
            let data = try await reseau(request)
            cache.ecrire(data, pour: url)
            return data
        } catch let erreur as URLError where gardee != nil && erreur.code != .cancelled {
            return gardee!.data
        }
    }

    private func reseau(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        if response.url?.path.contains("/auth/login") == true { throw UfolepError.sessionExpiree }
        try check(response)
        return data
    }

    /// Exécute `operation` en ne lisant que le cache (même périmé) : affichage immédiat avant l'appel réseau.
    /// `nil` si une des réponses nécessaires n'est pas en cache.
    func depuisCache<T>(_ operation: () async throws -> T) async -> T? {
        try? await ReponsesCache.$cacheSeulement.withValue(true) { try await operation() }
    }

    /// Exécute `operation` sans cache (tirer pour rafraîchir) ; les réponses reçues remplacent le cache.
    func sansCache<T>(_ operation: () async throws -> T) async rethrows -> T {
        try await ReponsesCache.$ignorer.withValue(true) { try await operation() }
    }

    /// Données personnelles modifiées par une action (inscription, paiement) : à relire au prochain appel.
    func invaliderSuivi() {
        ReponsesCache.shared.invalider(chemins: ["manifestations/liste-inscriptions", "commandes"])
    }

    func clearSession() {
        ReponsesCache.shared.vider()
        session.configuration.httpCookieStorage?.removeCookies(since: .distantPast)
    }

    // MARK: inscription à une course

    private var personneIDCache: Int?

    /// Commandes en attente de paiement.
    func fetchCommandes() async throws -> [Commande] {
        HTMLParsing.commandes(from: try await getHTML("commandes"))
    }

    /// Cookies de la session, pour ouvrir une page du site (paiement) dans une fenêtre intégrée.
    func cookies() -> [HTTPCookie] {
        session.configuration.httpCookieStorage?.cookies(for: Self.baseURL) ?? []
    }

    /// Page « Choix du mode de paiement » d'une commande.
    static func urlPaiement(_ commande: Commande?) -> URL {
        guard let commande else { return baseURL.appending(path: "commandes") }
        var c = URLComponents(url: baseURL.appending(path: "commandes/choix-paiement"), resolvingAgainstBaseURL: false)!
        c.percentEncodedQuery = "commandes%5B%5D=\(commande.id)"
        return c.url!
    }

    /// Inscriptions « en cours de saisie » (enregistrées, pas encore validées) pour cette manifestation.
    func inscriptionsEnCoursDeSaisie(manifestationID: Int) async throws -> Int {
        let data = try await getJSON("manifestations/licencie/inscription-manifestation/manifestation/\(manifestationID)/inscriptions-solo-saisies", [])
        return ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [Any])?.count ?? 0
    }

    /// Identifiant de la personne licenciée (prop `personne` de la page du calendrier).
    func fetchPersonneID() async throws -> Int {
        if let personneIDCache { return personneIDCache }
        let html = try await fetchManifestations()
        guard let m = html.firstMatch(of: #/:personne="([^"]*)"/#) else { throw UfolepError.refuse(["Profil introuvable."]) }
        let json = String(m.output.1).replacingOccurrences(of: "&quot;", with: "\"")
        guard let id = (try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])?["id"] as? Int else {
            throw UfolepError.refuse(["Profil introuvable."])
        }
        personneIDCache = id
        return id
    }

    /// Ce que le site autorise pour cette personne sur cette manifestation (courses ouvertes, motifs de refus).
    func fetchDetailPersonne(manifestationID: Int, personneID: Int) async throws -> InscriptionDetailPersonne {
        let data = try await getJSON("manifestations/manifestation/\(manifestationID)/detail-personne/\(personneID)", [])
        return try JSONDecoder().decode(InscriptionDetailPersonne.self, from: data)
    }

    /// Étape 1 : le site calcule le ticket (crée l'inscription « en cours de saisie »).
    func calculerTicket(manifestationID: Int, personneID: Int, niveauID: Int) async throws -> TicketInscription {
        let niveau: [String: Any] = ["niveau_id": niveauID, "poids": NSNull(), "principal": false, "infos_complementaires": [String: Any]()]
        let inscription: [String: Any] = [
            "id": NSNull(), "personne_id": personneID, "commentaire": NSNull(), "certificat_medical": NSNull(),
            "roles": [Int](), "infos_complementaires": [String: Any](),
            "payeur_id": personneID, "payeur_type": "ELicence\\Core\\Models\\Personne",
            "libelle": NSNull(), "carte_etranger_id": NSNull(), "gratuit": false, "groupe_id": NSNull(),
            "niveaux": [niveau],
        ]
        let corps: [String: Any] = ["inscription": [inscription], "structure_id": NSNull(), "entente_id": NSNull()]
        let data = try await postJSON("manifestations/manifestation/\(manifestationID)/generation-ticket", corps)
        return try Self.ticket(depuis: data)
    }

    /// Étape 3 : ticket de validation de toutes tes inscriptions « en cours de saisie » sur cette manifestation.
    func calculerTicketUnique(manifestationID: Int) async throws -> TicketInscription {
        let data = try await postJSON("manifestations/licencie/inscription-manifestation/manifestation/\(manifestationID)/calcul-inscription-unique", [:])
        return try Self.ticket(depuis: data)
    }

    /// Étape 4 : validation définitive (l'inscription devient « à payer », le paiement se fait ensuite dans Commandes).
    func enregistrerInscriptionUnique(manifestationID: Int, ticketID: String) async throws {
        _ = try await postJSON("manifestations/licencie/inscription-manifestation/manifestation/\(manifestationID)/enregistrer-inscription-unique/\(ticketID)", [:])
    }

    private static func ticket(depuis data: Data) throws -> TicketInscription {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["id"] as? String ?? (json["id"] as? Int).map(String.init) else {
            throw UfolepError.refuse(["Réponse inattendue du site (ticket)."])
        }
        let lignes = (json["data"] as? [[String: Any]] ?? []).map {
            TicketInscription.Ligne(libelle: $0["libelle"] as? String ?? "", montant: ($0["montant"] as? NSNumber)?.doubleValue ?? 0)
        }
        return TicketInscription(id: id, total: (json["total"] as? NSNumber)?.doubleValue ?? lignes.reduce(0) { $0 + $1.montant }, lignes: lignes, brut: data)
    }

    /// Étape 2 : enregistre le ticket. `final: false` = inscription « en cours de saisie » (validation et paiement ensuite).
    func enregistrer(ticketID: String, final: Bool) async throws {
        _ = try await postJSON("manifestations/ticket/\(ticketID)", ["enregistrementFinal": final])
    }

    /// POST JSON avec le jeton CSRF que Laravel lit dans l'en-tête `X-XSRF-TOKEN` (valeur du cookie XSRF-TOKEN).
    private func postJSON(_ path: String, _ corps: [String: Any]) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.setValue(Self.baseURL.absoluteString, forHTTPHeaderField: "Origin")
        if let cookie = session.configuration.httpCookieStorage?.cookies(for: Self.baseURL)?.first(where: { $0.name == "XSRF-TOKEN" }) {
            request.setValue(cookie.value.removingPercentEncoding ?? cookie.value, forHTTPHeaderField: "X-XSRF-TOKEN")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: corps)
        let (data, response) = try await session.data(for: request)
        if response.url?.path.contains("/auth/login") == true { throw UfolepError.sessionExpiree }
        if let http = response as? HTTPURLResponse, http.statusCode == 422 || http.statusCode == 403 {
            throw UfolepError.refuse(Self.messages(de: data))
        }
        try check(response)
        return data
    }

    /// Extrait les messages d'erreur d'une réponse 422 Laravel (`{"errors": {...}}` ou `{"message": "..."}`).
    private static func messages(de data: Data) -> [String] {
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
        // <input type="hidden" name="_token" value="..."> (ou <meta name="csrf-token" content="...">)
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
