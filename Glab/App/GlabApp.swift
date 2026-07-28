import SwiftUI

@main
struct GlabApp: App {
    @State private var appSession = AppSession(
        credentialStore: KeychainGitLabCredentialStore(),
        responseCache: FileGitLabResponseCache()
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
