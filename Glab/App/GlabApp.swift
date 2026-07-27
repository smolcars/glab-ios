import SwiftUI

@main
struct GlabApp: App {
    @State private var appSession = AppSession(
        credentialStore: KeychainGitLabCredentialStore()
    )

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(appSession)
                .task {
                    await appSession.restore()
                }
        }
    }
}
