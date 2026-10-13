import Foundation

struct Page<T: Decodable>: Decodable {
    let data: [T]
}

struct Manifestation: Decodable, Identifiable {
    let id: Int
    let libelle: String
    let dateDebut: String
    let dateFin: String
    let dateDebutHoraire: String?
    let adresse: Adresse?
    let configNiveaux: [ConfigNiveau]
    let structure: Structure?
    let modele: Modele?
    let documents: [Document]?
    let inscriptible: Bool?
    let datesInscriptionStart: String?
    let datesInscriptionEnd: String?
    let horaireInscriptionStart: String?
    let horaireInscriptionEnd: String?

    struct Structure: Decodable {
        let nom: String
        let code: String?
    }

    struct Document: Decodable {
        let fileURL: String?
        let type: DocType?

        struct DocType: Decodable {
            let code: String?
            let libelle: String?
        }

        enum CodingKeys: String, CodingKey {
            case type
            case fileURL = "file_url"
        }
    }

    /// Fichier GPX publié par l'organisateur, s'il y en a un (le site n'expose aujourd'hui que affiche, règlement, programme).
    var gpxURL: URL? {
        documents?.lazy.compactMap { d -> URL? in
            guard let f = d.fileURL, let url = URL(string: f) else { return nil }
            let code = d.type?.code?.uppercased() ?? ""
            return url.pathExtension.lowercased() == "gpx" || code.contains("GPX") || code.contains("TRACE") ? url : nil
        }.first
    }

    var debutDate: Date? { Date.fr("dd/MM/yyyy").date(from: dateDebut) }

    /// Type de la manifestation (« Cyclocross Classique »).
    struct Modele: Decodable {
        let libelle: String
    }

    struct Adresse: Decodable {
        let commune: String?
        let codePostalFr: String?
        let numVoie: String?
        let typeVoie: String?
        let nomVoie: String?
        let latitude: String?
        let longitude: String?

        enum CodingKeys: String, CodingKey {
            case commune, latitude, longitude
            case codePostalFr = "code_postal_fr"
            case numVoie = "num_voie"
            case typeVoie = "type_voie"
            case nomVoie = "nom_voie"
        }

        var coordinate: (latitude: Double, longitude: Double)? {
            guard let lat = latitude.flatMap(Double.init), let lon = longitude.flatMap(Double.init),
                  lat != 0 || lon != 0 else { return nil }
            return (lat, lon)
        }

        var rue: String {
            [numVoie, typeVoie, nomVoie].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, libelle, adresse
        case dateDebut = "date_debut"
        case dateFin = "date_fin"
        case dateDebutHoraire = "date_debut_horaire"
        case configNiveaux = "config_niveaux"
        case structure, modele, documents, inscriptible
        case datesInscriptionStart = "dates_inscription_start"
        case datesInscriptionEnd = "dates_inscription_end"
        case horaireInscriptionStart = "horaire_inscription_start"
        case horaireInscriptionEnd = "horaire_inscription_end"
    }
}

struct ConfigNiveau: Decodable, Identifiable {
    let id: Int
    let avec: Bool
    let position: Int
    let infos: Infos
    let niveau: Niveau

    struct Niveau: Decodable {
        let id: Int
        let libelle: String
        let groupeId: Int?
        let position: Int?

        enum CodingKeys: String, CodingKey {
            case id, libelle, position
            case groupeId = "groupe_id"
        }
    }

    /// `infos` vaut `[]` quand rien n'est renseigné, et un objet sinon.
    struct Infos: Decodable {
        var heure: String?
        var heureDepart: String?
        var nbTours: String?
        var distanceTour: String?
        var duree: String?
        var km: String?

        enum CodingKeys: String, CodingKey {
            case heure, duree, km
            case heureDepart = "heure_depart"
            case nbTours = "nb_tours"
            case distanceTour = "distance_tour"
        }

        init() {}

        init(from decoder: Decoder) throws {
            guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
            func texte(_ key: CodingKeys) -> String? {
                if let s = try? c.decode(String.self, forKey: key) { return s }
                if let d = try? c.decode(Double.self, forKey: key) { return String(d) }
                return nil
            }
            duree = texte(.duree)
            km = texte(.km)
            heure = try? c.decode(String.self, forKey: .heure)
            heureDepart = try? c.decode(String.self, forKey: .heureDepart)
            nbTours = try? c.decode(String.self, forKey: .nbTours)
            distanceTour = try? c.decode(String.self, forKey: .distanceTour)
        }

        var isEmpty: Bool { heure == nil && heureDepart == nil && nbTours == nil && distanceTour == nil && duree == nil && km == nil }

        /// Durée de la course en minutes : `duree` (minutes ; < 1 lu comme des heures), sinon estimée
        /// à 30 km/h d'après la distance, sinon 60 min.
        var dureeMinutes: Int {
            if let d = duree.flatMap({ Double($0.replacingOccurrences(of: ",", with: ".")) }), d > 0 {
                return Int((d < 1 ? d * 60 : d).rounded())
            }
            let distance = (Double(nbTours ?? "") ?? 0) * (Double(distanceTour ?? "") ?? 0)
            let total = distance > 0 ? distance : (Double(km ?? "") ?? 0)
            return total > 0 ? Int((total / 30 * 60).rounded()) : 60
        }
    }
}

struct GroupeNiveaux: Decodable, Identifiable {
    let id: Int
    let libelle: String
}

/// Type de manifestation (modèle) proposé dans le filtre du calendrier fédéral.
struct TypeManifestation: Decodable, Identifiable, Hashable {
    let id: Int
    let libelle: String
    let active: Bool?
}

/// Comité départemental (structure de type DEP).
struct Departement: Identifiable, Hashable {
    let id: Int
    let code: String   // « 059 »
    let nom: String    // « UFOLEP 59 »

    /// « 59 » (sans zéro initial) pour l'affichage compact.
    var numero: String { String(code.drop { $0 == "0" }) }
}

/// Nœud de `/structures/lazy-tree` ; le titre est un fragment HTML « <span>…badge code</span> nom ».
struct TreeNode: Decodable {
    let key: Int
    let title: String
    let children: [TreeNode]?

    var departement: Departement? {
        let text = title.replacing(#/<[^>]+>/#, with: "|")
            .split(separator: "|").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard text.count >= 2, text[0].allSatisfy(\.isNumber) else { return nil }
        return Departement(id: key, code: text[0], nom: text[1])
    }
}

/// Inscription du licencié, lue dans le HTML de `/manifestations/liste-inscriptions`.
struct Inscription: Identifiable, Hashable {
    struct Epreuve: Hashable {
        let type: String      // « Cyclocross Classique Adultes »
        let statut: String    // « Active »
        let niveaux: [String] // « Adultes - 3e catégorie »
    }

    let manifestationID: Int
    let libelle: String
    let annee: String
    let organisateur: String
    let type: String
    let dateTexte: String
    let dateDebut: Date?
    let dateFin: Date?
    let epreuves: [Epreuve]

    var id: Int { manifestationID }
    var estTerminee: Bool { dateFin.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false }
}

/// Fiche profil lue dans le HTML de `/infos`.
struct Profil {
    var nom = ""
    var numeroLicence = ""
    var photoURL: URL?
    var champs: [(label: String, valeur: String)] = []
}

/// Carte licencié (`/cartes-pass/cartes`) : une discipline, une saison, éventuellement une catégorie.
struct Carte: Identifiable, Hashable {
    let id = UUID()
    let saison: String        // « 2027 »
    let discipline: String    // « Cyclocross »
    let priseLe: String
    let expireLe: String
    let categorieAge: String? // « Adulte masculin 30/39 »
    let niveau: String?       // « 3ème catégorie »
    let club: String
    let comite: String
    let statut: String        // « Active », « Expiré »

    var estActive: Bool { statut.lowercased() == "active" }
}


/// Sport = discipline du site (« Cyclo VTT », « Cyclo - Cyclosport »…).
struct Discipline: Decodable, Identifiable, Hashable {
    let code: String
    let libelle: String
    let active: Bool?
    var id: String { code }
}

/// Réponse de `manifestations/manifestation/{id}/detail-personne/{personne}` : ce que le site autorise pour cette personne.
struct InscriptionDetailPersonne: Decodable {
    struct NiveauStatut: Decodable {
        struct Niveau: Decodable {
            let id: Int
            let libelle: String
        }

        let niveau: Niveau
        let erreurs: [String]
        let disabled: Bool
        let surListeAttente: Bool?

        enum CodingKeys: String, CodingKey {
            case niveau, erreurs, disabled
            case surListeAttente = "sur_liste_attente"
        }

        var inscriptible: Bool { !disabled && erreurs.isEmpty }
    }

    struct Vide: Decodable {}

    let niveaux: [NiveauStatut]
    let documentsDemandes: [Vide]?
}

/// Ticket calculé par le site avant l'enregistrement (on garde la réponse brute pour l'affichage).
struct TicketInscription {
    struct Ligne {
        let libelle: String
        let montant: Double
    }

    let id: String          // « 216-39438 » (manifestation-personne)
    let total: Double
    let lignes: [Ligne]
    let brut: Data
}

/// Commande en attente de paiement (`/commandes`).
struct Commande: Identifiable, Hashable {
    let id: Int          // valeur de la case à cocher (14005)
    let numero: String   // « 0000013387 »
    let libelle: String  // « Inscription sur la manifestation : Cyclo-cross VTT de Feignies »
    let montant: Double
}
