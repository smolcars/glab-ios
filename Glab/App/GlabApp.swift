import Foundation
import SwiftUI

@main
struct GlabApp: App {
    @State private var appSession = AppSession(
        credentialStore: KeychainGitLabCredentialStore(),
        accountIndexStore:
            UserDefaultsGitLabAccountIndexStore(),
        responseCache: FileGitLabResponseCache(),
        discussionDraftStore:
            FileGitLabDiscussionDraftStore(),
        resourceEditDraftStore:
            FileGitLabResourceEditDraftStore(),
        issueCreationDraftStore:
            FileGitLabIssueCreationDraftStore()
    )
    @State private var incomingLinkModel =
        GitLabIncomingLinkModel()

    var body: some Scene {
        WindowGroup {
            rootContent
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

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
            if
                usesP308ApprovalFixture
            {
                GitLabMergeRequestApprovalFixtureView()
            } else if
                usesP309PipelineFixture
            {
                GitLabPipelineFixtureView()
            } else {
                AppRootView(
                    incomingLinkModel:
                        incomingLinkModel
                )
            }
        #else
            AppRootView(
                incomingLinkModel:
                    incomingLinkModel
            )
        #endif
    }

    #if DEBUG
        private var
            usesP308ApprovalFixture:
            Bool
        {
            let arguments =
                ProcessInfo.processInfo
                    .arguments
            return arguments.contains(
                "p3_08_approval_fixture"
            )
                || arguments.contains(
                    "-p3_08_approval_fixture"
                )
        }

        private var
            usesP309PipelineFixture:
            Bool
        {
            let arguments =
                ProcessInfo.processInfo
                    .arguments
            return arguments.contains(
                "p3_09_pipeline_fixture"
            )
                || arguments.contains(
                    "-p3_09_pipeline_fixture"
                )
        }
    #endif
}
