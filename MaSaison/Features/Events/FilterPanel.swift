import SwiftUI

/// Filters panel: edit or remove a filter, or restore the profile defaults.
struct FilterPanel: View {
    @Environment(FilterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Binding var departments: Set<Int>
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

                VStack(spacing: 10) {
                    row(title: "Sport", value: store.sportsSummary(sports), isActive: !sports.isEmpty,
                          editor: MultiSelectView.sports(store.sports, selection: $sports),
                          onDelete: { sports = [] })
                    row(title: "Départements", value: store.departmentsSummary(departments), isActive: !departments.isEmpty,
                          editor: MultiSelectView.departments(store.departments, selection: $departments),
                          onDelete: { departments = [] })
                }

                ActionRow(title: "Afficher les résultats", icon: "list.bullet", tone: .primary) { dismiss() }

                ActionRow(title: "Rétablir les filtres", subtitle: "Ceux définis dans le profil", icon: "arrow.counterclockwise") {
                    departments = store.defaultDepartments
                    sports = store.defaultSports
                }
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

    private func row<Destination: View>(title: String, value: String, isActive: Bool, editor: Destination, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(title)
                Text(value).font(.cond(26)).foregroundStyle(isActive ? Theme.accent : Theme.muted).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            NavigationLink { editor } label: {
                Image(systemName: "pencil").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .accessibilityLabel("Modifier : \(title)")
            IconButton(systemImage: "trash", label: "Supprimer le filtre \(title)", danger: true, action: onDelete)
                .opacity(isActive ? 1 : 0.35).disabled(!isActive)
        }
        .padding(.vertical, 14).padding(.leading, 18).padding(.trailing, 14)
        .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(isActive ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
    }
}
