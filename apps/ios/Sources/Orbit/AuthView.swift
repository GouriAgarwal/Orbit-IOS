import SwiftUI

@MainActor
final class AuthState: ObservableObject {
    @Published var signedIn = false
    @Published var organizerMode = false
    @Published var displayName = ""
    @Published var isBusy = false
    @Published var error: String?
    private let client = AuthClient()

    func restoreSession() async {
        guard let stored = TokenVault.load() else { return }
        do {
            let tokens = try await client.refresh(refreshToken: stored)
            try TokenVault.save(tokens.refreshToken)
            let user = try await client.currentUser(accessToken: tokens.accessToken)
            displayName = user.profile?.displayName ?? "Student"
            signedIn = true
        } catch { TokenVault.delete() }
    }

    func submit(email: String, password: String, name: String, isRegistering: Bool) async {
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            let tokens = isRegistering
                ? try await client.register(email: email, password: password, displayName: name)
                : try await client.login(email: email, password: password)
            try TokenVault.save(tokens.refreshToken)
            let profile = try await client.currentUser(accessToken: tokens.accessToken)
            displayName = profile.profile?.displayName ?? name
            signedIn = true
        } catch { self.error = error.localizedDescription }
    }
    func signOut() {
        let token = TokenVault.load()
        TokenVault.delete(); signedIn = false; organizerMode = false; displayName = ""
        if let token { Task { try? await client.logout(refreshToken: token) } }
    }
}

struct AuthView: View {
    @EnvironmentObject private var auth: AuthState
    @State private var registering = true
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Text("O").font(.system(size: 30, weight: .black, design: .rounded)).foregroundStyle(OrbitStyle.onInk).frame(width: 60, height: 60).background(OrbitStyle.ink, in: Circle())
            Text(registering ? "Find your people." : "Welcome back.").font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(OrbitStyle.ink)
            Text(registering ? "Create your Orbit student account." : "Sign in to continue to Orbit.").foregroundStyle(.secondary)
            if registering { TextField("Your name", text: $name).textContentType(.name).textInputAutocapitalization(.words).authField() }
            TextField("Email", text: $email).textContentType(.emailAddress).keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled().authField()
            SecureField("Password", text: $password).textContentType(registering ? .newPassword : .password).authField()
            if let error = auth.error { Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Button {
                Task { await auth.submit(email: email, password: password, name: name, isRegistering: registering) }
            } label: {
                HStack { Spacer(); if auth.isBusy { ProgressView().tint(OrbitStyle.onInk) } else { Text(registering ? "Create account" : "Sign in").fontWeight(.bold) }; Spacer() }
                    .padding(16).background(OrbitStyle.ink, in: Capsule()).foregroundStyle(OrbitStyle.onInk)
            }.disabled(auth.isBusy || email.isEmpty || password.isEmpty || (registering && name.isEmpty))
            Button(registering ? "Already have an account? Sign in" : "New to Orbit? Create an account") { registering.toggle(); auth.error = nil }
                .font(.subheadline.weight(.semibold)).foregroundStyle(OrbitStyle.ink).frame(maxWidth: .infinity)
            Spacer()
            Text("By continuing, you agree to follow your campus community guidelines.").font(.caption).foregroundStyle(.secondary)
        }.padding(26).background(OrbitStyle.paper.ignoresSafeArea()).task { await auth.restoreSession() }
    }
}

private extension View {
    func authField() -> some View { padding(15).background(OrbitStyle.card, in: RoundedRectangle(cornerRadius: 14)) }
}
