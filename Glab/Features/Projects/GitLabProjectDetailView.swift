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
    let repositoryLoader:
        any GitLabRepositoryLoading
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
        repositoryLoader:
            any GitLabRepositoryLoading,
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
        self.repositoryLoader =
            repositoryLoader
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
                    projectPathWithNamespace:
                        route.pathWithNamespace,
                    initialIsStarred:
                        route.initialIsStarred,
                    service:
                        starringService,
                    stateStore:
                        appSession
                        .projectStarStateStore,
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
                        projectCodeRow(project)

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
                    let readmeRoute =
                        GitLabRepositoryFileRoute(
                            readmeIn: project
                        )
                {
                    GitLabProjectReadmeView(
                        route: readmeRoute,
                        loader: repositoryLoader,
                        accountID: accountID,
                        appSession: appSession
                    )
                    .id(readmeRoute)
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
        if apiAccess.canWrite {
            projectStarButton(project)
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
        _ project: GitLabProject
    ) -> some View {
        HStack(spacing: 7) {
            Button {
                Task {
                    if starModel.canRetry {
                        await retryStarStatus(
                            for: project
                        )
                    } else {
                        await toggleStar(
                            for: project
                        )
                    }
                }
            } label: {
                if starModel.isMutating {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 18, height: 18)
                } else {
                    switch starModel.state {
                    case .idle, .loading:
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 18, height: 18)
                    case .failed:
                        Image(
                            systemName: "arrow.clockwise"
                        )
                        .foregroundStyle(.primary)
                        .frame(width: 18, height: 18)
                    case let .ready(isStarred):
                        Image(
                            systemName:
                                isStarred
                                ? "star.fill"
                                : "star"
                        )
                        .foregroundStyle(
                            isStarred
                            ? Color.glabBrandWarm
                            : Color.primary
                        )
                        .frame(width: 18, height: 18)
                    }
                }
            }
            .font(
                .glabSubheadline.weight(
                    .semibold
                )
            )
            .frame(width: 44, height: 44)
            .buttonBorderShape(.circle)
            .buttonStyle(.glass(.clear))
            .disabled(
                !starModel.canToggle
                    && !starModel.canRetry
            )
            .accessibilityLabel(
                starAccessibilityLabel(
                    starModel.state
                )
            )
            .accessibilityValue(
                project.starCount == 1
                ? "1 star"
                : "\(project.starCount) stars"
            )
            .accessibilityHint(
                starAccessibilityHint(
                    starModel.state
                )
            )
            .accessibilityIdentifier(
                "project.starButton"
            )

            Text(
                project.starCount
                    .formatted()
            )
            .font(
                .glabSubheadline.weight(
                    .semibold
                )
            )
            .monospacedDigit()
            .accessibilityHidden(true)
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
    }

    private func starAccessibilityLabel(
        _ state: GitLabProjectStarState
    ) -> String {
        switch state {
        case .idle, .loading:
            "Loading star status"
        case .failed:
            "Retry star status"
        case .ready(isStarred: true):
            "Unstar project"
        case .ready(isStarred: false):
            "Star project"
        }
    }

    private func starAccessibilityHint(
        _ state: GitLabProjectStarState
    ) -> String {
        switch state {
        case .idle, .loading:
            "Checks whether this project is starred."
        case .failed:
            "Checks the current star status again."
        case .ready(isStarred: true):
            "Removes this project from your starred projects."
        case .ready(isStarred: false):
            "Adds this project to your starred projects."
        }
    }

    @ViewBuilder
    private func projectCodeRow(
        _ project: GitLabProject
    ) -> some View {
        NavigationLink {
            GitLabRepositoryView(
                project: project,
                loader: repositoryLoader,
                accountID: accountID,
                appSession: appSession
            )
        } label: {
            GitLabProjectDestinationLabel(
                title: "Code",
                subtitle:
                    "Browse files and branches",
                gitLabIcon: .project
            )
        }
        .buttonStyle(
            GitLabProjectDestinationButtonStyle()
        )
        .accessibilityHint(
            "Browses files in this project."
        )
        .accessibilityIdentifier(
            "project.code"
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

    private func retryStarStatus(
        for project: GitLabProject
    ) async {
        await starModel.refresh(
            project: project
        )
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

private struct GitLabProjectReadmeView: View {
    let route: GitLabRepositoryFileRoute
    let loader: any GitLabRepositorySourceLoading
    let accountID: GitLabAccountID
    let appSession: AppSession

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer
    @State private var model:
        GitLabRepositoryFileModel
    @State private var presentation:
        GitLabRepositoryFilePresentation =
            .markdownKit

    init(
        route: GitLabRepositoryFileRoute,
        loader: any GitLabRepositorySourceLoading,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.route = route
        self.loader = loader
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabRepositoryFileModel(
                    route: route,
                    loader: loader
                )
        )
    }

    var body: some View {
        VStack(
            alignment: .leading,
            spacing: 16
        ) {
            header

            Divider()

            content
        }
        .padding(16)
        .background(
            Color.secondary.opacity(0.06),
            in: .rect(cornerRadius: 16)
        )
        .task {
            await model.loadIfNeeded()
            await handleAuthenticationFailure()
        }
        .onChange(
            of: model.authenticationFailure
        ) { _, error in
            guard let error else {
                return
            }
            Task {
                await appSession
                    .handleAuthenticationFailure(
                        error,
                        for: accountID
                    )
            }
        }
        .accessibilityIdentifier(
            "project.readme"
        )
    }

    private var header: some View {
        HStack(spacing: 12) {
            Label(
                route.fileName,
                systemImage: "info.circle"
            )
            .font(.glabHeadline)
            .lineLimit(1)
            .truncationMode(.middle)

            Spacer(minLength: 8)

            Menu {
                Picker(
                    "Preview",
                    selection: $presentation
                ) {
                    ForEach(
                        [
                            GitLabRepositoryFilePresentation
                                .markdownKit,
                            .rendered,
                        ],
                        id: \.self
                    ) { option in
                        Label(
                            option.title,
                            systemImage:
                                option.systemImage
                        )
                        .tag(option)
                    }
                }

                Divider()

                NavigationLink {
                    fileView(
                        presentation: presentation
                    )
                } label: {
                    Label(
                        "Open Full Screen",
                        systemImage:
                            "arrow.up.left.and.arrow.down.right"
                    )
                }

                NavigationLink {
                    fileView(
                        presentation: .raw
                    )
                } label: {
                    Label(
                        "View Raw",
                        systemImage: "text.page"
                    )
                }

                if let destination = route.safeWebURL {
                    Link(destination: destination) {
                        Label(
                            "Open in GitLab",
                            systemImage:
                                "arrow.up.right.square"
                        )
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.glass(.clear))
            .buttonBorderShape(.circle)
            .accessibilityLabel("README actions")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading README…")
                    .foregroundStyle(.secondary)
            }
            .font(.glabCallout)
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        case let .loaded(document):
            if
                GitLabRepositoryFilePresentation
                    .supportsRenderedMarkdown(
                        document
                    )
            {
                readmePreview(document)
            } else {
                Text(
                    document.language == .markdown
                        ? "This README is too large to render. Open the raw file to read it."
                        : "This README format is available as a raw file."
                )
                .font(.glabCallout)
                .foregroundStyle(.secondary)
            }
        case let .failed(error):
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                Label(
                    "Couldn’t load README",
                    systemImage:
                        "exclamationmark.triangle"
                )
                .font(
                    .glabCallout.weight(
                        .semibold
                    )
                )

                Text(error.description)
                    .font(.glabCaption)
                    .foregroundStyle(.secondary)

                if error.canRetry {
                    Button("Try Again") {
                        Task {
                            await model.retry()
                            await handleAuthenticationFailure()
                        }
                    }
                    .font(
                        .glabCallout.weight(
                            .semibold
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func readmePreview(
        _ document: GitLabSourceDocument
    ) -> some View {
        switch presentation {
        case .markdownKit:
            GitLabMarkdownKitPrototypeView(
                source: document.source
            )
        case .rendered:
            GitLabRepositoryMarkdownContentView(
                route: route,
                document: document,
                accountID: accountID,
                renderer: markdownRenderer
            )
        case .raw:
            EmptyView()
        }
    }

    private func fileView(
        presentation:
            GitLabRepositoryFilePresentation
    ) -> some View {
        GitLabRepositoryFileView(
            route: route,
            loader: loader,
            accountID: accountID,
            appSession: appSession,
            initialPresentation: presentation
        )
    }

    private func handleAuthenticationFailure()
        async
    {
        guard
            let error = model.authenticationFailure
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
