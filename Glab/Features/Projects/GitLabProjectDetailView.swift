import SwiftUI

struct GitLabProjectDetailView: View {
    let route: GitLabProjectRoute
    let apiAccess: GitLabAPIAccess
    let issueLoader:
        any GitLabIssueLoading
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
        GitLabProjectDetailModel
    @State private var createdIssueRoute:
        GitLabIssueRoute?

    init(
        route: GitLabProjectRoute,
        loader: any GitLabProjectResolving,
        apiAccess: GitLabAPIAccess,
        issueLoader:
            any GitLabIssueLoading,
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
        self.route = route
        self.apiAccess = apiAccess
        self.issueLoader = issueLoader
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
                GitLabProjectDetailModel(
                    route: route,
                    loader: loader
                )
        )
    }

    var body: some View {
        content
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                Color(
                    uiColor:
                        .systemGroupedBackground
                )
            )
            .task {
                await load()
            }
            .accessibilityIdentifier(
                "project.detail"
            )
            .navigationDestination(
                isPresented:
                    createdIssueIsPresented
            ) {
                if let createdIssueRoute {
                    issueDetail(
                        route:
                            createdIssueRoute
                    )
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading project"
                )
                .padding(20)
            }
        case let .failed(error):
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await retry()
                    }
                }
            }
        case let .loaded(project):
            projectContent(project)
        }
    }

    private func projectContent(
        _ project: GitLabProject
    ) -> some View {
        ScrollView {
            LazyVStack(
                alignment: .leading,
                spacing: 24
            ) {
                projectHeader(project)

                GitLabDetailSection(
                    title: "Project"
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 12
                    ) {
                        metadataRow(
                            title: "Visibility",
                            value:
                                project
                                    .visibility
                                    .title,
                            systemImage:
                                project
                                    .visibility
                                    .systemImage
                        )
                        metadataRow(
                            title: "Stars",
                            value:
                                project.starCount
                                    .formatted(),
                            systemImage: "star"
                        )
                        metadataRow(
                            title: "Last activity",
                            value:
                                project
                                    .lastActivityAt
                                    .formatted(
                                        date:
                                            .abbreviated,
                                        time:
                                            .shortened
                                    ),
                            systemImage: "clock"
                        )
                    }
                }

                GitLabDetailSection(
                    title: "Work"
                ) {
                    projectIssuesRow(
                        project
                    )
                }

                if
                    let destination =
                        project.safeWebURL
                {
                    GitLabOpenInGitLabLink(
                        destination:
                            destination,
                        accessibilityIdentifier:
                            "project.openInGitLab"
                    )
                    .padding(.horizontal, -20)
                }
            }
            .padding(20)
        }
        .refreshable {
            await retry()
        }
        .gitLabProjectIssueCreation(
            project: project,
            apiAccess: apiAccess,
            isAvailable:
                project.issuesAccessLevel?
                    .isDisabled != true,
            service:
                issueCreationService,
            accountID: accountID,
            appSession: appSession,
            accessibilityIdentifier:
                "project.newIssueButton"
        ) { issue in
            createdIssueRoute =
                issue.route
        }
    }

    private func projectHeader(
        _ project: GitLabProject
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            AsyncImage(
                url: project.safeAvatarURL
            ) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    Text(project.avatarMark)
                        .font(
                            .headline.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(.orange)
                }
            }
            .frame(width: 58, height: 58)
            .background(
                Color.orange.opacity(0.12)
            )
            .clipShape(
                .rect(cornerRadius: 14)
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: 14
                )
                .stroke(
                    Color.secondary
                        .opacity(0.18),
                    lineWidth: 0.5
                )
            }
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 5
            ) {
                Text(project.name)
                    .font(.title2.bold())
                Text(
                    project.pathWithNamespace
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
        .accessibilityElement(
            children: .combine
        )
        .accessibilityIdentifier(
            "project.header"
        )
    }

    private func metadataRow(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        LabeledContent {
            Text(value)
                .multilineTextAlignment(
                    .trailing
                )
        } label: {
            Label(
                title,
                systemImage: systemImage
            )
        }
    }

    @ViewBuilder
    private func projectIssuesRow(
        _ project: GitLabProject
    ) -> some View {
        if
            project.issuesAccessLevel?
                .isDisabled == true
        {
            HStack(spacing: 12) {
                Label(
                    "Issues",
                    systemImage:
                        "smallcircle.filled.circle"
                )
                Spacer(minLength: 8)
                Text("Disabled")
                    .font(.subheadline)
                    .foregroundStyle(
                        .secondary
                    )
            }
            .accessibilityElement(
                children: .combine
            )
            .accessibilityIdentifier(
                "project.issues.disabled"
            )
        } else {
            NavigationLink {
                GitLabProjectIssuesView(
                    project: project,
                    apiAccess: apiAccess,
                    loader: issueLoader,
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
                    issueCreationService:
                        issueCreationService,
                    accountID: accountID,
                    appSession: appSession,
                    onResourceEdited:
                        onResourceEdited
                )
            } label: {
                HStack(spacing: 12) {
                    Label(
                        "Issues",
                        systemImage:
                            "smallcircle.filled.circle"
                    )
                    Spacer(minLength: 8)
                    Text("Browse")
                        .font(.subheadline)
                        .foregroundStyle(
                            .secondary
                        )
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint(
                "Shows issues in this project."
            )
            .accessibilityIdentifier(
                "project.issues"
            )
        }
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
            loader: issueLoader,
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
                onResourceEdited
        )
    }

    private func load() async {
        await model.loadIfNeeded()
        await handleAuthenticationFailure()
    }

    private func retry() async {
        await model.retry()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
        else {
            return
        }
        await appSession
            .handleAuthenticationFailure(
                error,
                for: accountID
            )
    }
}
