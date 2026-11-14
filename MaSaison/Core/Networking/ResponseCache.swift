import CryptoKit
import Foundation

/// How long a site response is reused without calling the site again.
enum Freshness {
    /// Always the network, nothing is kept (orders, registration steps).
    case uncached
    case duration(TimeInterval)

    static let disciplines = Freshness.duration(7 * 86_400)
    static let departments = Freshness.duration(7 * 86_400)
    static let groups = Freshness.duration(12 * 3_600)
    static let eventPage = Freshness.duration(12 * 3_600)
    static let eventList = Freshness.duration(6 * 3_600)
    static let profile = Freshness.duration(3_600)
    static let cards = Freshness.duration(3_600)
    static let results = Freshness.duration(5 * 60)
    static let registrations = Freshness.duration(5 * 60)
}

/// Raw site responses (HTML or JSON) by URL, in memory and in `Caches/ufolep/` (one file per URL,
/// dated by its modification date). Entries older than 7 days are purged on launch; cleared on sign-out.
final class ResponseCache {
    static let shared = ResponseCache()

    /// Read-only cache, even if stale: to show a screen immediately (see `UfolepClient.fromCacheOnly`).
    @TaskLocal static var cacheOnly = false
    /// Ignores the cache and forces the network: pull to refresh (see `UfolepClient.bypassingCache`).
    @TaskLocal static var bypassCache = false

    private struct Entry {
        let data: Data
        let date: Date
    }

    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("ufolep", isDirectory: true)
    private var memory: [String: Entry] = [:]
    private static let maxAge: TimeInterval = 7 * 86_400

    private init() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        purgeExpired()
    }

    /// Entry if it exists, with its age; `nil` otherwise.
    func read(_ url: URL) -> (data: Data, age: TimeInterval)? {
        let key = url.absoluteString
        if let e = memory[key] { return (e.data, Date().timeIntervalSince(e.date)) }
        let f = file(key)
        guard let data = try? Data(contentsOf: f),
              let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate else { return nil }
        memory[key] = Entry(data: data, date: date)
        return (data, Date().timeIntervalSince(date))
    }

    func write(_ data: Data, for url: URL) {
        let key = url.absoluteString
        memory[key] = Entry(data: data, date: Date())
        let f = file(key)
        try? data.write(to: f, options: .atomic)
        try? Data(key.utf8).write(to: f.appendingPathExtension("url"), options: .atomic)
    }

    /// Forgets responses whose path starts with one of the prefixes (e.g. after a registration).
    func invalidate(paths: [String]) {
        let prefixes = paths.map { UfolepClient.baseURL.appending(path: $0).absoluteString }
        for key in memory.keys where prefixes.contains(where: key.hasPrefix) { memory[key] = nil }
        // on disk, the original URL is read from the ".url" file stored next to each response
        for key in index() where prefixes.contains(where: key.hasPrefix) {
            let f = file(key)
            try? FileManager.default.removeItem(at: f)
            try? FileManager.default.removeItem(at: f.appendingPathExtension("url"))
        }
    }

    /// Clears everything (sign-out: this is personal data).
    func clear() {
        memory = [:]
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: files

    /// File name = SHA-256 of the URL; the URL is stored next to it (".url") for invalidation by path.
    private func file(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(name)
    }

    private func index() -> [String] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "url" }.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
    }

    private func purgeExpired() {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for f in files where f.pathExtension != "url" {
            let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if Date().timeIntervalSince(date) > Self.maxAge {
                try? FileManager.default.removeItem(at: f)
                try? FileManager.default.removeItem(at: f.appendingPathExtension("url"))
            }
        }
    }
}
