import SwiftUI

/// Panneau Filtres : modifier, supprimer un filtre, ou rétablir les valeurs du profil.
struct FiltresPanel: View {
    @Environment(FiltresStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var departements: Set<Int>
    @Binding var sports: Set<String>

    var body: some View {
        NavigationStack {
            ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Filtres").font(.cond(32)).textCase(.uppercase).foregroundStyle(Theme.text)
                    Spacer()
                    IconButton(systemImage: "xmark", label: "Fermer") { dismiss() }
                }

                AstuceView(tip: AppTips.filtres)

                VStack(spacing: 10) {
                    ligne(titre: "Sport", valeur: store.resumeSports(sports), actif: !sports.isEmpty,
                          modifier: MultiSelectView.sports(store.sports, selection: $sports),
                          supprimer: { sports = [] })
                    ligne(titre: "Départements", valeur: store.resumeDepartements(departements), actif: !departements.isEmpty,
                          modifier: MultiSelectView.departements(store.departements, selection: $departements),
                          supprimer: { departements = [] })
                }

                Button {
                    departements = store.departementsParDefaut
                    sports = store.sportsParDefaut
                } label: {
                    Label("Rétablir les filtres par défaut", systemImage: "arrow.counterclockwise")
                        .font(.cond(15)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.textSoft)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }

                Button("Afficher les résultats") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
            }
            .screenBackground()
            .toolbar(.hidden, for: .navigationBar)
        }
        .presentationDetents([.fraction(0.85), .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.surface)
    }

    private func ligne<Destination: View>(titre: String, valeur: String, actif: Bool, modifier: Destination, supprimer: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(titre)
                Text(valeur).font(.cond(26)).foregroundStyle(actif ? Theme.accent : Theme.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            NavigationLink { modifier } label: {
                Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("Modifier : \(titre)")
            IconButton(systemImage: "trash", label: "Supprimer le filtre \(titre)", danger: true, action: supprimer)
                .opacity(actif ? 1 : 0.35).disabled(!actif)
        }
        .padding(.vertical, 14).padding(.leading, 18).padding(.trailing, 14)
        .background(Color(hex: 0x0F1318), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(actif ? Theme.accent : Theme.line, lineWidth: 1))
    }
}
