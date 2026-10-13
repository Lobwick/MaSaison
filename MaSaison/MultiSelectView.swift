import SwiftUI

/// Sélection multiple générique (départements, sports) : recherche + coches.
struct MultiSelectView<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let label: String
        let recherche: String
    }

    let titre: String
    let items: [Item]
    @Binding var selection: Set<ID>
    var astuce: AppTip?
    @State private var recherche = ""

    private var filtres: [Item] {
        recherche.isEmpty ? items : items.filter { $0.recherche.localizedCaseInsensitiveContains(recherche) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let astuce { AstuceView(tip: astuce).padding(.bottom, 4) }
                HStack {
                    Eyebrow("\(selection.count) sélectionné(s)")
                    Spacer()
                    if !selection.isEmpty {
                        Button("Tout effacer") { selection.removeAll() }
                            .font(.cond(14, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.bottom, 2)
                ForEach(filtres) { item in
                    let coche = selection.contains(item.id)
                    Button {
                        if coche { selection.remove(item.id) } else { selection.insert(item.id) }
                    } label: {
                        HStack {
                            Text(item.label).font(.barlow(16, .semibold)).foregroundStyle(coche ? Theme.accent : Theme.text)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: coche ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(coche ? Theme.accent : Theme.faint).font(.system(size: 20))
                        }
                        .card(border: coche ? Theme.accent : Theme.line, radius: 16, padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 24)
        }
        .searchable(text: $recherche, prompt: "Numéro ou nom")
        .screenBackground()
        .navigationTitle(titre)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension MultiSelectView where ID == Int {
    static func departements(_ departements: [Departement], selection: Binding<Set<Int>>, astuce: AppTip? = AppTips.departements) -> MultiSelectView<Int> {
        MultiSelectView(titre: "Départements",
                        items: departements.map { .init(id: $0.id, label: "\($0.numero) – \($0.nom)", recherche: "\($0.numero) \($0.nom)") },
                        selection: selection, astuce: astuce)
    }
}

extension MultiSelectView where ID == String {
    static func sports(_ sports: [Discipline], selection: Binding<Set<String>>) -> MultiSelectView<String> {
        MultiSelectView(titre: "Sports",
                        items: sports.map { .init(id: $0.code, label: $0.libelle, recherche: $0.libelle) },
                        selection: selection)
    }
}
