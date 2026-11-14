import SwiftUI

struct LoginView: View {
    @Environment(AuthModel.self) private var auth
    @State private var username = ""
    @State private var password = ""
    @FocusState private var focus: Field?
    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow("UFOLEP", color: Theme.accent)
                    Text("Connexion").pageTitle()
                    Text("Retrouvez vos cartes, vos inscriptions et les manifestations près de chez vous.")
                        .font(.barlow(15)).foregroundStyle(Theme.muted)
                }

                VStack(alignment: .leading, spacing: 14) {
                    field("Identifiant ou e-mail") {
                        TextField("", text: $username)
                            .textContentType(.username)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            #endif
                            .focused($focus, equals: .username)
                            .submitLabel(.next)
                            .onSubmit { focus = .password }
                    }
                    field("Mot de passe") {
                        SecureField("", text: $password)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                    }
                }

                if let error = auth.errorMessage {
                    Text(error).font(.barlow(14)).foregroundStyle(Theme.danger)
                }

                ActionRow(title: "Se connecter", subtitle: auth.isLoading ? "Connexion en cours…" : "Avec ton compte UFOLEP",
                          icon: auth.isLoading ? "hourglass" : "person.crop.circle.badge.checkmark", tone: .primary, action: submit)
                .disabled(username.isEmpty || password.isEmpty || auth.isLoading)
                .opacity(username.isEmpty || password.isEmpty ? 0.5 : 1)

                VStack(alignment: .center, spacing: 14) {
                    Text("Pas de compte ? Créez-le sur le site de l'UFOLEP, puis connectez-vous ici.")
                        .font(.barlow(14)).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)

                UnofficialNotice()
            }
            .padding(.horizontal, 20).padding(.top, 48).padding(.bottom, 120)
        }
        .scrollDismissesKeyboard(.interactively)
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(label)
            content()
                .font(.barlow(17)).foregroundStyle(Theme.text)
                .padding(.horizontal, 14).frame(height: 52)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line, lineWidth: 1))
        }
    }

    private func submit() {
        Task { await auth.login(username: username, password: password) }
    }
}
