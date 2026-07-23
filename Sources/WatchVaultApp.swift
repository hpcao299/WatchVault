import SwiftUI

@main
struct WatchVaultApp: App {
    @StateObject private var authManager = AuthManager()
    @StateObject private var mediaManager = MediaManager()
    @Environment(\.scenePhase) var scenePhase
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authManager.isAuthenticated {
                    VaultView()
                        .environmentObject(authManager)
                        .environmentObject(mediaManager)
                } else {
                    LockScreenView()
                        .environmentObject(authManager)
                }
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .background || newPhase == .inactive {
                    authManager.lock()
                }
            }
        }
    }
}
