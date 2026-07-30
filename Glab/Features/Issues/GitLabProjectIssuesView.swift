import SwiftUI

struct GitLabProjectIssuesView: View {
    let project: GitLabProject
    let apiAccess: GitLabAPIAccess
    let loader: any GitLabIssueLoading
    let discussionLoader:
        any GitLabDiscussionLoading
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let editService:
        any GitLabResourceEditing
    let issueStatusService:
        any GitLabIssueStatusServing
    let issueCreationService:
        any GitLabIssueCreationServing
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @State private var model:
        ProjectIssuesModel
    @State private var createdIssueRoute:
        GitLabIssueRoute?
    @State private var creationRequestID = 0

    init(
        project: GitLabProject,
        apiAccess: GitLabAPIAccess,
        loader: any GitLabIssueLoading,
        discussionLoader:
            any GitLabDiscussionLoading,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        editService:
            any GitLabResourceEditing,
        issueStatusService:
            any GitLabIssueStatusServing,
        issueCreationService:
            any GitLabIssueCreationServing,
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.project = project
        self.apiAccess = apiAccess
        self.loader = loader
        self.discussionLoader =
            discussionLoader
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.editService = editService
        self.issueStatusService =
            issueStatusService
        self.issueCreationService =
            issueCreationService
        self.accountID = accountID
        self.appSession = appSession
        self.onResourceEdited =
            onResourceEdited
        _model = State(
            initialValue:
                ProjectIssuesModel(
                    projectID: project.id,
                    loader: loader
                )
        )
    }

    var body: some View {
        @Bindable var model = model

        VStack(spacing: 0) {
            statePicker(model: $model)
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)

            Divider()

            issueList
        }
            .gitLabProjectIssueCreation(
                project: project,
                apiAccess: apiAccess,
                service:
                    issueCreationService,
                accountID: accountID,
                appSession: appSession,
                accessibilityIdentifier:
                    "projectIssues.newIssueButton",
                requestID:
                    creationRequestID
            ) { issue in
                didCreate(issue)
            }
            .navigationDestination(
                isPresented:
                    createdIssueIsPresented
            ) {
                createdIssueDestination
            }
    }

    private var issueList: some View {
        GitLabIssueListView(
            model: model.activeModel,
            configuration:
                GitLabIssueListConfiguration(
                    title: "Issues",
                    loadingMessage:
                        "Loading \(model.selectedState.title.lowercased()) issues",
                    emptyTitle:
                        "No \(model.selectedState.title.lowercased()) issues",
                    emptyMessage:
                        emptyMessage,
                    accessibilityIdentifier:
                        "projectIssues.list",
                    referenceStyle: .short,
                    prefersInlineTitle: true
                ),
            loader: loader,
            discussionLoader:
                discussionLoader,
            discussionMutator:
                discussionMutator,
            reactionService:
                reactionService,
            editService: editService,
            issueStatusService:
                issueStatusService,
            accountID: accountID,
            appSession: appSession,
            emptyAction: emptyAction
        ) { result in
            reconcileEditedResource(
                result
            )
        }
    }

    private func statePicker(
        model: Bindable<ProjectIssuesModel>
    ) -> some View {
        GitLabLifecycleStatePicker(
            states:
                GitLabProjectIssueState
                    .allCases,
            selection: model.selectedState,
            title: \.title,
            systemImage: \.systemImage,
            tintColor: \.tintColor,
            accessibilityValue: \.rawValue,
            accessibilityIdentifier:
                "projectIssues.state"
        )
    }

    private var emptyMessage: String {
        switch model.selectedState {
        case .opened:
            "Open issues in \(project.name) will appear here."
        case .closed:
            "Closed issues in \(project.name) will appear here."
        }
    }

    @ViewBuilder
    private var createdIssueDestination:
        some View
    {
        if let createdIssueRoute {
            issueDetail(
                route: createdIssueRoute
            )
        }
    }

    private var emptyAction:
        (() -> Void)?
    {
        guard apiAccess.canWrite else {
            return nil
        }
        return {
            requestIssueCreation()
        }
    }

    private func didCreate(
        _ issue: GitLabIssue
    ) {
        model.reconcileCreatedIssue(issue)
        createdIssueRoute = issue.route
    }

    private func requestIssueCreation() {
        creationRequestID &+= 1
    }

    private func reconcileEditedResource(
        _ result: GitLabResourceEditResult
    ) {
        if
            case let .issue(issue) = result,
            issue.projectID == project.id
        {
            model.reconcileEditedIssue(issue)
        }
        onResourceEdited(result)
    }

    private var createdIssueIsPresented:
        Binding<Bool>
    {
        Binding {
            createdIssueRoute != nil
        } set: { isPresented in
            if !isPresented {
                createdIssueRoute = nil
            }
        }
    }

    private func issueDetail(
        route: GitLabIssueRoute
    ) -> some View {
        GitLabIssueDetailView(
            route: route,
            loader: loader,
            discussionLoader:
                discussionLoader,
            discussionMutator:
                discussionMutator,
            reactionService:
                reactionService,
            editService:
                editService,
            issueStatusService:
                issueStatusService,
            accountID: accountID,
            appSession: appSession,
            onResourceEdited:
                reconcileEditedResource
        )
    }
}

private extension GitLabProjectIssueState {
    var tintColor: Color {
        switch self {
        case .opened:
            .green
        case .closed:
            .purple
        }
    }
}
