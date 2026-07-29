import SwiftUI

private struct
    GitLabProjectIssueCreationModifier:
    ViewModifier
{
    let project: GitLabProject
    let apiAccess: GitLabAPIAccess
    let isAvailable: Bool
    let service:
        any GitLabIssueCreationServing
    let accountID: GitLabAccountID
    let appSession: AppSession
    let accessibilityIdentifier: String
    let requestID: Int
    let onCreated: (GitLabIssue) -> Void

    @State private var presentation =
        GitLabPreparedSheetPresentationState<
            GitLabIssueCreationPresentation
        >()

    func body(
        content: Content
    ) -> some View {
        content
            .toolbar {
                if
                    isAvailable
                        && apiAccess.canWrite
                {
                    ToolbarItem(
                        placement:
                            .topBarTrailing
                    ) {
                        Button {
                            launch()
                        } label: {
                            Image(
                                systemName:
                                    "square.and.pencil"
                            )
                        }
                        .accessibilityLabel(
                            "New issue in \(project.name)"
                        )
                        .accessibilityHint(
                            "Opens the issue composer with this project selected."
                        )
                        .accessibilityIdentifier(
                            accessibilityIdentifier
                        )
                    }
                }
            }
            .sheet(
                isPresented: isPresented,
                onDismiss: {
                    presentation
                        .didDismiss()
                }
            ) {
                if
                    let destination =
                        presentation
                        .destination
                {
                    GitLabIssueCreationView(
                        model:
                            destination.model,
                        accountID:
                            accountID,
                        appSession:
                            appSession
                    )
                    .presentationDragIndicator(
                        .visible
                    )
                }
            }
            .onChange(
                of: presentation.preparedID
            ) { _, preparedID in
                presentation
                    .presentPrepared(
                        id: preparedID
                    )
            }
            .onChange(of: requestID) {
                _, _ in
                launch()
            }
    }

    @MainActor
    private func launch() {
        guard isAvailable else {
            return
        }
        let model =
            GitLabIssueCreationModel(
                accountID: accountID,
                apiAccess: apiAccess,
                service: service,
                draftStore:
                    appSession
                    .issueCreationDraftStore,
                fixedProject: project,
                isAccountCurrent: {
                    appSession
                        .activeAccountID
                        == accountID
                }
            ) { issue in
                presentation.dismiss()
                onCreated(issue)
            }
        presentation.prepare(
            GitLabIssueCreationPresentation(
                model: model
            )
        )
    }

    private var isPresented:
        Binding<Bool>
    {
        Binding {
            presentation.isPresented
        } set: { isPresented in
            guard !isPresented else {
                return
            }
            presentation.dismiss()
        }
    }
}

extension View {
    func gitLabProjectIssueCreation(
        project: GitLabProject,
        apiAccess: GitLabAPIAccess,
        isAvailable: Bool = true,
        service:
            any GitLabIssueCreationServing,
        accountID: GitLabAccountID,
        appSession: AppSession,
        accessibilityIdentifier: String,
        requestID: Int = 0,
        onCreated:
            @escaping (GitLabIssue) -> Void
    ) -> some View {
        modifier(
            GitLabProjectIssueCreationModifier(
                project: project,
                apiAccess: apiAccess,
                isAvailable:
                    isAvailable,
                service: service,
                accountID: accountID,
                appSession: appSession,
                accessibilityIdentifier:
                    accessibilityIdentifier,
                requestID: requestID,
                onCreated: onCreated
            )
        )
    }
}
