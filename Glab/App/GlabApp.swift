import Foundation
import SwiftUI
import UserNotifications

@main
struct GlabApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var appSession = AppSession(
        credentialStore: KeychainGitLabCredentialStore(),
        accountIndexStore:
            UserDefaultsGitLabAccountIndexStore(),
        responseCache: FileGitLabResponseCache(),
        jobTraceStore:
            FileGitLabJobTraceStore(),
        discussionDraftStore:
            FileGitLabDiscussionDraftStore(),
        resourceEditDraftStore:
            FileGitLabResourceEditDraftStore(),
        issueCreationDraftStore:
            FileGitLabIssueCreationDraftStore()
    )
    @State private var incomingLinkModel =
        GitLabIncomingLinkModel()
    @State private var todoNotificationManager =
        GitLabTodoNotificationManager()
    @State private var todoNotificationRouteModel:
        GitLabTodoNotificationRouteModel
    private let todoNotificationDelegate:
        GitLabTodoNotificationDelegate

    init() {
        let routeModel =
            GitLabTodoNotificationRouteModel()
        _todoNotificationRouteModel = State(
            initialValue: routeModel
        )
        let delegate =
            GitLabTodoNotificationDelegate(
                routeModel: routeModel
            )
        todoNotificationDelegate = delegate
        UNUserNotificationCenter.current()
            .delegate = delegate
    }

    var body: some Scene {
        WindowGroup {
            rootContent
                .environment(appSession)
                .environment(
                    todoNotificationManager
                )
                .environment(
                    todoNotificationRouteModel
                )
                .task {
                    await appSession.restore()
                    await todoNotificationManager
                        .refreshAuthorization()
                    await todoNotificationManager
                        .reconcileAccounts(
                            appSession.accounts
                                .map(\.id)
                        )
                }
                .onChange(of: scenePhase) {
                    _, phase in
                    guard phase == .background else {
                        return
                    }
                    todoNotificationManager
                        .scheduleRefresh()
                }
                .onChange(
                    of:
                        appSession.accounts
                            .map(\.id)
                ) { _, accountIDs in
                    Task {
                        await todoNotificationManager
                            .reconcileAccounts(
                                accountIDs
                            )
                    }
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
        .backgroundTask(
            .appRefresh(
                GitLabTodoNotificationManager
                    .backgroundTaskIdentifier
            )
        ) {
            await todoNotificationManager
                .performBackgroundRefresh(
                    appSession: appSession
                )
        }
    }

    @ViewBuilder
    private var rootContent: some View {
        #if DEBUG
            if
                usesTodoNotificationFixture
            {
                GitLabTodoNotificationFixtureView()
            } else if
                usesP308ApprovalFixture
            {
                GitLabMergeRequestApprovalFixtureView()
            } else if
                usesP309PipelineFixture
            {
                GitLabPipelineFixtureView()
            } else if
                usesP312MergeFixture
            {
                GitLabMergeRequestMergeFixtureView()
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
            usesTodoNotificationFixture:
            Bool
        {
            let arguments =
                ProcessInfo.processInfo
                    .arguments
            return arguments.contains(
                "todo_notification_fixture"
            )
                || arguments.contains(
                    "-todo_notification_fixture"
                )
        }

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

        private var
            usesP312MergeFixture:
            Bool
        {
            let arguments =
                ProcessInfo.processInfo
                    .arguments
            return arguments.contains(
                "p3_12_merge_fixture"
            )
                || arguments.contains(
                    "-p3_12_merge_fixture"
                )
        }
    #endif
}
