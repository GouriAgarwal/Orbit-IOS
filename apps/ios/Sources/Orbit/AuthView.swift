import SwiftUI

@MainActor
final class AuthState: ObservableObject {
    @Published var signedIn = false
    @Published var organizerMode = false
    @Published var displayName = ""
    @Published var isBusy = false
    @Published var error: String?
    @Published var needsInterestSetup = false
    @Published var interests: [String] = []
    private let client = AuthClient()

    func restoreSession() async {
        guard let stored = TokenVault.load() else { return }
        do {
            let tokens = try await client.refresh(refreshToken: stored)
            try TokenVault.save(tokens.refreshToken)
            let user = try await client.currentUser(accessToken: tokens.accessToken)
            displayName = user.profile?.displayName ?? "Student"
            interests = user.profile?.interests ?? []
            needsInterestSetup = interests.isEmpty
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
            interests = profile.profile?.interests ?? []
            needsInterestSetup = isRegistering || interests.isEmpty
            signedIn = true
        } catch { self.error = error.localizedDescription }
    }
    func saveInterests(_ selected: [String]) async {
        isBusy = true; error = nil
        defer { isBusy = false }
        do {
            guard let refreshToken = TokenVault.load() else { throw AuthError.server("Sign in again to save your interests.") }
            let tokens = try await client.refresh(refreshToken: refreshToken)
            try TokenVault.save(tokens.refreshToken)
            try await client.saveInterests(selected, accessToken: tokens.accessToken)
            interests = selected
            needsInterestSetup = false
        } catch { self.error = error.localizedDescription }
    }
    func signOut() {
        let token = TokenVault.load()
        TokenVault.delete(); signedIn = false; organizerMode = false; displayName = ""; interests = []; needsInterestSetup = false
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

struct InterestSetupView: View {
    @EnvironmentObject private var auth: AuthState
    @State private var selected = Set<String>()

    private let choices: [(String, String)] = [
        ("Technology", "laptopcomputer"), ("Hackathons", "hammer.fill"), ("Design & UI/UX", "paintpalette.fill"),
        ("Entrepreneurship", "lightbulb.fill"), ("AI & Data Science", "sparkles"), ("Arts & Culture", "theatermasks.fill"),
        ("Music", "music.note"), ("Sports", "figure.run"), ("Gaming", "gamecontroller.fill"),
        ("Career & Networking", "person.2.fill"), ("Wellness", "heart.fill"), ("Volunteering", "hands.sparkles.fill"),
        ("Photography", "camera.fill"), ("Finance", "chart.line.uptrend.xyaxis"), ("Environment", "leaf.fill"),
        ("Writing & Literature", "book.closed.fill"), ("Workshops & Learning", "graduationcap.fill")
    ]

    private let columns = [GridItem(.adaptive(minimum: 142), spacing: 9)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles").font(.title3.weight(.bold)).foregroundStyle(OrbitStyle.ink)
                    .frame(width: 46, height: 46).background(OrbitStyle.mint, in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text("Make Orbit yours").font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                    Text("Pick at least 3 interests for your feed.").font(.subheadline).foregroundStyle(.secondary)
                }
            }

            ScrollView {
                LazyVGrid(columns: columns, spacing: 9) {
                    ForEach(choices, id: \.0) { choice in
                        let title = choice.0
                        let symbol = choice.1
                        let isSelected = selected.contains(title)
                        Button {
                            if isSelected { selected.remove(title) } else { selected.insert(title) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                                Text(title).font(.system(.caption, design: .rounded, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.85)
                                Spacer(minLength: 0)
                                if isSelected { Image(systemName: "checkmark.circle.fill").font(.system(size: 13)) }
                            }
                            .foregroundStyle(isSelected ? OrbitStyle.onInk : OrbitStyle.ink.opacity(0.82))
                            .padding(.horizontal, 11).padding(.vertical, 12)
                            .background(isSelected ? OrbitStyle.ink : OrbitStyle.card, in: Capsule())
                            .overlay(Capsule().stroke(OrbitStyle.ink.opacity(isSelected ? 0 : 0.08)))
                        }.buttonStyle(.plain)
                    }
                }
            }

            Text("You can change these any time in your profile.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .center)
            if let error = auth.error { Text(error).font(.footnote).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            Button {
                Task { await auth.saveInterests(selected.sorted()) }
            } label: {
                HStack { Spacer(); if auth.isBusy { ProgressView().tint(OrbitStyle.onInk) } else { Text("Personalize my feed").fontWeight(.bold); Image(systemName: "arrow.right").fontWeight(.bold) }; Spacer() }
                    .padding(16).background(OrbitStyle.ink, in: Capsule()).foregroundStyle(OrbitStyle.onInk)
            }.disabled(auth.isBusy || selected.count < 3)
            if selected.count < 3 {
                Text("Choose \(3 - selected.count) more to continue.").font(.caption.weight(.medium)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            }
        }
        .padding(22).background(OrbitStyle.paper.ignoresSafeArea())
        .task { selected = Set(auth.interests) }
    }
}
