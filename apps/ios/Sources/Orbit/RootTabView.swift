import SwiftUI
import UIKit

enum OrbitAppearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .system: nil; case .light: .light; case .dark: .dark }
    }
}

struct OrbitAppearancePicker: View {
    @AppStorage("orbit.appearance") private var appearanceRaw = OrbitAppearance.system.rawValue

    var body: some View {
        Picker("Appearance", selection: $appearanceRaw) {
            ForEach(OrbitAppearance.allCases) { appearance in
                Text(appearance.title).tag(appearance.rawValue)
            }
        }.pickerStyle(.segmented)
    }
}

struct RootTabView: View {
    var body: some View {
        TabView {
            DiscoverView().tabItem { Label("Discover", systemImage: "sparkle.magnifyingglass") }
            MyEventsView().tabItem { Label("My Events", systemImage: "calendar") }
            StudentClubsView().tabItem { Label("Clubs", systemImage: "person.3") }
            FindTeamView().tabItem { Label("Find Team", systemImage: "person.3") }
            InboxView().tabItem { Label("Inbox", systemImage: "bubble.left.and.bubble.right") }
            StudentProfileView().tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }.tint(OrbitStyle.ink)
    }
}

struct SignedInProfileView: View {
    @EnvironmentObject private var auth: AuthState
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "person.crop.circle.fill").font(.system(size: 64)).foregroundStyle(OrbitStyle.coral)
                Text(auth.displayName).font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(OrbitStyle.ink)
                Text("Student profile").foregroundStyle(.secondary)
                OrbitAppearancePicker().padding(.horizontal, 24)
                Button("Switch to Organizer mode") { auth.organizerMode = true }.buttonStyle(.borderedProminent).tint(OrbitStyle.ink)
                Button("Sign out", role: .destructive) { auth.signOut() }.padding(.top, 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(OrbitStyle.paper.ignoresSafeArea())
                .navigationTitle("Profile").navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct PlaceholderView: View {
    let title: String
    let symbol: String
    let detail: String
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: symbol).font(.system(size: 36, weight: .medium)).foregroundStyle(OrbitStyle.coral)
                Text(title).font(.system(.title, design: .rounded, weight: .bold))
                Text(detail).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 280)
                Text("Coming in the next Orbit slice").font(.caption.weight(.semibold)).foregroundStyle(OrbitStyle.ink.opacity(0.65)).padding(.horizontal, 14).padding(.vertical, 9).background(OrbitStyle.mint, in: Capsule())
            }.frame(maxWidth: .infinity, maxHeight: .infinity).background(OrbitStyle.paper.ignoresSafeArea())
                .navigationTitle("Orbit").navigationBarTitleDisplayMode(.inline)
        }
    }
}

enum OrbitStyle {
    static let ink = adaptive(light: (0.11, 0.19, 0.24), dark: (0.88, 0.91, 0.93))
    static let onInk = adaptive(light: (1, 1, 1), dark: (0.08, 0.10, 0.12))
    static let coral = adaptive(light: (0.91, 0.36, 0.27), dark: (1, 0.48, 0.38))
    static let mint = adaptive(light: (0.85, 0.94, 0.88), dark: (0.19, 0.30, 0.26))
    static let paper = adaptive(light: (0.97, 0.96, 0.92), dark: (0.07, 0.08, 0.09))
    static let card = adaptive(light: (1, 1, 1), dark: (0.13, 0.15, 0.17))
    static let yellow = adaptive(light: (0.98, 0.79, 0.39), dark: (0.62, 0.42, 0.13))

    private static func adaptive(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(uiColor: UIColor { traits in
            let values = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: values.0, green: values.1, blue: values.2, alpha: 1)
        })
    }
}
