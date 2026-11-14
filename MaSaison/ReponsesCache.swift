import CryptoKit
import Foundation

/// Durée pendant laquelle une réponse du site est réutilisée sans le rappeler.
enum Fraicheur {
    /// Toujours le réseau, rien n'est gardé (commandes, étapes d'inscription).
    case aucune
    case duree(TimeInterval)

    static let disciplines = Fraicheur.duree(7 * 86_400)
    static let departements = Fraicheur.duree(7 * 86_400)
    static let groupes = Fraicheur.duree(12 * 3_600)
    static let ficheManifestation = Fraicheur.duree(12 * 3_600)
    static let listeCourses = Fraicheur.duree(6 * 3_600)
    static let profil = Fraicheur.duree(3_600)
    static let cartes = Fraicheur.duree(3_600)
    static let resultats = Fraicheur.duree(5 * 60)
    static let inscriptions = Fraicheur.duree(5 * 60)
}

/// Réponses brutes du site (HTML ou JSON) par URL, en mémoire et dans `Caches/ufolep/` (un fichier par URL,
/// daté par sa date de modification). Purgé des entrées de plus de 7 jours au lancement, vidé à la déconnexion.
final class ReponsesCache {
    static let shared = ReponsesCache()

    /// Lecture seule du cache, même périmé : pour afficher un écran tout de suite (voir `UfolepClient.depuisCache`).
    @TaskLocal static var cacheSeulement = false
    /// Ignore le cache et force le réseau : tirer pour rafraîchir (voir `UfolepClient.sansCache`).
    @TaskLocal static var ignorer = false

    private struct Entree {
        let data: Data
        let date: Date
    }

    private let dossier = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ufolep", isDirectory: true)
    private var memoire: [String: Entree] = [:]
    private static let ageMax: TimeInterval = 7 * 86_400

    private init() {
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
        purger()
    }

    /// Entrée si elle existe, avec son âge ; `nil` sinon.
    func lire(_ url: URL) -> (data: Data, age: TimeInterval)? {
        let cle = url.absoluteString
        if let e = memoire[cle] { return (e.data, Date().timeIntervalSince(e.date)) }
        let f = fichier(cle)
        guard let data = try? Data(contentsOf: f),
              let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        memoire[cle] = Entree(data: data, date: date)
        return (data, Date().timeIntervalSince(date))
    }

    func ecrire(_ data: Data, pour url: URL) {
        let cle = url.absoluteString
        memoire[cle] = Entree(data: data, date: Date())
        let f = fichier(cle)
        try? data.write(to: f, options: .atomic)
        try? Data(cle.utf8).write(to: f.appendingPathExtension("url"), options: .atomic)
    }

    /// Oublie les réponses dont le chemin commence par l'un des préfixes (ex. après une inscription).
    func invalider(chemins: [String]) {
        let prefixes = chemins.map { UfolepClient.baseURL.appending(path: $0).absoluteString }
        for cle in memoire.keys where prefixes.contains(where: cle.hasPrefix) { memoire[cle] = nil }
        // sur le disque, l'URL d'origine est lue dans le fichier « .url » rangé à côté de chaque réponse
        for cle in index() where prefixes.contains(where: cle.hasPrefix) {
            let f = fichier(cle)
            try? FileManager.default.removeItem(at: f)
            try? FileManager.default.removeItem(at: f.appendingPathExtension("url"))
        }
    }

    /// Vide tout (déconnexion : ce sont des données personnelles).
    func vider() {
        memoire = [:]
        try? FileManager.default.removeItem(at: dossier)
        try? FileManager.default.createDirectory(at: dossier, withIntermediateDirectories: true)
    }

    // MARK: fichiers

    /// Nom de fichier = SHA-256 de l'URL ; l'URL est rangée à côté (« .url ») pour l'invalidation par chemin.
    private func fichier(_ cle: String) -> URL {
        let nom = SHA256.hash(data: Data(cle.utf8)).map { String(format: "%02x", $0) }.joined()
        return dossier.appendingPathComponent(nom)
    }

    private func index() -> [String] {
        let fichiers = (try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: nil)) ?? []
        return fichiers.filter { $0.pathExtension == "url" }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private func purger() {
        let fichiers = (try? FileManager.default.contentsOfDirectory(at: dossier, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in fichiers where f.pathExtension != "url" {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(date) > Self.ageMax {
                try? FileManager.default.removeItem(at: f)
                try? FileManager.default.removeItem(at: f.appendingPathExtension("url"))
            }
        }
    }
}
