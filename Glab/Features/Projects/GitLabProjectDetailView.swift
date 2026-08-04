import SwiftUI

struct GitLabProjectDetailView: View {
    let route: GitLabProjectRoute
    let apiAccess: GitLabAPIAccess
    let onProjectStarChanged:
        (GitLabProjectStarChange) -> Void
    let issueLoader:
        any GitLabIssueLoading
    let mergeRequestLoader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    let mergeRequestApprovalService:
        any GitLabMergeRequestApprovalServing
    let mergeRequestMergeService:
        any GitLabMergeRequestMergeServing
    let pipelineLoader:
        any GitLabPipelineLoading
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
    let commitLoader:
        any GitLabCommitLoading
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @State private var model:
        GitLabProjectDetailModel
    @State private var starModel:
        GitLabProjectStarModel
    @State private var createdIssueRoute:
        GitLabIssueRoute?

    init(
        route: GitLabProjectRoute,
        loader: any GitLabProjectResolving,
        starringService:
            any GitLabProjectStarringServing,
        apiAccess: GitLabAPIAccess,
        issueLoader:
            any GitLabIssueLoading,
        mergeRequestLoader:
            any GitLabMergeRequestLoading
                & GitLabMergeRequestApprovalLoading
                & GitLabMergeRequestDiffLoading
                & GitLabMergeRequestDiffSummaryLoading,
        mergeRequestApprovalService:
            any GitLabMergeRequestApprovalServing,
        mergeRequestMergeService:
            any GitLabMergeRequestMergeServing,
        pipelineLoader:
            any GitLabPipelineLoading,
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
        commitLoader:
            any GitLabCommitLoading,
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void,
        onProjectStarChanged:
            @escaping (
                GitLabProjectStarChange
            ) -> Void
    ) {
        self.route = route
        self.apiAccess = apiAccess
        self.issueLoader = issueLoader
        self.mergeRequestLoader =
            mergeRequestLoader
        self.mergeRequestApprovalService =
            mergeRequestApprovalService
        self.mergeRequestMergeService =
            mergeRequestMergeService
        self.pipelineLoader =
            pipelineLoader
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
        self.commitLoader =
            commitLoader
        self.accountID = accountID
        self.appSession = appSession
        self.onResourceEdited =
            onResourceEdited
        self.onProjectStarChanged =
            onProjectStarChanged
        _model = State(
            initialValue:
                GitLabProjectDetailModel(
                    route: route,
                    loader: loader
                )
        )
        _starModel = State(
            initialValue:
                GitLabProjectStarModel(
                    accountID: accountID,
                    apiAccess: apiAccess,
                    service:
                        starringService,
                    isAccountCurrent: {
                        appSession
                            .activeAccountID
                            == accountID
                    }
                )
        )
    }

    var body: some View {
        content
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .background(
                Color.glabCanvas
            )
            .task {
                await load()
            }
            .task(id: loadedProject?.id) {
                guard let loadedProject else {
                    return
                }
                await starModel.loadIfNeeded(
                    project: loadedProject
                )
                await handleAuthenticationFailure()
            }
            .alert(
                "Couldn’t update star",
                isPresented:
                    starFailureIsPresented
            ) {
                Button("OK") {
                    starModel.dismissFailure()
                }
            } message: {
                Text(
                    starModel.failure?
                        .localizedDescription
                        ?? ""
                )
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
            .gitLabProjectIssueCreation(
                project: loadedProject,
                apiAccess: apiAccess,
                isAvailable:
                    projectIssueCreationIsAvailable,
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
                    title: "Overview"
                ) {
                    projectOverview(project)
                }

                GitLabDetailSection(
                    title: "Browse"
                ) {
                    VStack(
                        alignment: .leading,
                        spacing: 10
                    ) {
                        projectIssuesRow(
                            project
                        )

                        projectMergeRequestsRow(
                            project
                        )

                        projectCommitsRow(
                            project
                        )
                    }
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
            if let loadedProject {
                await starModel.refresh(
                    project: loadedProject
                )
                await handleAuthenticationFailure()
            }
        }
    }

    private var loadedProject:
        GitLabProject?
    {
        guard
            case let .loaded(project) =
                model.state
        else {
            return nil
        }
        return project
    }

    private var projectIssueCreationIsAvailable:
        Bool
    {
        guard let loadedProject else {
            return false
        }
        return loadedProject
            .issuesAccessLevel?
            .isDisabled != true
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
                            .glabHeadline.weight(
                                .bold
                            )
                        )
                        .foregroundStyle(Color.glabBrandWarm)
                }
            }
            .frame(width: 58, height: 58)
            .background(
                Color.glabBrandWarm.opacity(0.12)
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
                    .font(.glabTitle2.bold())
                Text(
                    project.pathWithNamespace
                )
                .font(.glabSubheadline)
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

    private func projectOverview(
        _ project: GitLabProject
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    projectFact(
                        title: "Visibility",
                        value:
                            project.visibility.title,
                        systemImage:
                            project.visibility
                                .systemImage
                    )

                    Divider()
                        .frame(height: 42)

                    projectStars(project)
                }

                VStack(
                    alignment: .leading,
                    spacing: 14
                ) {
                    projectFact(
                        title: "Visibility",
                        value:
                            project.visibility.title,
                        systemImage:
                            project.visibility
                                .systemImage
                    )

                    projectStars(project)
                }
            }

            Divider()

            projectFact(
                title: "Last activity",
                value:
                    project.lastActivityAt
                        .formatted(
                            date: .abbreviated,
                            time: .shortened
                        ),
                systemImage: "clock"
            )
        }
        .padding(16)
        .background(
            Color.secondary.opacity(0.07),
            in: .rect(cornerRadius: 16)
        )
        .accessibilityElement(
            children: .contain
        )
    }

    private func projectFact(
        title: String,
        value: String,
        systemImage: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: systemImage)
                .font(.glabCaption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(
                    .glabSubheadline.weight(.semibold)
                )
                .fixedSize(
                    horizontal: false,
                    vertical: true
                )
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .accessibilityElement(
            children: .combine
        )
    }

    @ViewBuilder
    private func projectStars(
        _ project: GitLabProject
    ) -> some View {
        if
            apiAccess.canWrite,
            let isStarred = starModel.isStarred
        {
            projectStarButton(
                project,
                isStarred: isStarred
            )
        } else {
            projectFact(
                title: "Stars",
                value:
                    project.starCount
                        .formatted(),
                systemImage: "star"
            )
        }
    }

    private func projectStarButton(
        _ project: GitLabProject,
        isStarred: Bool
    ) -> some View {
        let glass =
            isStarred
            ? Glass.regular.tint(
                Color.glabBrandWarm
            )
            : Glass.regular

        return Button {
            Task {
                await toggleStar(
                    for: project
                )
            }
        } label: {
            HStack(spacing: 7) {
                if starModel.isMutating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16)
                } else {
                    Image(
                        systemName:
                            isStarred
                            ? "star.fill"
                            : "star"
                    )
                    .frame(width: 16)
                }

                Text(
                    project.starCount
                        .formatted()
                )
                .monospacedDigit()
            }
            .font(
                .glabSubheadline.weight(
                    .semibold
                )
            )
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.glass(glass))
        .disabled(!starModel.canToggle)
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .accessibilityLabel(
            isStarred
            ? "Unstar project"
            : "Star project"
        )
        .accessibilityValue(
            project.starCount == 1
            ? "1 star"
            : "\(project.starCount) stars"
        )
        .accessibilityHint(
            isStarred
            ? "Removes this project from your starred projects."
            : "Adds this project to your starred projects."
        )
        .accessibilityIdentifier(
            "project.starButton"
        )
    }

    @ViewBuilder
    private func projectIssuesRow(
        _ project: GitLabProject
    ) -> some View {
        if
            project.issuesAccessLevel?
                .isDisabled == true
        {
            GitLabProjectDestinationLabel(
                title: "Issues",
                subtitle:
                    "Disabled for this project",
                gitLabIcon:
                    .workItemIssue,
                isAvailable: false
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
                GitLabProjectDestinationLabel(
                    title: "Issues",
                    subtitle:
                        "Plan and track project work",
                    gitLabIcon:
                        .workItemIssue
                )
            }
            .buttonStyle(
                GitLabProjectDestinationButtonStyle()
            )
            .accessibilityHint(
                "Shows issues in this project."
            )
            .accessibilityIdentifier(
                "project.issues"
            )
        }
    }

    @ViewBuilder
    private func projectMergeRequestsRow(
        _ project: GitLabProject
    ) -> some View {
        if
            project.mergeRequestsAccessLevel?
                .isDisabled == true
        {
            GitLabProjectDestinationLabel(
                title: "Merge Requests",
                subtitle:
                    "Disabled for this project",
                gitLabIcon:
                    .mergeRequest,
                isAvailable: false
            )
            .accessibilityIdentifier(
                "project.mergeRequests.disabled"
            )
        } else {
            NavigationLink {
                GitLabProjectMergeRequestsView(
                    project: project,
                    loader:
                        mergeRequestLoader,
                    approvalService:
                        mergeRequestApprovalService,
                    mergeService:
                        mergeRequestMergeService,
                    pipelineLoader:
                        pipelineLoader,
                    discussionLoader:
                        discussionLoader,
                    discussionMutator:
                        discussionMutator,
                    reactionService:
                        reactionService,
                    editService:
                        editService,
                    accountID: accountID,
                    appSession: appSession,
                    onResourceEdited:
                        onResourceEdited
                )
            } label: {
                GitLabProjectDestinationLabel(
                    title: "Merge Requests",
                    subtitle:
                        "Review proposed changes",
                    gitLabIcon:
                        .mergeRequest
                )
            }
            .buttonStyle(
                GitLabProjectDestinationButtonStyle()
            )
            .accessibilityHint(
                "Shows merge requests in this project."
            )
            .accessibilityIdentifier(
                "project.mergeRequests"
            )
        }
    }

    private func projectCommitsRow(
        _ project: GitLabProject
    ) -> some View {
        NavigationLink {
            GitLabProjectCommitsView(
                project: project,
                loader: commitLoader,
                accountID: accountID,
                appSession: appSession
            )
        } label: {
            GitLabProjectDestinationLabel(
                title: "Commits",
                subtitle:
                    "History on "
                    + defaultBranchTitle(project),
                gitLabIcon:
                    .commit
            )
        }
        .buttonStyle(
            GitLabProjectDestinationButtonStyle()
        )
        .accessibilityHint(
            "Shows commits on the default branch."
        )
        .accessibilityIdentifier(
            "project.commits"
        )
    }

    private func defaultBranchTitle(
        _ project: GitLabProject
    ) -> String {
        guard
            let branch =
                project.defaultBranch?
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
            !branch.isEmpty
        else {
            return "the default branch"
        }
        return branch
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

    private var starFailureIsPresented:
        Binding<Bool>
    {
        Binding {
            starModel.failure != nil
        } set: { isPresented in
            if !isPresented {
                starModel.dismissFailure()
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

    private func toggleStar(
        for project: GitLabProject
    ) async {
        let previousIsStarred =
            starModel.isStarred
        let change = await starModel.toggle(
            project: project
        )

        if let change {
            _ = model.reconcileAuthoritative(
                change.project
            )
            onProjectStarChanged(change)
        } else if
            starModel.failure?
                .requiresProjectRefresh == true
        {
            await model.retry()
            if
                model.refreshError == nil,
                let refreshedProject =
                    loadedProject,
                let previousIsStarred,
                let isStarred =
                    starModel.isStarred,
                isStarred != previousIsStarred
            {
                onProjectStarChanged(
                    GitLabProjectStarChange(
                        project:
                            refreshedProject,
                        isStarred:
                            isStarred
                    )
                )
            }
        }
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error =
                model.authenticationFailure
                ?? starModel
                    .authenticationFailure
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

private struct GitLabProjectDestinationLabel:
    View
{
    let title: String
    let subtitle: String
    let gitLabIcon: GitLabIcon
    var isAvailable = true

    var body: some View {
        HStack(spacing: 12) {
            GitLabIconView(gitLabIcon)
                .foregroundStyle(
                    isAvailable
                        ? Color.glabAccent
                        : Color.secondary
                )
                .frame(width: 40, height: 40)
                .background(
                    (
                        isAvailable
                            ? Color.glabAccent
                            : Color.secondary
                    )
                    .opacity(
                        isAvailable ? 0.14 : 0.08
                    ),
                    in: .rect(cornerRadius: 11)
                )
                .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 3
            ) {
                Text(title)
                    .font(
                        .glabBody.weight(.semibold)
                    )
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            if isAvailable {
                Image(systemName: "chevron.forward")
                    .font(
                        .glabCaption.weight(.bold)
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Color.secondary.opacity(0.1),
                        in: .circle
                    )
                    .accessibilityHidden(true)
            } else {
                Text("Unavailable")
                    .font(
                        .glabCaption.weight(.medium)
                    )
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(
            maxWidth: .infinity,
            minHeight: 64,
            alignment: .leading
        )
        .background(
            Color.secondary.opacity(
                isAvailable ? 0.075 : 0.04
            ),
            in: .rect(cornerRadius: 16)
        )
        .contentShape(.rect)
        .opacity(isAvailable ? 1 : 0.68)
        .accessibilityElement(
            children: .combine
        )
    }
}

private struct GitLabProjectDestinationButtonStyle:
    ButtonStyle
{
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    func makeBody(
        configuration: Configuration
    ) -> some View {
        configuration.label
            .opacity(
                configuration.isPressed
                    ? 0.72
                    : 1
            )
            .scaleEffect(
                configuration.isPressed
                    && !reduceMotion
                    ? 0.985
                    : 1
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.12),
                value:
                    configuration.isPressed
            )
    }
}
