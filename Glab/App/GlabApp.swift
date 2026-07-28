import SwiftUI

@main
struct GlabApp: App {
    @State private var appSession = AppSession(
        credentialStore: KeychainGitLabCredentialStore(),
        accountIndexStore:
            UserDefaultsGitLabAccountIndexStore(),
        responseCache: FileGitLabResponseCache(),
        discussionDraftStore:
            FileGitLabDiscussionDraftStore()
    )
    @State private var incomingLinkModel =
        GitLabIncomingLinkModel()

    var body: some Scene {
        WindowGroup {
            AppRootView(
                incomingLinkModel:
                    incomingLinkModel
            )
                .environment(appSession)
                .task {
                    await appSession.restore()
                }
                .onOpenURL { url in
                    incomingLinkModel.receive(
                        url,
                        accounts:
                            appSession.accounts
                                .map(\.id),
                        activeAccountID:
                            appSession.activeAccountID
                    )
                }
        }
    }
}
