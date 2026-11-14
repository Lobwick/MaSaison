import Foundation

/// (Deliberately simple) extraction of the server-rendered HTML pages.
enum HTMLParsing {
    static func registrations(from html: String) -> [Registration] {
        let cards = html.split(separator: #/<div class="card\s+border-left-2/#).dropFirst()
        return cards.compactMap { card -> Registration? in
            let c = String(card)
            guard let title = c.firstMatch(of: #/(\d{4}) - <a href="[^"]*/manifestations/show/(\d+)">([^<]+)</a>/#),
                  let id = Int(title.output.2) else { return nil }
            let date = field("Date", in: c)
            let entries = c.split(separator: #/class="card\s+card-epreuve"/#).dropFirst().map { e -> Registration.Entry in
                let e = String(e)
                return .init(
                    type: e.firstMatch(of: #/container-epreuve">[\s\S]*?<span[^>]*>([^<]+)</span>/#).map { clean(String($0.output.1)) } ?? "",
                    status: e.firstMatch(of: #/text-uppercase[^>]*>(?:\s*<span[^>]*></span>)?([^<]+)</span>/#).map { clean(String($0.output.1)) } ?? "",
                    levels: e.matches(of: #/font-weight-semibold">([^<]+)</span>/#).map { clean(String($0.output.1)) }
                )
            }
            return Registration(
                eventID: id,
                name: clean(String(title.output.3)),
                year: String(title.output.1),
                organizer: organizer(in: c),
                type: field("Type", in: c),
                dateText: date,
                startDate: firstDate(date),
                endDate: lastDate(date),
                entries: entries
            )
        }
    }

    /// "Manifestation | Epreuve | Date | Classement" tables of `/manifestations/resultats`.
    static func results(from html: String) -> [RaceResult] {
        html.split(separator: #/<tr[\s>]/#).dropFirst().compactMap { row -> RaceResult? in
            let cells = String(row).matches(of: #/<td[^>]*>([\s\S]*?)</td>/#).map { String($0.output.1) }
            guard cells.count >= 4, let date = firstDate(clean(cells[2])) else { return nil }
            let id = cells[0].firstMatch(of: #/manifestations?/(?:show/)?(\d+)/#).flatMap { Int($0.output.1) }
            let ranking = clean(cells[3])
            guard !ranking.isEmpty else { return nil }
            return RaceResult(eventID: id, name: clean(cells[0]), date: date, ranking: ranking)
        }
    }

    static func profile(from html: String) -> Profile {
        var p = Profile()
        if let m = html.firstMatch(of: #/src="([^"]*photos_personnes[^"]*)"/#) { p.photoURL = URL(string: String(m.output.1).replacingOccurrences(of: "&amp;", with: "&"), relativeTo: UfolepClient.baseURL)?.absoluteURL }
        if let m = html.firstMatch(of: #/font-weight-semibold text-default d-block">([\s\S]*?)</span>\s*<span class="text-muted">([\s\S]*?)</span>/#) {
            p.name = clean(String(m.output.1))
            p.licenseNumber = clean(String(m.output.2))
        }
        for m in html.matches(of: #/<td class="text-slate">([\s\S]*?)</td>\s*<td>([\s\S]*?)</td>/#) {
            let value: String
            let raw = String(m.output.2)
            if let visible = raw.firstMatch(of: #/d-none d-md-block">([\s\S]*?)</span>/#) {
                value = clean(String(visible.output.1))   // phone numbers: the HTML contains two versions
            } else {
                value = clean(raw.replacing(#/<br\s*/?>/#, with: ", "))
            }
            if !value.isEmpty { p.fields.append((clean(String(m.output.1)), value)) }
        }
        return p
    }

    static func cards(from html: String) -> [LicenseCard] {
        var cards: [LicenseCard] = []
        for row in html.split(separator: #/class="timeline-row"/#).dropFirst() {
            let l = String(row)
            guard let season = l.firstMatch(of: #/<span>(\d{4})</span>/#)?.output.1 else { continue }
            for block in l.split(separator: #/class="card panel/#).dropFirst() {
                let b = String(block)
                guard let title = b.firstMatch(of: #/</i>\s*Carte ([^<]+)</h6>/#)?.output.1 else { continue }
                var issued = "", expires = ""
                var age: String?, level: String?
                if let ul = b.firstMatch(of: #/<ul class="list list-unstyled text-grey">([\s\S]*?)</ul>/#)?.output.1 {
                    for li in ul.matches(of: #/<li[^>]*>([\s\S]*?)</li>/#) {
                        let t = clean(String(li.output.1))
                        if t.hasPrefix("Prise le") { issued = t.replacing("Prise le ", with: "") }
                        else if t.hasPrefix("Expire le") { expires = t.replacing("Expire le ", with: "") }
                        else if t.hasPrefix("À partir") || t.hasPrefix("Validée") || t.contains("pt(s)") || t.isEmpty { continue }
                        else if t.localizedCaseInsensitiveContains("catégorie") { level = t }
                        else { age = t }
                    }
                }
                let structures = b.matches(of: #/badge-proportional mr-1">([^<]+)</span>\s*([^<]+)</span>/#)
                cards.append(LicenseCard(
                    season: String(season),
                    discipline: clean(String(title)),
                    issuedOn: issued,
                    expiresOn: expires,
                    ageCategory: age,
                    level: level,
                    club: structures.first.map { clean(String($0.output.2)) } ?? "",
                    committee: structures.dropFirst().first.map { clean(String($0.output.2)) } ?? "",
                    status: b.firstMatch(of: #/text-uppercase">\s*([^<]+)</span>/#).map { clean(String($0.output.1)) } ?? ""
                ))
            }
        }
        return cards
    }

    /// Orders awaiting payment: one `commandes[]` checkbox per order.
    static func orders(from html: String) -> [Order] {
        html.split(separator: #/name="commandes\[\]"/#).dropFirst().compactMap { chunk -> Order? in
            let m = String(chunk)
            guard let id = m.firstMatch(of: #/value="(\d+)"/#).flatMap({ Int($0.output.1) }) else { return nil }
            let amount = m.firstMatch(of: #/data-montant="([\d.]+)"/#).flatMap { Double($0.output.1) } ?? 0
            let row = m.firstMatch(of: #/Commande n°\s*(\d+)\s*-\s*([^<]+)</#)
            return Order(id: id,
                            number: row.map { String($0.output.1) } ?? "",
                            name: row.map { clean(String($0.output.2)) } ?? "",
                            amount: amount)
        }
    }

    // MARK: helpers

    private static func field(_ label: String, in html: String) -> String {
        html.firstMatch(of: try! Regex("\(label) : ([^<]+)</li>")).map { clean(String($0.output[1].substring ?? "")) } ?? ""
    }

    /// "062 UFOLEP 62" → "UFOLEP 62"
    private static func organizer(in html: String) -> String {
        guard let m = html.firstMatch(of: #/Organisateur :([\s\S]*?)</li>/#) else { return "" }
        let text = clean(String(m.output.1))
        return text.replacing(#/^\d+\s+/#, with: "")
    }

    private static func firstDate(_ text: String) -> Date? {
        guard let first = text.firstMatch(of: #/\d{2}/\d{2}/\d{4}/#) else { return nil }
        return Date.fr("dd/MM/yyyy").date(from: String(first.output))
    }

    /// Last dd/MM/yyyy date of a text ("Le 18/10/2026", "Du 17/10/2026 au 18/10/2026").
    private static func lastDate(_ text: String) -> Date? {
        guard let last = text.matches(of: #/\d{2}/\d{2}/\d{4}/#).last else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "dd/MM/yyyy"
        return f.date(from: String(last.output))
    }

    static func clean(_ html: String) -> String {
        html.replacing(#/<[^>]+>/#, with: " ")
            .replacingOccurrences(of: "&#039;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: " ,", with: ",")
    }
}
