import Charts
import MapKit
import QuickLook
import SwiftUI

/// Détail d'une manifestation : statut d'inscription, mes courses, lieu et tracé, autres courses.
struct ManifestationDetailView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(CartesStore.self) private var cartes
    @Environment(AgendaStore.self) private var agenda
    @Environment(SuiviCoursesStore.self) private var suivi
    @AppStorage("boutonAgenda") private var boutonAgenda = true
    @AppStorage("echauffementMinutes") private var echauffement = 60
    @Environment(\.dismiss) private var dismiss

    let manifestation: Manifestation
    @State private var groupes: [GroupeNiveaux] = []
    @State private var errorMessage: String?
    @State private var trace: GPXTrack?
    @State private var fichierGPX: URL?
    @State private var autresOuvert = false
    @State private var erreurAgenda: String?
    @State private var meteo: Meteo?
    @State private var erreurMeteo: String?
    @State private var traceCharge = false
    @State private var meteoCharge = false
    @State private var trajet: Trajet?
    @State private var trajetEnCours = false
    @State private var infoAgenda: String?
    @State private var erreurTrajet: String?
    @State private var majTrajetEnCours = false
    @State private var mentionMeteo: MeteoAttribution?
    @State private var apercu: URL?
    @State private var documentEnCours: URL?
    @State private var erreurDocument: String?
    @State private var correspondant: Correspondant?
    @State private var photoProfil: UIImage?

    var body: some View {
        ScrollView(.vertical) {
            LazyVStack(alignment: .leading, spacing: 22) {
                barreNavigationDetail
                entete

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

                if meteoDisponible { meteoSection }

                lieuEtTrace

                if !miennes.isEmpty && !autres.isEmpty { autresCourses }

                if !manifestation.documentsPDF.isEmpty { documentsSection }

                organisateurSection

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
        // trois chargements indépendants, lancés dès l'ouverture : aucun n'attend les autres
        .task { await charger() }
        .task { await chargerTrace() }
        .task { await chargerMeteo() }
        .task { correspondant = try? await auth.withSession { try await auth.client.fetchCorrespondant(manifestationID: manifestation.id) } }
        .task { await chargerPhotoProfil() }
        .task {
            suivi.memoriser([manifestation])
            await suivi.actualiser(auth)
        }
        // déjà autorisé : le trajet se calcule sans rien demander ; sinon un bouton propose de le faire
        .task { if TrajetService.autorise { await calculerTrajet() } }
        .quickLookPreview($apercu)
    }

    // MARK: documents et organisateur

    private var documentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("DOCUMENTS")
            VStack(spacing: 0) {
                ForEach(Array(manifestation.documentsPDF.enumerated()), id: \.offset) { _, doc in
                    Button { Task { await ouvrir(doc.url, libelle: doc.libelle) } } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "doc.text").foregroundStyle(Theme.accent)
                            Text(doc.libelle).font(.barlow(16, .semibold)).foregroundStyle(Theme.text)
                            Spacer()
                            if documentEnCours == doc.url { ProgressView().controlSize(.small) }
                            else { Image(systemName: "chevron.right").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted) }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 48)
                    }
                    .buttonStyle(.plain)
                    .disabled(documentEnCours != nil)
                }
            }
            .card(padding: 4)
            if let erreurDocument { Text(erreurDocument).font(.barlow(13)).foregroundStyle(Theme.danger) }
        }
    }

    /// Télécharge le PDF avec la session du licencié puis l'ouvre dans l'aperçu QuickLook.
    private func ouvrir(_ url: URL, libelle: String) async {
        erreurDocument = nil
        documentEnCours = url
        defer { documentEnCours = nil }
        do {
            let data = try await auth.client.download(url)
            let nom = "\(manifestation.libelle.capitalized) - \(libelle)".replacingOccurrences(of: "/", with: "-")
            let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("\(nom).pdf")
            try data.write(to: fichier)
            apercu = fichier
        } catch {
            erreurDocument = "Impossible d'ouvrir « \(libelle) » : \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var organisateurSection: some View {
        if let structure = manifestation.structure {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow("ORGANISATEUR")
                Text(structure.nom).font(.barlow(16)).foregroundStyle(Theme.text)
                if let nom = correspondant?.nomComplet {
                    Text("Correspondant : \(nom)").font(.barlow(14)).foregroundStyle(Theme.muted)
                }
                if let correspondant, correspondant.telephoneURL != nil || correspondant.emailURL != nil {
                    VStack(spacing: 8) {
                        if let tel = correspondant.telephoneURL {
                            Link(destination: tel) {
                                ActionRowLabel(titre: "Appeler", sousTitre: correspondant.numSpecifique, icone: "phone")
                            }
                            .buttonStyle(ActionRowStyle())
                        }
                        if let mail = correspondant.emailURL {
                            Link(destination: mail) {
                                ActionRowLabel(titre: "Écrire", sousTitre: correspondant.mailSpecifique, icone: "envelope")
                            }
                            .buttonStyle(ActionRowStyle())
                        }
                    }
                }
            }
        }
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
    }

    /// Tracé GPX : téléchargé en parallèle à l'ouverture ; la carte et le profil se mettent à jour à l'arrivée.
    private func chargerTrace() async {
        guard !traceCharge else { return }
        traceCharge = true
        guard let url = manifestation.gpxURL, let data = try? await auth.client.download(url) else { return }
        trace = GPXTrack.parse(data)
        let fichier = FileManager.default.temporaryDirectory.appendingPathComponent("\(manifestation.libelle.capitalized).gpx")
        if (try? data.write(to: fichier)) != nil { fichierGPX = fichier }
    }

    /// Météo : demandée en parallèle à l'ouverture ; la carte se met à jour à l'arrivée.
    private func chargerMeteo() async {
        guard !meteoCharge else { return }
        meteoCharge = true
        guard let debut = manifestation.debutDate else { erreurMeteo = MeteoDiagnostic.dateIllisible(manifestation.dateDebut).localizedDescription; return }
        guard let c = manifestation.adresse?.coordinate else { erreurMeteo = MeteoDiagnostic.pasDeCoordonnees.localizedDescription; return }
        do {
            meteo = try await MeteoService.prevision(latitude: c.latitude, longitude: c.longitude, jour: debut)
            if meteo != nil { mentionMeteo = await MeteoService.attribution() }
        } catch {
            erreurMeteo = "\(error.localizedDescription)\n\(String(describing: error))"
        }
    }

    /// Temps de trajet depuis ma position (demande l'autorisation la première fois).
    private func calculerTrajet() async {
        guard let c = manifestation.adresse?.coordinate, !trajetEnCours else { return }
        trajetEnCours = true
        defer { trajetEnCours = false }
        do {
            trajet = try await TrajetService.trajet(versLatitude: c.latitude, longitude: c.longitude)
            erreurTrajet = nil
        } catch {
            erreurTrajet = error.localizedDescription
        }
    }

    @ViewBuilder
    private var trajetLigne: some View {
        if let trajet {
            Label(trajet.texte, systemImage: "car.fill")
                .font(.barlow(13, .semibold)).foregroundStyle(Theme.accent).padding(.top, 4)
        } else if trajetEnCours {
            ProgressView().controlSize(.small).padding(.top, 4)
        } else if let erreurTrajet {
            Text(erreurTrajet).font(.barlow(12)).foregroundStyle(Theme.danger).padding(.top, 4)
        } else if TrajetService.nonDemande, manifestation.adresse?.coordinate != nil {
            VStack(alignment: .leading, spacing: 2) {
                Button { Task { await calculerTrajet() } } label: {
                    Label("Temps de trajet depuis ma position", systemImage: "car")
                        .font(.barlow(13, .semibold)).foregroundStyle(Theme.accent)
                }
                Text("Ta position sert uniquement à ce calcul.").font(.barlow(11)).foregroundStyle(Theme.muted)
            }
            .padding(.top, 4)
        }
    }

    // MARK: météo

    private var meteoDisponible: Bool {
        guard let debut = manifestation.debutDate, manifestation.adresse?.coordinate != nil else { return false }
        return MeteoService.dansHorizon(debut)
    }

    @ViewBuilder
    private var meteoSection: some View {
        Group {
            if let meteo {
                meteoCarte(meteo)
            } else if let erreurMeteo {
                VStack(alignment: .leading, spacing: 6) {
                    Eyebrow("MÉTÉO")
                    Text("Météo indisponible").font(.barlow(15, .semibold)).foregroundStyle(Theme.textSoft)
                    Text(erreurMeteo).font(.barlow(12)).foregroundStyle(Theme.muted).textSelection(.enabled)
                }
                .card(radius: 24, padding: 16)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 150)
            }
        }
    }

    /// Créneau des courses (de l'appel à l'arrivée) : les miennes, sinon toutes ; `nil` si aucun horaire.
    private var creneauCourses: DateInterval? {
        AgendaService.plage(manifestation: manifestation, courses: (miennes.isEmpty ? toutes : miennes).map(\.course))
    }

    private func meteoCarte(_ jour: Meteo) -> some View {
        let m = creneauCourses.map { jour.pendant($0) } ?? jour
        func degres(_ t: Double) -> String { "\(Int(t.rounded()))°" }
        let heure = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "fr_FR"))
        let temperature = Int(m.tempMin.rounded()) == Int(m.tempMax.rounded())
            ? degres(m.tempMax) : "\(degres(m.tempMin)) – \(degres(m.tempMax))"
        let pluie = m.pluieMm >= 0.1 ? String(format: "%.1f mm", m.pluieMm).replacingOccurrences(of: ".", with: ",") : "Sec"
        let rafales = m.rafalesKmh.map { "Rafales \(Int($0.rounded()))" } ?? "km/h"
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Eyebrow("MÉTÉO")
                Spacer()
                Text(m.plage.map { "\($0.start.formatted(heure)) – \($0.end.formatted(heure))" } ?? "Journée")
                    .font(.barlow(12, .semibold)).foregroundStyle(Theme.muted)
            }
            HStack(spacing: 14) {
                IconeMeteo(symbole: m.symbole, taille: 44)
                    .frame(width: 56)
                VStack(alignment: .leading, spacing: 0) {
                    Text(temperature).font(.cond(36)).foregroundStyle(Theme.text)
                    Text(m.libelle).font(.barlow(15, .semibold)).foregroundStyle(Theme.textSoft)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                tuileMeteo(icone: "thermometer.medium", couleur: .orange, titre: "TEMP.", valeur: degres(m.tempMax), detail: "min \(degres(m.tempMin))")
                tuileMeteo(icone: "cloud.rain.fill", couleur: .blue, titre: "PLUIE", valeur: "\(m.probaPluie)%", detail: pluie)
                tuileMeteo(icone: "wind", couleur: .teal, titre: "VENT", valeur: "\(Int(m.ventKmh.rounded()))", detail: rafales)
            }
            HStack(spacing: 10) {
                Text(m.plage == nil ? "Prévision pour le jour de l'épreuve" : "Prévision pendant la course")
                    .font(.barlow(12)).foregroundStyle(Theme.muted)
                Spacer()
                if let mention = mentionMeteo {
                    VStack(alignment: .trailing, spacing: 2) {
                        // les cartes sont claires même en mode sombre forcé : logo pour fond clair
                        AsyncImage(url: mention.logoClair) { $0.resizable().scaledToFit() } placeholder: { Color.clear }
                            .frame(height: 14)
                        Link("Autres sources de données", destination: mention.mentionsLegales)
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

    private func tuileMeteo(icone: String, couleur: Color, titre: String, valeur: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: icone).symbolRenderingMode(.hierarchical).foregroundStyle(couleur)
                    .font(.system(size: 13, weight: .semibold))
                Text(titre).font(.barlow(10, .semibold)).tracking(1).foregroundStyle(Theme.muted)
            }
            Text(valeur).font(.cond(26)).foregroundStyle(Theme.text)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(detail).font(.barlow(11)).foregroundStyle(Theme.muted)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }

    // MARK: en-tête

    private var barreNavigationDetail: some View {
        // retour, nom de la manifestation (titre de la page, sur plusieurs lignes si besoin), puis notifications / profil
        HStack(alignment: .top, spacing: 12) {
            HeaderCircleButton(systemImage: "chevron.left", label: "Retour") { dismiss() }
            Text(manifestation.libelle)
                .font(.cond(28)).textCase(.uppercase).foregroundStyle(Theme.text)
                .lineSpacing(-2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)
                .accessibilityAddTraits(.isHeader)
            ProfileActions(photo: photoProfil, accent: Theme.accent)
        }
        .padding(.top, 4)
    }

    private var entete: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                if let debut = manifestation.debutDate {
                    Text(dateTexte(debut)).font(.barlow(14, .semibold)).tracking(0.6).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                BoutonEnvie(manifestation: manifestation, taille: 22)
            }
            statutBandeau
        }
    }

    private func dateTexte(_ debut: Date) -> String {
        let f = Date.fr("EEEE d MMMM yyyy")
        var s = f.string(from: debut).uppercased().replacingOccurrences(of: ".", with: ".")
        if let fin = Date.fr("dd/MM/yyyy").date(from: manifestation.dateFin), fin > debut {
            s += " → " + Date.fr("EEE d MMMM").string(from: fin).uppercased()
        }
        return s
    }

    private func chargerPhotoProfil() async {
        do {
            let profil = try await auth.withSession { try await auth.client.fetchProfil() }
            guard let url = profil.photoURL else { return }
            if let data = try? await auth.withSession({ try await auth.client.download(url) }) {
                photoProfil = UIImage(data: data)
            }
        } catch {
            photoProfil = nil
        }
    }

    // MARK: statut d'inscription

    private var statut: Statut {
        let now = Date()
        let debut = Self.dateHeure(manifestation.datesInscriptionStart, manifestation.horaireInscriptionStart)
        let fin = Self.dateHeure(manifestation.datesInscriptionEnd, manifestation.horaireInscriptionEnd)
        if let start = Self.parse(manifestation.datesInscriptionStart, manifestation.horaireInscriptionStart), now < start {
            return .aVenir("Inscriptions ouvrent le \(debut)")
        }
        if let end = manifestation.clotureInscriptions, now > end {
            return .ferme("Inscriptions fermées depuis le \(fin)")
        }
        guard manifestation.inscriptible == true else { return .ferme("Inscriptions fermées") }
        return .ouvert(fin.isEmpty ? "Inscriptions ouvertes" : "Inscriptions ouvertes jusqu'au \(fin)")
    }

    /// « 18/11/2026 - 23:59 » ; la date seule si l'heure manque.
    private static func dateHeure(_ date: String?, _ heure: String?) -> String {
        guard let date, !date.isEmpty else { return "" }
        guard let h = heureCourte(heure) else { return date }
        return "\(date) - \(h)"
    }

    /// « 23:59:00 » ou « 23:59 » → « 23:59 ».
    private static func heureCourte(_ heure: String?) -> String? {
        guard let h = heure?.trimmingCharacters(in: .whitespaces), h.count >= 5 else { return nil }
        return String(h.prefix(5))
    }

    private static func parse(_ date: String?, _ heure: String?) -> Date? {
        Manifestation.dateInscription(date, heure)
    }

    enum Statut {
        case ouvert(String), ferme(String), aVenir(String)
    }

    @ViewBuilder
    private var statutBandeau: some View {
        switch statut {
        case .ferme(let texte):
            Label(texte, systemImage: "lock.fill")
                .font(.barlow(13, .semibold))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.danger.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.danger.opacity(0.2), lineWidth: 1))
        default:
            StatutBadge(statut: statut)
        }
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
                HStack(spacing: 0) {
                    bandeauColonne("ÉCHAUFF.", valeur: creneau.map { $0.echauffement.formatted(heure) } ?? "—", accent: .warning)
                    separateurBandeau
                    bandeauColonne("APPEL", valeur: infos.heure ?? "—")
                    separateurBandeau
                    bandeauColonne("DÉPART", valeur: infos.heureDepart ?? "—", accent: .accent)
                    separateurBandeau
                    bandeauColonne("TOURS", valeur: infos.nbTours ?? infos.km ?? "—", suffixe: tours(infos))
                }
                .padding(10)
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            if case .ouvert = statut { InscriptionBloc(manifestation: manifestation, course: course) }
            if boutonAgenda, let creneau { boutonAgendaView(course: course, creneau: creneau) }
        }
        .padding(18)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
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

    private var separateurBandeau: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(width: 1, height: 46)
            .padding(.horizontal, 6)
    }

    @ViewBuilder
    private func bandeauColonne(_ titre: String, valeur: String, accent: ThemeAccent? = nil, suffixe: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(titre)
                .font(.barlow(10, .semibold))
                .tracking(0.8)
                .foregroundStyle(accent?.color ?? Theme.muted)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valeur)
                    .font(.barlow(17, .semibold))
                    .foregroundStyle(accent?.color ?? Theme.text)
                    .lineLimit(1)
                if let suffixe {
                    Text(suffixe)
                        .font(.barlow(11, .semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                HStack(spacing: 12) {
                    Label("Inscrit à l'agenda (\(plage))", systemImage: "checkmark.circle.fill")
                        .font(.barlow(13, .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer()
                    if manifestation.adresse?.coordinate != nil {
                        Button {
                            majTrajet(course)
                        } label: {
                            Label("TRAJET", systemImage: "car")
                                .font(.barlow(12, .semibold))
                                .foregroundStyle(Theme.text)
                        }
                        .buttonStyle(.plain)
                        .disabled(majTrajetEnCours)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            } else {
                ActionRow(titre: "Ajouter à l'agenda", sousTitre: "\(plage) · \(texteInclus)",
                          icone: "calendar.badge.plus") { ajouter(course) }
            }
            if let infoAgenda { Text(infoAgenda).font(.barlow(13)).foregroundStyle(Theme.accent) }
            if let erreurAgenda { Text(erreurAgenda).font(.barlow(13)).foregroundStyle(Theme.danger) }
        }
    }

    /// Ce que contiendra l'événement ; le trajet n'y est que si la position est déjà autorisée.
    private var texteInclus: String {
        var elements = ["lieu"]
        if manifestation.gpxURL != nil { elements.append("tracé GPX") }
        if trajet != nil || TrajetService.autorise { elements.append("trajet") }
        return elements.formatted(.list(type: .and, width: .standard).locale(Locale(identifier: "fr_FR"))) + " inclus"
    }

    private func ajouter(_ course: ConfigNiveau) {
        erreurAgenda = nil
        infoAgenda = nil
        Task {
            do {
                // trajet : seulement si la position est déjà autorisée (pas de nouvelle invite au moment d'ajouter)
                if trajet == nil, TrajetService.autorise { await calculerTrajet() }
                let id = try await AgendaService.ajouter(manifestation: manifestation, course: course, echauffementMinutes: echauffement, trajet: trajet)
                agenda.enregistrer(manifestation: manifestation.id, course: course.id, identifiant: id)
                if trajet == nil {
                    infoAgenda = "Événement créé sans temps de trajet. "
                        + (erreurTrajet ?? "Touche « Mettre à jour le temps de trajet » pour l'ajouter (la position est demandée une seule fois).")
                }
            } catch {
                erreurAgenda = error.localizedDescription
            }
        }
    }

    /// Recalcule le trajet depuis ma position actuelle et met à jour l'événement déjà créé.
    private func majTrajet(_ course: ConfigNiveau) {
        erreurAgenda = nil
        infoAgenda = nil
        guard let c = manifestation.adresse?.coordinate,
              let identifiant = agenda.identifiant(manifestation: manifestation.id, course: course.id) else { return }
        majTrajetEnCours = true
        Task {
            defer { majTrajetEnCours = false }
            let nouveau: Trajet
            do {
                nouveau = try await TrajetService.trajet(versLatitude: c.latitude, longitude: c.longitude)
            } catch {
                erreurAgenda = error.localizedDescription
                return
            }
            trajet = nouveau
            do {
                let maj = try await AgendaService.mettreAJourTrajet(identifiant: identifiant, manifestation: manifestation, course: course,
                                                                   echauffementMinutes: echauffement, trajet: nouveau)
                if !maj.identifiant.isEmpty { agenda.enregistrer(manifestation: manifestation.id, course: course.id, identifiant: maj.identifiant) }
                let lieu = maj.calendriers.joined(separator: ", ")
                infoAgenda = "Trajet mis à jour : \(nouveau.texte). \(maj.nombre) événement\(maj.nombre > 1 ? "s" : "") modifié\(maj.nombre > 1 ? "s" : "") (calendrier « \(lieu) »)."
            } catch AgendaError.evenementIntrouvable {
                agenda.retirer(manifestation: manifestation.id, course: course.id)
                erreurAgenda = AgendaError.evenementIntrouvable.localizedDescription
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
                            trajetLigne
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
                .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Theme.line, lineWidth: 1))
            }
            if let trace {
                if trace.aProfil { profilAltimetrique(trace) }
                if let fichierGPX {
                    ShareLink(item: fichierGPX) {
                        ActionRowLabel(titre: "Tracé GPX", sousTitre: "Télécharger ou envoyer vers une app GPS", icone: "arrow.down.circle")
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

private enum MeteoDiagnostic: LocalizedError {
    case dateIllisible(String), pasDeCoordonnees
    var errorDescription: String? {
        switch self {
        case .dateIllisible(let d): "Date de début illisible : « \(d) »."
        case .pasDeCoordonnees: "Pas de coordonnées exploitables pour ce lieu."
        }
    }
}

private enum ThemeAccent {
    case accent
    case warning

    var color: Color {
        switch self {
        case .accent: Theme.accent
        case .warning: Theme.warning
        }
    }
}
