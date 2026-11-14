import SwiftUI
import TipKit

/// One tip per screen (TipKit): light bulb, uppercase heading, message, 44 pt close button.
struct AppTip: Tip {
    let id: String
    let heading: String
    let detail: String

    var title: Text { Text(heading) }
    var message: Text? { Text(detail) }
    var image: Image? { Image(systemName: "lightbulb") }
}

enum AppTips {
    static let home = AppTip(id: "accueil", heading: "Commencez par le profil",
        detail: "Réglez vos cartes, vos départements, votre sport et votre échauffement avant de chercher une course.")
    static let events = AppTip(id: "manifestations", heading: "Filtres préréglés",
        detail: "Vos départements et votre sport sont déjà préréglés. Touchez ici pour les ajuster.")
    static let detail = AppTip(id: "detail", heading: "Ajouter à l'agenda",
        detail: "Ajoutez la course à votre agenda : l'échauffement est déjà compté dans le créneau.")
    static let profile = AppTip(id: "profil", heading: "Filtres par défaut",
        detail: "Ils s'appliquent à chaque ouverture de la liste des manifestations. Modifiez-les ou rétablissez-les ici.")
    static let departments = AppTip(id: "departements", heading: "Plusieurs départements",
        detail: "Cochez plusieurs départements pour élargir la recherche.")
    static let filters = AppTip(id: "filtres", heading: "Modifier ou retirer",
        detail: "Le crayon modifie un filtre, la corbeille le retire.")
}

struct UfolepTipStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32).background(Color(hex: 0x2B343D), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                configuration.title
                    .font(.cond(17)).tracking(0.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                configuration.message
                    .font(.barlow(14)).foregroundStyle(Theme.textSoft)
            }
            Spacer(minLength: 0)
            Button {
                configuration.tip.invalidate(reason: .tipClosed)
            } label: {
                Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Fermer l'astuce")
            .padding(.vertical, -12)
        }
        .padding(.leading, 14).padding(.trailing, 4).padding(.vertical, 14)
        .background(Color(hex: 0x232A32), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color(hex: 0x3A444E), lineWidth: 1))
    }
}

/// Inline tip (takes no space once dismissed).
struct InlineTipView: View {
    let tip: AppTip

    var body: some View {
        TipView(tip).tipViewStyle(UfolepTipStyle())
    }
}
