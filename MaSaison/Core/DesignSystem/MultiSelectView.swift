import SwiftUI

/// Generic multiple selection (departments, sports): search + checkmarks.
struct MultiSelectView<ID: Hashable>: View {
    struct Item: Identifiable {
        let id: ID
        let label: String
        let searchText: String
    }

    let title: String
    let items: [Item]
    @Binding var selection: Set<ID>
    var tip: AppTip?
    @State private var searchText = ""

    private var filteredItems: [Item] {
        searchText.isEmpty ? items : items.filter { $0.searchText.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                if let tip { InlineTipView(tip: tip).padding(.bottom, 4) }
                HStack {
                    Eyebrow("\(selection.count) sélectionné(s)")
                    Spacer()
                    if !selection.isEmpty {
                        Button("Tout effacer") { selection.removeAll() }
                            .font(.cond(14, .semibold)).tracking(1.5).textCase(.uppercase).foregroundStyle(Theme.accent)
                    }
                }
                .padding(.bottom, 2)
                ForEach(filteredItems) { item in
                    let isChecked = selection.contains(item.id)
                    Button {
                        if isChecked { selection.remove(item.id) } else { selection.insert(item.id) }
                    } label: {
                        HStack {
                            Text(item.label).font(.barlow(16, .semibold)).foregroundStyle(isChecked ? Theme.accent : Theme.text)
                                .multilineTextAlignment(.leading)
                            Spacer()
                            Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isChecked ? Theme.accent : Theme.faint).font(.system(size: 20))
                        }
                        .card(border: isChecked ? Theme.accent : Theme.line, radius: 16, padding: 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 120)
        }
        .searchable(text: $searchText, prompt: "Numéro ou nom")
        .screenBackground()
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}

extension MultiSelectView where ID == Int {
    static func departments(_ departments: [Department], selection: Binding<Set<Int>>, tip: AppTip? = AppTips.departments) -> MultiSelectView<Int> {
        MultiSelectView(title: "Départements",
                        items: departments.map { .init(id: $0.id, label: "\($0.number) – \($0.name)", searchText: "\($0.number) \($0.name)") },
                        selection: selection, tip: tip)
    }
}

extension MultiSelectView where ID == String {
    static func sports(_ sports: [Discipline], selection: Binding<Set<String>>) -> MultiSelectView<String> {
        MultiSelectView(title: "Sports",
                        items: sports.map { .init(id: $0.code, label: $0.name, searchText: $0.name) },
                        selection: selection)
    }
}
