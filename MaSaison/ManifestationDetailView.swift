import Charts
import MapKit
import SwiftUI

/// Détail d'une manifestation : statut d'inscription, mes courses, lieu et tracé, autres courses.
struct ManifestationDetailView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(CartesStore.self) private var cartes
    @Environment(AgendaStore.self) private var agenda
    @AppStorage("boutonAgenda") private var boutonAgenda = true
    @AppStorage("echauffementMinutes") private var echauffement = 60

    let manifestation: Manifestation
    @State private var groupes: [GroupeNiveaux] = []
    @State private var errorMessage: String?
    @State private var trace: GPXTrack?
    @State private var fichierGPX: URL?
    @State private var autresOuvert = false
    @State private var erreurAgenda: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                entete

                if !miennes.isEmpty { AstuceView(tip: AppTips.detail) }

                if miennes.isEmpty {
                    if !autres.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Eyebrow("COURSES")
                            VStack(spacing: 0) { ForEach(autres, id: \.course.id) { ligneAutre($0) } }.card(padding: 4)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow("POUR MOI", color: Theme.accent)
                        ForEach(miennes, id: \.course.id) { carteCourse($0.course, groupe: $0.groupe) }
                    }
                }

                lieuEtTrace

                if !miennes.isEmpty && !autres.isEmpty { autresCourses }

                if let nom = manifestation.structure?.nom {
                    VStack(alignment: .leading, spacing: 6) {
                        Eyebrow("ORGANISATEUR")
                        Text(nom).font(.barlow(16)).foregroundStyle(Theme.text)
                    }
                }

                if let errorMessage { Text(errorMessage).font(.barlow(14)).foregroundStyle(Theme.danger) }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
        }
        .screenBackground()
        .toolbarBackground(.hidden, for: .navigationBar)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await charger() }
    }

    // MARK: données

    private var toutes: [(groupe: String, course: ConfigNiveau)] {
        groupes.flatMap { groupe in
            manifestation.configNiveaux
                .filter { $0.niveau.groupeId == groupe.id }
                .sorted { ($0.niveau.position ?? 0) < ($1.niveau.position ?? 0) }
                .map { (groupe.libelle, $0) }
        }
    }
    private var miennes: [(groupe: String, course: ConfigNiveau)] { toutes.filter { cartes.correspond(course: $0.course, in: manifestation) } }
    private var autres: [(groupe: String, course: ConfigNiveau)] { toutes.filter { !cartes.correspond(course: $0.course, in: manifestation) } }

    private func charger() async {
        do {
            groupes = try await auth.withSession { try await auth.client.fetchGroupes(manifestationID: manifestation.id) }
        } catch {
            errorMessage = error.localizedDescription
        }
        if let url = manifestation.gpxURL, let data = try? await auth.client.download(url) {
            trace = GPXTrack.parse(data)
            let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("\(manifestation.libelle.capitalized).gpx")
            if (try? data.write(to: fichier)) != nil { fichierGPX = fichier }
        }
    }

    // MARK: en-tête

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow([manifestation.modele?.libelle, manifestation.structure?.nom].compactMap { $0 }.joined(separator: " · "))
            Text(manifestation.libelle).font(.cond(52)).textCase(.uppercase).foregroundStyle(Theme.text)
                .lineSpacing(-6).fixedSize(horizontal: false, vertical: true)
            if let debut = manifestation.debutDate {
                Text(dateTexte(debut)).font(.cond(20, .semibold)).tracking(1).foregroundStyle(Theme.textSoft)
            }
            StatutBadge(statut: statut)
        }
    }

    private func dateTexte(_ debut: Date) -> String {
        let f = Date.fr("EEE d MMMM yyyy")
        var s = f.string(from: debut).uppercased().replacingOccurrences(of: ".", with: ".")
        if let fin = Date.fr("dd/MM/yyyy").date(from: manifestation.dateFin), fin > debut {
            s += " → " + Date.fr("EEE d MMMM").string(from: fin).uppercased()
        }
        return s
    }

    // MARK: statut d'inscription

    private var statut: Statut {
        let now = Date()
        let debut = manifestation.datesInscriptionStart ?? ""
        let fin = manifestation.datesInscriptionEnd ?? ""
        if let start = Self.parse(manifestation.datesInscriptionStart, manifestation.horaireInscriptionStart), now < start {
            return .aVenir("Inscriptions ouvrent le \(debut)")
        }
        if let end = Self.parse(manifestation.datesInscriptionEnd, manifestation.horaireInscriptionEnd), now > end {
            return .ferme("Inscriptions fermées depuis le \(fin)")
        }
        guard manifestation.inscriptible == true else { return .ferme("Inscriptions fermées") }
        return .ouvert(fin.isEmpty ? "Inscriptions ouvertes" : "Inscriptions ouvertes jusqu'au \(fin)")
    }

    private static func parse(_ date: String?, _ heure: String?) -> Date? {
        guard let date else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "dd/MM/yyyy HH:mm"
        return f.date(from: "\(date) \(heure ?? "00:00")")
    }

    enum Statut {
        case ouvert(String), ferme(String), aVenir(String)
    }

    // MARK: ma course

    private func carteCourse(_ course: ConfigNiveau, groupe: String) -> some View {
        let infos = course.infos
        let creneau = AgendaService.creneau(manifestation: manifestation, course: course, echauffementMinutes: echauffement)
        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(groupe).font(.barlow(13)).foregroundStyle(Theme.muted)
                Text(course.niveau.libelle).font(.cond(30)).textCase(.uppercase).foregroundStyle(Theme.text)
            }
            if infos.isEmpty {
                Text("Horaires non communiqués").font(.barlow(14)).foregroundStyle(Theme.muted)
            } else {
                HStack(spacing: 10) {
                    tuile("APPEL", infos.heure ?? "—")
                    tuile("DÉPART", infos.heureDepart ?? "—", accent: true)
                    tuile("TOURS", infos.nbTours ?? infos.km ?? "—", suffixe: tours(infos))
                }
                if let creneau, echauffement > 0 {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Eyebrow("ÉCHAUFFEMENT")
                            Text(creneau.echauffement.formatted(heure)).font(.cond(34)).foregroundStyle(Theme.warning)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("\(dureeTexte(echauffement)) avant l'appel").font(.barlow(13, .semibold)).foregroundStyle(Theme.textSoft)
                            Text("Réglable dans Profil").font(.barlow(12)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            if case .ouvert = statut { InscriptionBloc(manifestation: manifestation, course: course) }
            if boutonAgenda, let creneau { boutonAgendaView(course: course, creneau: creneau) }
        }
        .card(border: Theme.accent, radius: 24, padding: 18)
    }

    private func tuile(_ titre: String, _ valeur: String, accent: Bool = false, suffixe: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Eyebrow(titre).font(.cond(11, .semibold))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(valeur).font(.cond(34)).foregroundStyle(accent ? Theme.accent : Theme.text)
                if let suffixe { Text(suffixe).font(.cond(15, .semibold)).foregroundStyle(Theme.muted) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func tours(_ infos: ConfigNiveau.Infos) -> String? {
        if infos.nbTours != nil { return infos.distanceTour.map { "× \($0) km" } }
        if infos.km != nil { return "km" }
        return nil
    }

    private func dureeTexte(_ minutes: Int) -> String {
        minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) h" : String(format: "%d h %02d", minutes / 60, minutes % 60)
    }

    // MARK: agenda

    @ViewBuilder
    private func boutonAgendaView(course: ConfigNiveau, creneau: AgendaService.Creneau) -> some View {
        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let plage = "\(creneau.debut.formatted(heure)) – \(creneau.fin.formatted(heure))"
        let ajoute = agenda.ajoute(manifestation: manifestation.id, course: course.id)
        VStack(spacing: 10) {
            if ajoute {
                Label("Ajouté à l'agenda · \(plage)", systemImage: "checkmark.circle.fill")
                    .font(.cond(17)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.accent, lineWidth: 1))
                #if os(iOS)
                Link("Ouvrir dans Calendrier", destination: URL(string: "calshow:\(creneau.debut.timeIntervalSinceReferenceDate)")!)
                    .font(.cond(15, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.textSoft)
                #endif
            } else {
                Button { ajouter(course) } label: {
                    Label("Ajouter à l'agenda · \(plage)", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(PrimaryButtonStyle())
                Text(manifestation.gpxURL != nil ? "L'événement agenda inclut le lieu et le lien du tracé GPX." : "L'événement agenda inclut le lieu.")
                    .font(.barlow(12)).foregroundStyle(Theme.muted)
            }
            if let erreurAgenda { Text(erreurAgenda).font(.barlow(13)).foregroundStyle(Theme.danger) }
        }
    }

    private func ajouter(_ course: ConfigNiveau) {
        erreurAgenda = nil
        Task {
            do {
                let id = try await AgendaService.ajouter(manifestation: manifestation, course: course, echauffementMinutes: echauffement)
                agenda.enregistrer(manifestation: manifestation.id, course: course.id, identifiant: id)
            } catch {
                erreurAgenda = error.localizedDescription
            }
        }
    }

    // MARK: lieu et tracé

    private var lieuEtTrace: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("LIEU ET TRACÉ")
            if let adresse = manifestation.adresse {
                VStack(spacing: 0) {
                    carte(adresse: adresse)
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            if !adresse.rue.isEmpty { Text(adresse.rue.capitalized).font(.barlow(15, .semibold)).foregroundStyle(Theme.text) }
                            Text((adresse.commune ?? "").capitalized).font(.barlow(15, .semibold)).foregroundStyle(Theme.text)
                            Text(adresse.codePostalFr ?? "")
                                .font(.barlow(14)).foregroundStyle(Theme.muted)
                        }
                        Spacer()
                        if let c = adresse.coordinate {
                            Link(destination: URL(string: "http://maps.apple.com/?ll=\(c.latitude),\(c.longitude)&q=\(manifestation.libelle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")")!) {
                                Text("Ouvrir dans Plans").font(.cond(13, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            if let trace {
                if trace.aProfil { profilAltimetrique(trace) }
                if let fichierGPX {
                    ShareLink(item: fichierGPX) {
                        Label("Télécharger le tracé GPX", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(OutlineButtonStyle())
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
    private func carte(adresse: Manifestation.Adresse) -> some View {
        if let c = adresse.coordinate {
            let centre = CLLocationCoordinate2D(latitude: c.latitude, longitude: c.longitude)
            Map(initialPosition: region(centre: centre)) {
                if let trace {
                    MapPolyline(coordinates: trace.coordinates).stroke(Theme.accent, lineWidth: 4)
                    if let depart = trace.coordinates.first {
                        Annotation("Départ · arrivée", coordinate: depart) {
                            Circle().fill(Theme.accent).frame(width: 14, height: 14).overlay(Circle().stroke(Theme.bg, lineWidth: 3))
                        }
                    }
                } else {
                    // pas de tracé : on montre toujours le pin du lieu de départ
                    Marker(manifestation.libelle.capitalized, coordinate: centre).tint(Theme.accent)
                }
            }
            .mapStyle(.standard(elevation: .flat))
            .frame(height: 200)
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                if let trace {
                    Text("TRACÉ GPX · \(trace.distanceKm.formatted(.number.precision(.fractionLength(1)))) KM")
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

    private func region(centre: CLLocationCoordinate2D) -> MapCameraPosition {
        if let trace, trace.coordinates.count > 1 {
            return .rect(MKMapRect(coordinates: trace.coordinates).insetBy(dx: -500, dy: -500))
        }
        return .region(MKCoordinateRegion(center: centre, latitudinalMeters: 3000, longitudinalMeters: 3000))
    }

    private func profilAltimetrique(_ trace: GPXTrack) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("PROFIL ALTIMÉTRIQUE")
            Chart(Array(trace.points.enumerated()), id: \.offset) { _, p in
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
                tuile("D+", trace.denivelePositif.formatted(.number.precision(.fractionLength(0))), suffixe: "m")
                tuile("ALT. MAX", (trace.altitudeMax ?? 0).formatted(.number.precision(.fractionLength(0))), suffixe: "m")
                tuile("ALT. MIN", (trace.altitudeMin ?? 0).formatted(.number.precision(.fractionLength(0))), suffixe: "m")
            }
        }
        .card(radius: 24, padding: 16)
    }

    // MARK: autres courses

    private var autresCourses: some View {
        VStack(spacing: 0) {
            Button { withAnimation { autresOuvert.toggle() } } label: {
                HStack {
                    Text("Autres courses").font(.cond(17, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.text)
                    Text("(\(autres.count))").font(.cond(17, .semibold)).foregroundStyle(Theme.muted)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 14, weight: .bold)).foregroundStyle(Theme.muted)
                        .rotationEffect(.degrees(autresOuvert ? 180 : 0))
                }
                .padding(18)
            }
            .buttonStyle(.plain)
            if autresOuvert {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(groupes) { groupe in
                        let lignes = autres.filter { $0.groupe == groupe.libelle }
                        if !lignes.isEmpty {
                            Eyebrow(groupe.libelle).padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 4)
                            ForEach(lignes, id: \.course.id) { ligneAutre($0) }
                        }
                    }
                }
                .padding(.bottom, 12)
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    private func ligneAutre(_ item: (groupe: String, course: ConfigNiveau)) -> some View {
        let infos = item.course.infos
        let creneau = AgendaService.creneau(manifestation: manifestation, course: item.course, echauffementMinutes: echauffement)
        let ajoute = agenda.ajoute(manifestation: manifestation.id, course: item.course.id)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.course.niveau.libelle).font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                Text(infos.isEmpty ? "Horaires non communiqués" : [infos.heure.map { "Appel \($0)" }, infos.heureDepart.map { "Départ \($0)" }, infos.nbTours.map { n in infos.distanceTour.map { "\(n) × \($0) km" } ?? "\(n) tours" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.barlow(13)).foregroundStyle(Theme.muted)
            }
            Spacer()
            if boutonAgenda, creneau != nil {
                Button { ajouter(item.course) } label: {
                    Image(systemName: ajoute ? "checkmark.circle.fill" : "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold)).foregroundStyle(ajoute ? Theme.accent : Theme.textSoft)
                        .frame(width: 44, height: 44)
                }
                .disabled(ajoute)
                .accessibilityLabel(ajoute ? "Déjà dans l'agenda" : "Ajouter à l'agenda")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 6)
    }
}

private struct StatutBadge: View {
    let statut: ManifestationDetailView.Statut

    var body: some View {
        let (texte, couleur, icone): (String, Color, String) = switch statut {
        case .ouvert(let t): (t, Theme.accent, "checkmark.circle")
        case .ferme(let t): (t, Theme.danger, "xmark.circle")
        case .aVenir(let t): (t, Theme.warning, "clock")
        }
        Label(texte, systemImage: icone)
            .font(.barlow(14, .bold))
            .foregroundStyle(couleur)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(couleur.opacity(0.14), in: Capsule())
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
