import SwiftUI
import UIKit

@main
struct OrbitApp: App {
    @StateObject private var auth = AuthState()
    var body: some Scene {
        WindowGroup {
            Group {
                if auth.signedIn {
                    if auth.needsInterestSetup { InterestSetupView() }
                    else if auth.organizerMode { OrganizerTabView() }
                    else { RootTabView() }
                }
                else { AuthView() }
            }
            .environmentObject(auth)
            .preferredColorScheme(OrbitAppearance(rawValue: appearanceRaw)?.colorScheme)
        }
    }

    @AppStorage("orbit.appearance") private var appearanceRaw = OrbitAppearance.system.rawValue
}
