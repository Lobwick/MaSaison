import Foundation

/// Extraction (volontairement simple) des pages HTML rendues côté serveur.
enum HTMLParsing {
    static func inscriptions(from html: String) -> [Inscription] {
        let cartes = html.split(separator: #/<div class="card\s+border-left-2/#).dropFirst()
        return cartes.compactMap { carte -> Inscription? in
            let c = String(carte)
            guard let titre = c.firstMatch(of: #/(\d{4}) - <a href="[^"]*/manifestations/show/(\d+)">([^<]+)</a>/#),
                  let id = Int(titre.output.2) else { return nil }
            let date = champ("Date", in: c)
            let epreuves = c.split(separator: #/class="card\s+card-epreuve"/#).dropFirst().map { e -> Inscription.Epreuve in
                let e = String(e)
                return .init(
                    type: e.firstMatch(of: #/container-epreuve">[\s\S]*?<span[^>]*>([^<]+)</span>/#).map { clean(String($0.output.1)) } ?? "",
                    statut: e.firstMatch(of: #/text-uppercase[^>]*>(?:\s*<span[^>]*></span>)?([^<]+)</span>/#).map { clean(String($0.output.1)) } ?? "",
                    niveaux: e.matches(of: #/font-weight-semibold">([^<]+)</span>/#).map { clean(String($0.output.1)) }
                )
            }
            return Inscription(
                manifestationID: id,
                libelle: clean(String(titre.output.3)),
                annee: String(titre.output.1),
                organisateur: organisateur(in: c),
                type: champ("Type", in: c),
                dateTexte: date,
                dateDebut: premiereDate(date),
                dateFin: dernieresDates(date),
                epreuves: epreuves
            )
        }
    }

    static func profil(from html: String) -> Profil {
        var p = Profil()
        if let m = html.firstMatch(of: #/src="([^"]*photos_personnes[^"]*)"/#) { p.photoURL = URL(string: String(m.output.1)) }
        if let m = html.firstMatch(of: #/font-weight-semibold text-default d-block">([\s\S]*?)</span>\s*<span class="text-muted">([\s\S]*?)</span>/#) {
            p.nom = clean(String(m.output.1))
            p.numeroLicence = clean(String(m.output.2))
        }
        for m in html.matches(of: #/<td class="text-slate">([\s\S]*?)</td>\s*<td>([\s\S]*?)</td>/#) {
            let valeur: String
            let brut = String(m.output.2)
            if let visible = brut.firstMatch(of: #/d-none d-md-block">([\s\S]*?)</span>/#) {
                valeur = clean(String(visible.output.1))   // téléphones : le HTML contient deux versions
            } else {
                valeur = clean(brut.replacing(#/<br\s*/?>/#, with: ", "))
            }
            if !valeur.isEmpty { p.champs.append((clean(String(m.output.1)), valeur)) }
        }
        return p
    }

    static func cartes(from html: String) -> [Carte] {
        var cartes: [Carte] = []
        for ligne in html.split(separator: #/class="timeline-row"/#).dropFirst() {
            let l = String(ligne)
            guard let saison = l.firstMatch(of: #/<span>(\d{4})</span>/#)?.output.1 else { continue }
            for bloc in l.split(separator: #/class="card panel/#).dropFirst() {
                let b = String(bloc)
                guard let titre = b.firstMatch(of: #/</i>\s*Carte ([^<]+)</h6>/#)?.output.1 else { continue }
                var prise = "", expire = ""
                var age: String?, niveau: String?
                if let ul = b.firstMatch(of: #/<ul class="list list-unstyled text-grey">([\s\S]*?)</ul>/#)?.output.1 {
                    for li in ul.matches(of: #/<li[^>]*>([\s\S]*?)</li>/#) {
                        let t = clean(String(li.output.1))
                        if t.hasPrefix("Prise le") { prise = t.replacing("Prise le ", with: "") }
                        else if t.hasPrefix("Expire le") { expire = t.replacing("Expire le ", with: "") }
                        else if t.hasPrefix("À partir") || t.hasPrefix("Validée") || t.contains("pt(s)") || t.isEmpty { continue }
                        else if t.localizedCaseInsensitiveContains("catégorie") { niveau = t }
                        else { age = t }
                    }
                }
                let structures = b.matches(of: #/badge-proportional mr-1">([^<]+)</span>\s*([^<]+)</span>/#)
                cartes.append(Carte(
                    saison: String(saison),
                    discipline: clean(String(titre)),
                    priseLe: prise,
                    expireLe: expire,
                    categorieAge: age,
                    niveau: niveau,
                    club: structures.first.map { clean(String($0.output.2)) } ?? "",
                    comite: structures.dropFirst().first.map { clean(String($0.output.2)) } ?? "",
                    statut: b.firstMatch(of: #/text-uppercase">\s*([^<]+)</span>/#).map { clean(String($0.output.1)) } ?? ""
                ))
            }
        }
        return cartes
    }

    /// Commandes en attente de paiement : une case `commandes[]` par commande.
    static func commandes(from html: String) -> [Commande] {
        html.split(separator: #/name="commandes\[\]"/#).dropFirst().compactMap { morceau -> Commande? in
            let m = String(morceau)
            guard let id = m.firstMatch(of: #/value="(\d+)"/#).flatMap({ Int($0.output.1) }) else { return nil }
            let montant = m.firstMatch(of: #/data-montant="([\d.]+)"/#).flatMap { Double($0.output.1) } ?? 0
            let ligne = m.firstMatch(of: #/Commande n°\s*(\d+)\s*-\s*([^<]+)</#)
            return Commande(id: id,
                            numero: ligne.map { String($0.output.1) } ?? "",
                            libelle: ligne.map { clean(String($0.output.2)) } ?? "",
                            montant: montant)
        }
    }

    // MARK: helpers

    private static func champ(_ label: String, in html: String) -> String {
        html.firstMatch(of: try! Regex("\(label) : ([^<]+)</li>")).map { clean(String($0.output[1].substring ?? "")) } ?? ""
    }

    /// « 062 UFOLEP 62 » → « UFOLEP 62 »
    private static func organisateur(in html: String) -> String {
        guard let m = html.firstMatch(of: #/Organisateur :([\s\S]*?)</li>/#) else { return "" }
        let texte = clean(String(m.output.1))
        return texte.replacing(#/^\d+\s+/#, with: "")
    }

    private static func premiereDate(_ texte: String) -> Date? {
        guard let first = texte.firstMatch(of: #/\d{2}/\d{2}/\d{4}/#) else { return nil }
        return Date.fr("dd/MM/yyyy").date(from: String(first.output))
    }

    /// Dernière date jj/MM/aaaa d'un texte (« Le 18/10/2026 », « Du 17/10/2026 au 18/10/2026 »).
    private static func dernieresDates(_ texte: String) -> Date? {
        guard let last = texte.matches(of: #/\d{2}/\d{2}/\d{4}/#).last else { return nil }
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
