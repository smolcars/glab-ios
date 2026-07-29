import SwiftUI

struct AssignedIssuesView: View {
    let model: AssignedIssuesModel
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
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        @Bindable var model = model

        content
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Assigned Issues")
            .navigationBarTitleDisplayMode(
                dynamicTypeSize.isAccessibilitySize
                    ? .inline
                    : .large
            )
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search loaded issues"
            )
            .navigationDestination(for: GitLabIssueRoute.self) {
                GitLabIssueDetailView(
                    route: $0,
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
                        onResourceEdited
                )
            }
            .refreshable {
                await refresh()
            }
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingInitial {
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading assigned issues"
                )
                .padding(20)
            }
        } else if model.issues.isEmpty, let error = model.loadError {
            GitLabContentStateScrollView {
                GitLabRetryStateView(error: error) {
                    Task {
                        await refresh()
                    }
                }
            }
        } else if model.issues.isEmpty, model.hasLoaded {
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: "No assigned issues",
                    message:
                        "Open issues assigned to you will appear here.",
                    systemImage: "smallcircle.filled.circle"
                )
            }
        } else {
            issueList
        }
    }

    private var issueList: some View {
        List {
            if model.didFailRefresh, let error = model.loadError {
                GitLabInlineRetryRow(
                    title: "Couldn’t refresh issues",
                    error: error,
                    accessibilityIdentifier:
                        "issues.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            if
                model.displayedIssues.isEmpty,
                !model.searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            {
                ContentUnavailableView.search(
                    text: model.searchText
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(model.displayedIssues) { issue in
                    NavigationLink(value: issue.route) {
                        GitLabIssueRow(issue: issue)
                    }
                    .accessibilityIdentifier(
                        "issues.row.\(issue.projectID).\(issue.iid)"
                    )
                    .task {
                        await model.loadNextPageIfNeeded(
                            after: issue
                        )
                        await handleAuthenticationFailure()
                    }
                }
            }

            if model.isLoadingNextPage {
                HStack {
                    Spacer()
                    ProgressView("Loading more…")
                        .font(.footnote)
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if
                model.didFailNextPage,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t load more issues",
                    error: error,
                    accessibilityIdentifier:
                        "issues.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("issues.assigned.list")
    }

    private func refresh() async {
        await model.refresh()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure() async {
        guard let error = model.authenticationFailure else {
            return
        }
        await appSession.handleAuthenticationFailure(
            error,
            for: accountID
        )
    }
}

private struct GitLabIssueRow: View {
    let issue: GitLabIssue

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(issue.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 3
                )

            if !issue.labels.isEmpty {
                labels
            }

            metadata
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                reference
                updatedTime
            }
        } else {
            HStack(spacing: 6) {
                reference
                Spacer(minLength: 8)
                updatedTime
            }
        }
    }

    private var reference: some View {
        HStack(spacing: 6) {
            Text(issue.references.full)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 1
                )

            if issue.confidential {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Confidential")
            }
        }
    }

    private var updatedTime: some View {
        Text(
            GitLabRelativeTimeFormatter.string(
                from: issue.updatedAt
            )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            "Updated "
                + issue.updatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
        )
    }

    @ViewBuilder
    private var labels: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                labelPills
            }
        } else {
            HStack(spacing: 6) {
                labelPills
            }
        }
    }

    @ViewBuilder
    private var labelPills: some View {
        ForEach(issue.labels.prefix(3), id: \.self) {
            GitLabLabelPill(name: $0)
        }

        if issue.labels.count > 3 {
            Text("+\(issue.labels.count - 3)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                state
                assignees
                comments
            }
        } else {
            HStack(spacing: 12) {
                state
                assignees
                Spacer(minLength: 4)
                comments
            }
        }
    }

    private var state: some View {
        GitLabIssueStateLabel(issue: issue)
            .font(.caption)
    }

    @ViewBuilder
    private var assignees: some View {
        if !issue.assignees.isEmpty {
            Label(
                issue.assignees
                    .map(\.displayName)
                    .joined(separator: ", "),
                systemImage: "person.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(
                dynamicTypeSize.isAccessibilitySize
                    ? nil
                    : 1
            )
        }
    }

    private var comments: some View {
        Label(
            "\(issue.userNotesCount)",
            systemImage: "bubble.left"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var accessibilityLabel: String {
        var parts = [
            issue.references.full,
            issue.title,
            issue.stateTitle,
            "\(issue.userNotesCount) comments",
        ]
        if issue.confidential {
            parts.append("Confidential")
        }
        if !issue.labels.isEmpty {
            parts.append("Labels: \(issue.labels.joined(separator: ", "))")
        }
        if !issue.assignees.isEmpty {
            parts.append(
                "Assigned to "
                    + issue.assignees
                        .map(\.displayName)
                        .joined(separator: ", ")
            )
        }
        return parts.joined(separator: ", ")
    }
}

private struct GitLabIssueStateLabel: View {
    let issue: GitLabIssue

    var body: some View {
        Label(
            issue.stateTitle,
            systemImage: systemImage
        )
        .foregroundStyle(color)
    }

    private var systemImage: String {
        switch issue.stateKind {
        case .opened:
            "smallcircle.filled.circle"
        case .closed:
            "checkmark.circle.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    private var color: Color {
        switch issue.stateKind {
        case .opened:
            .green
        case .closed:
            .purple
        case .unknown:
            .secondary
        }
    }
}

struct GitLabIssueDetailView: View {
    let accountID: GitLabAccountID
    let appSession: AppSession
    let discussionResource:
        GitLabDiscussionResource
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let editService:
        any GitLabResourceEditing
    let issueStatusService:
        any GitLabIssueStatusServing
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @State private var model: GitLabIssueDetailModel
    @State private var discussionModel:
        GitLabDiscussionsModel
    @State private var composerTarget:
        GitLabDiscussionComposerTarget?
    @State private var
        showsReadOnlyCommentAlert = false
    @State private var editorModel:
        GitLabResourceEditorModel?
    @State private var showsEditor = false
    @State private var metadataEditorModel:
        GitLabResourceMetadataEditorModel?
    @State private var stateMutationModel:
        GitLabResourceMetadataEditorModel?
    @State private var pendingStateEvent:
        GitLabResourceStateEvent?
    @State private var
        showsStateConfirmation = false
    @State private var stateFailureMessage:
        String?
    @State private var issueStatusModel:
        GitLabIssueStatusModel?
    @State private var statusFailureMessage:
        String?
    @State private var taskToggleModel:
        GitLabDescriptionTaskToggleModel

    init(
        route: GitLabIssueRoute,
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
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.accountID = accountID
        self.appSession = appSession
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.editService = editService
        self.issueStatusService =
            issueStatusService
        self.onResourceEdited =
            onResourceEdited
        let discussionResource =
            GitLabDiscussionResource.issue(route)
        self.discussionResource =
            discussionResource
        let detailModel =
            GitLabIssueDetailModel(
                route: route,
                loader: loader
            )
        _model = State(
            initialValue: detailModel
        )
        let apiAccess =
            appSession.accounts
                .first {
                    $0.id == accountID
                }?
                .apiAccess
            ?? .readOnly
        _taskToggleModel = State(
            initialValue:
                GitLabDescriptionTaskToggleModel(
                    accountID: accountID,
                    apiAccess: apiAccess,
                    service: editService,
                    draftStore:
                        appSession
                            .resourceEditDraftStore,
                    isAccountCurrent: {
                        appSession
                            .activeAccountID
                            == accountID
                    },
                    onSuccess: {
                        result in
                        guard
                            case let .issue(
                                updatedIssue
                            ) = result,
                            detailModel
                                .reconcileAuthoritative(
                                    updatedIssue
                                )
                        else {
                            return
                        }
                        onResourceEdited(result)
                    },
                    onStale: {
                        await detailModel.retry()
                    }
                )
        )
        _discussionModel = State(
            initialValue:
                GitLabDiscussionsModel(
                    resource: discussionResource,
                    loader: discussionLoader
                )
        )
    }

    var body: some View {
        content
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Issue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isDetailLoaded {
                    GitLabResourceDetailToolbarActions(
                        destination:
                            detailWebURL,
                        openInGitLabAccessibilityIdentifier:
                            "issues.openInGitLab",
                        canEdit:
                            !taskToggleModel
                                .isBusy
                            && !statusMutationIsBlocking
                            && !(
                                metadataEditorModel?
                                    .isBusy
                                ?? false
                            )
                            && !(
                                stateMutationModel?
                                    .isBusy
                                ?? false
                            ),
                        canComment:
                            apiAccess.canWrite,
                        edit: launchEditor,
                        editMetadata:
                            launchMetadataEditor,
                        stateEvent:
                            apiAccess.canWrite
                            ? availableStateEvent
                            : nil,
                        changeState:
                            requestStateChange,
                        addComment: {
                            launchComposer(
                                .newDiscussion
                            )
                        }
                    )
                }
            }
            .refreshable {
                await refresh()
            }
            .task {
                await load()
            }
            .onDisappear {
                taskToggleModel.cancel()
            }
            .onChange(
                of:
                    authenticationFailure
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
            .sheet(item: $composerTarget) {
                target in
                GitLabDiscussionComposerView(
                    accountID: accountID,
                    resource:
                        discussionResource,
                    target: target,
                    apiAccess: apiAccess,
                    mutator:
                        discussionMutator,
                    draftStore:
                        appSession
                            .discussionDraftStore,
                    appSession: appSession,
                    onSuccess:
                        discussionModel
                            .reconcile
                )
                .presentationDragIndicator(
                    .visible
                )
            }
            .sheet(
                isPresented: $showsEditor,
                onDismiss: {
                    editorModel = nil
                }
            ) {
                if let editorModel {
                    GitLabResourceEditorView(
                        model: editorModel,
                        accountID: accountID,
                        appSession: appSession,
                        webURL: detailWebURL
                    )
                    .presentationDragIndicator(
                        .visible
                    )
                }
            }
            .sheet(
                item: $metadataEditorModel
            ) { metadataEditorModel in
                GitLabResourceMetadataEditorView(
                    model:
                        metadataEditorModel,
                    accountID: accountID,
                    appSession: appSession
                )
                .presentationDragIndicator(
                    .visible
                )
            }
            .alert(
                stateConfirmationTitle,
                isPresented:
                    $showsStateConfirmation
            ) {
                Button(
                    stateConfirmationActionTitle,
                    role:
                        pendingStateEvent == .close
                        ? .destructive
                        : nil
                ) {
                    performStateChange()
                }
                Button(
                    "Cancel",
                    role: .cancel
                ) {
                    pendingStateEvent = nil
                }
            } message: {
                Text(
                    stateConfirmationMessage
                )
            }
            .alert(
                "Couldn’t update issue",
                isPresented:
                    stateFailureIsPresented
            ) {
                Button("OK", role: .cancel) {
                    stateFailureMessage = nil
                }
            } message: {
                Text(
                    stateFailureMessage ?? ""
                )
            }
            .alert(
                statusConfirmationTitle,
                isPresented:
                    statusConfirmationIsPresented
            ) {
                Button(
                    statusConfirmationActionTitle,
                    role:
                        issueStatusModel?
                            .selectionConfirmation?
                            .resultingState
                            == .closed
                        ? .destructive
                        : nil
                ) {
                    confirmStatusSelection()
                }
                Button(
                    "Cancel",
                    role: .cancel
                ) {
                    issueStatusModel?
                        .cancelSelection()
                }
            } message: {
                Text(
                    statusConfirmationMessage
                )
            }
            .alert(
                "Couldn’t update status",
                isPresented:
                    statusFailureIsPresented
            ) {
                Button("OK", role: .cancel) {
                    statusFailureMessage = nil
                }
            } message: {
                Text(
                    statusFailureMessage ?? ""
                )
            }
            .alert(
                "Commenting unavailable",
                isPresented:
                    $showsReadOnlyCommentAlert
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(
                    "This account has read-only API access. Sign in with OAuth or an API token with the api scope to post comments."
                )
            }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ScrollView {
                GitLabLoadingStateView(
                    message: "Loading issue"
                )
                .padding(20)
            }
        case let .failed(error):
            GitLabRetryStateView(error: error) {
                Task {
                    await refresh()
                }
            }
        case let .loaded(issue):
            VStack(spacing: 0) {
                if let error = model.refreshError {
                    GitLabInlineRetryRow(
                        title:
                            "Couldn’t refresh issue",
                        error: error,
                        accessibilityIdentifier:
                            "issues.detailRefreshError"
                    ) {
                        Task {
                            await refresh()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                GitLabIssueDetailContent(
                    issue: issue,
                    discussionModel:
                        discussionModel,
                    discussionResource:
                        discussionResource,
                    accountID: accountID,
                    apiAccess: apiAccess,
                    reactionService:
                        reactionService,
                    launchComposer:
                        launchComposer,
                    appSession: appSession,
                    issueStatusModel:
                        issueStatusModel,
                    isResourceMutationBusy:
                        resourceMutationIsBusy,
                    statusActionDidFinish:
                        handleStatusActionResult,
                    taskInteraction:
                        GitLabMarkdownTaskInteraction(
                            model:
                                taskToggleModel,
                            snapshot:
                                GitLabResourceEditSnapshot(
                                    issue: issue
                                ),
                            isExternallyDisabled:
                                statusMutationIsBlocking,
                            openEditor:
                                launchEditor
                        )
                )
            }
        }
    }

    private var authenticationFailure:
        GitLabSessionClientError?
    {
        model.authenticationFailure
            ?? discussionModel.authenticationFailure
            ?? taskToggleModel
                .authenticationFailure
            ?? issueStatusModel?
                .authenticationFailure
    }

    private var apiAccess:
        GitLabAPIAccess
    {
        appSession.accounts
            .first {
                $0.id == accountID
            }?
            .apiAccess
            ?? .readOnly
    }

    private var isDetailLoaded: Bool {
        guard case .loaded = model.state else {
            return false
        }
        return true
    }

    private var detailWebURL: URL? {
        guard
            case let .loaded(issue) =
                model.state
        else {
            return nil
        }
        return issue.safeWebURL
    }

    private func launchComposer(
        _ target:
            GitLabDiscussionComposerTarget
    ) {
        switch
            GitLabDiscussionComposerLaunchPolicy
                .decision(
                    for: target,
                    apiAccess: apiAccess
                )
        {
        case let .present(target):
            composerTarget = target
        case .explainReadOnly:
            showsReadOnlyCommentAlert = true
        }
    }

    private func launchEditor() {
        guard
            !taskToggleModel.isBusy,
            !statusMutationIsBlocking
        else {
            return
        }
        if let recoveryEditor =
            taskToggleModel
                .takeRecoveryEditor()
        {
            editorModel = recoveryEditor
            showsEditor = true
            return
        }
        guard
            case let .loaded(issue) =
                model.state
        else {
            return
        }

        editorModel =
            GitLabResourceEditorModel(
                accountID: accountID,
                baseline:
                    GitLabResourceEditSnapshot(
                        issue: issue
                    ),
                apiAccess: apiAccess,
                service: editService,
                draftStore:
                    appSession
                        .resourceEditDraftStore,
                isAccountCurrent: {
                    appSession.activeAccountID
                        == accountID
                },
                onSuccess: {
                    result in
                    guard
                        case let .issue(
                            updatedIssue
                        ) = result
                    else {
                        return
                    }
                    guard
                        model
                            .reconcileAuthoritative(
                                updatedIssue
                            )
                    else {
                        return
                    }
                    taskToggleModel.cancel()
                    onResourceEdited(result)
                }
            )
        showsEditor = true
    }

    private func launchMetadataEditor() {
        guard
            !taskToggleModel.isBusy,
            !statusMutationIsBlocking,
            case let .loaded(issue) =
                model.state
        else {
            return
        }
        metadataEditorModel =
            makeMetadataEditor(
                for: .issue(issue)
            )
    }

    private func requestStateChange(
        _ event: GitLabResourceStateEvent
    ) {
        guard
            apiAccess.canWrite,
            !taskToggleModel.isBusy,
            !statusMutationIsBlocking,
            case .loaded =
                model.state
        else {
            return
        }
        pendingStateEvent = event
        showsStateConfirmation = true
    }

    private func performStateChange() {
        guard
            let event = pendingStateEvent,
            case let .loaded(issue) =
                model.state
        else {
            return
        }
        pendingStateEvent = nil
        let metadataEditorModel =
            makeMetadataEditor(
                for: .issue(issue)
            )
        stateMutationModel =
            metadataEditorModel
        Task {
            await metadataEditorModel
                .changeState(event)
            guard !metadataEditorModel.didSucceed else {
                stateMutationModel = nil
                return
            }
            if
                let error =
                    metadataEditorModel
                        .authenticationFailure
            {
                stateMutationModel = nil
                await appSession
                    .handleAuthenticationFailure(
                        error,
                        for: accountID
                    )
                return
            }
            if
                metadataEditorModel
                    .requiresDeliveryCheck
            {
                self.metadataEditorModel =
                    metadataEditorModel
            } else {
                stateFailureMessage =
                    metadataEditorModel
                        .failure?
                        .description
            }
            stateMutationModel = nil
        }
    }

    private func makeMetadataEditor(
        for baseline:
            GitLabResourceEditResult
    ) -> GitLabResourceMetadataEditorModel {
        GitLabResourceMetadataEditorModel(
            accountID: accountID,
            baseline: baseline,
            apiAccess: apiAccess,
            service: editService,
            isAccountCurrent: {
                appSession.activeAccountID
                    == accountID
            },
            onSuccess: {
                result in
                guard
                    case let .issue(
                        updatedIssue
                    ) = result,
                    model.reconcileAuthoritative(
                        updatedIssue
                    )
                else {
                    return
                }
                taskToggleModel.cancel()
                onResourceEdited(result)
                Task {
                    await issueStatusModel?
                        .refreshAfterIssueMutation(
                            updatedIssue
                        )
                }
            }
        )
    }

    private var availableStateEvent:
        GitLabResourceStateEvent?
    {
        guard
            case let .loaded(issue) =
                model.state
        else {
            return nil
        }
        return switch issue.stateKind {
        case .opened:
            .close
        case .closed:
            .reopen
        case .unknown:
            nil
        }
    }

    private var resourceMutationIsBusy: Bool {
        taskToggleModel.isBusy
            || (
                metadataEditorModel?
                    .isBusy
                ?? false
            )
            || (
                stateMutationModel?
                    .isBusy
                ?? false
            )
    }

    private var statusMutationIsBlocking: Bool {
        (
            issueStatusModel?
                .isBusy
            ?? false
        )
            || (
                issueStatusModel?
                    .requiresDeliveryCheck
                ?? false
            )
    }

    private var stateConfirmationTitle: String {
        pendingStateEvent == .close
            ? "Close issue?"
            : "Reopen issue?"
    }

    private var stateConfirmationActionTitle:
        String
    {
        pendingStateEvent == .close
            ? "Close"
            : "Reopen"
    }

    private var stateConfirmationMessage: String {
        pendingStateEvent == .close
            ? "This will close the issue on GitLab and may remove it from your assigned work."
            : "This will reopen the issue on GitLab and may return it to your assigned work."
    }

    private var statusConfirmationTitle:
        String
    {
        issueStatusModel?
            .selectionConfirmation?
            .resultingState
            == .closed
            ? "Close issue?"
            : "Reopen issue?"
    }

    private var statusConfirmationActionTitle:
        String
    {
        issueStatusModel?
            .selectionConfirmation?
            .resultingState
            == .closed
            ? "Change & close"
            : "Change & reopen"
    }

    private var statusConfirmationMessage:
        String
    {
        guard
            let confirmation =
                issueStatusModel?
                    .selectionConfirmation
        else {
            return ""
        }
        return confirmation.resultingState
            == .closed
            ? "Changing the work item status to \(confirmation.status.name) will also close this issue."
            : "Changing the work item status to \(confirmation.status.name) will also reopen this issue."
    }

    private var statusConfirmationIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                issueStatusModel?
                    .selectionConfirmation
                    != nil
            },
            set: {
                if !$0 {
                    issueStatusModel?
                        .cancelSelection()
                }
            }
        )
    }

    private func confirmStatusSelection() {
        Task {
            await issueStatusModel?
                .confirmSelection()
            handleStatusActionResult()
        }
    }

    private func handleStatusActionResult() {
        guard
            let failure =
                issueStatusModel?
                    .failure
        else {
            statusFailureMessage = nil
            return
        }
        guard
            failure.authenticationFailure
                == nil
        else {
            return
        }

        statusFailureMessage =
            switch failure {
            case .readOnly:
                "This account has read-only API access."
            case .permissionDenied:
                "GitLab does not allow this account to change the status of this issue."
            case .stale:
                "The status changed on GitLab. Review the latest status and try again."
            case .rejected:
                "GitLab rejected the status change."
            case .deliveryUnknown:
                "GitLab may have received the change. Use the status check button before trying again."
            case .reconciliation:
                "The status changed, but the latest issue details could not be loaded. Use the status check button."
            case .authoritativeMismatch:
                "GitLab returned issue details that do not match the new status. Use the status check button."
            case .notApplied:
                "GitLab confirmed that the status change was not applied."
            case .load:
                "The latest work item status could not be loaded."
            }
    }

    private var stateFailureIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                stateFailureMessage != nil
            },
            set: {
                if !$0 {
                    stateFailureMessage = nil
                }
            }
        )
    }

    private var statusFailureIsPresented:
        Binding<Bool>
    {
        Binding(
            get: {
                statusFailureMessage
                    != nil
            },
            set: {
                if !$0 {
                    statusFailureMessage =
                        nil
                }
            }
        )
    }

    private func load() async {
        async let detail: Void =
            model.loadIfNeeded()
        async let discussion: Void =
            discussionModel.loadIfNeeded()
        await detail
        await loadStatusIfNeeded()
        await discussion
    }

    private func refresh() async {
        async let detail: Void = model.retry()
        async let discussion: Void =
            discussionModel.refresh()
        await detail
        if let issueStatusModel {
            await issueStatusModel.refresh()
        } else {
            await loadStatusIfNeeded()
        }
        await discussion
    }

    private func loadStatusIfNeeded() async {
        guard
            issueStatusModel == nil,
            case let .loaded(issue) =
                model.state
        else {
            return
        }

        let statusModel =
            GitLabIssueStatusModel(
                accountID: accountID,
                issue: issue,
                apiAccess: apiAccess,
                statusService:
                    issueStatusService,
                resourceService:
                    editService,
                isAccountCurrent: {
                    appSession
                        .activeAccountID
                        == accountID
                },
                onIssueReconciled: {
                    updatedIssue in
                    guard
                        model
                            .reconcileAuthoritative(
                                updatedIssue
                            )
                    else {
                        return
                    }
                    taskToggleModel.cancel()
                    onResourceEdited(
                        .issue(updatedIssue)
                    )
                }
            )
        issueStatusModel = statusModel
        await statusModel.load()
    }
}

private struct GitLabIssueDetailContent: View {
    let issue: GitLabIssue
    let discussionModel: GitLabDiscussionsModel
    let discussionResource:
        GitLabDiscussionResource
    let accountID: GitLabAccountID
    let apiAccess: GitLabAPIAccess
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let launchComposer:
        (GitLabDiscussionComposerTarget) -> Void
    let appSession: AppSession
    let issueStatusModel:
        GitLabIssueStatusModel?
    let isResourceMutationBusy: Bool
    let statusActionDidFinish:
        () -> Void
    let taskInteraction:
        GitLabMarkdownTaskInteraction

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer

    var body: some View {
        ScrollView {
            GitLabDetailScrollContent {
                header

                GitLabEmojiReactionView(
                    awardable:
                        .resource(
                            discussionResource
                        ),
                    currentUserID:
                        accountID.userID,
                    apiAccess: apiAccess,
                    loader: reactionService,
                    mutator:
                        reactionService,
                    accountID: accountID,
                    appSession: appSession
                )

                if issue.confidential {
                    Label(
                        "This issue is confidential",
                        systemImage: "lock.fill"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)
                }

                descriptionSection

                if !issue.labels.isEmpty {
                    labelsSection
                }

                peopleSection

                if issue.milestone != nil || issue.dueDate != nil {
                    planningSection
                }

                timestampsSection

                GitLabDiscussionSection(
                    model: discussionModel,
                    resource: discussionResource,
                    accountID: accountID,
                    webURL: issue.safeWebURL,
                    apiAccess: apiAccess,
                    reactionService:
                        reactionService,
                    resolutionModel: nil,
                    appSession: appSession,
                    launchComposer:
                        launchComposer
                )
            }
        }
        .accessibilityIdentifier("issues.detail.scroll")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.references.full)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(issue.title)
                .font(.title2.bold())
                .textSelection(.enabled)

            ViewThatFits(
                in: .horizontal
            ) {
                HStack(spacing: 12) {
                    issueMetadata
                    statusControl
                }

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    issueMetadata
                    statusControl
                }
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private var issueMetadata:
        some View
    {
        HStack(spacing: 12) {
            GitLabIssueStateLabel(
                issue: issue
            )

            Label(
                "\(issue.userNotesCount) comments",
                systemImage: "bubble.left"
            )
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var statusControl:
        some View
    {
        if let issueStatusModel {
            GitLabIssueStatusControl(
                model: issueStatusModel,
                isExternallyDisabled:
                    isResourceMutationBusy,
                actionDidFinish:
                    statusActionDidFinish
            )
        }
    }

    private var descriptionSection: some View {
        GitLabDetailSection(title: "Description") {
            if
                let request =
                    GitLabDescriptionMarkdownRequest
                    .issue(
                        accountID: accountID,
                        issue: issue
                    )
            {
                GitLabMarkdownContentView(
                    request: request,
                    revision: issue.updatedAt,
                    kind: .description,
                    renderer: markdownRenderer,
                    taskInteraction:
                        taskInteraction
                )
            } else {
                Text("No description provided.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var labelsSection: some View {
        GitLabDetailSection(title: "Labels") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(issue.labels, id: \.self) {
                        GitLabLabelPill(name: $0)
                    }
                }
            }
        }
    }

    private var peopleSection: some View {
        GitLabDetailSection(title: "People") {
            VStack(alignment: .leading, spacing: 14) {
                GitLabAPIUserRow(
                    user: issue.author,
                    role: "Author"
                )

                if issue.assignees.isEmpty {
                    LabeledContent(
                        "Assignees",
                        value: "Unassigned"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(issue.assignees) {
                        GitLabAPIUserRow(
                            user: $0,
                            role: "Assignee"
                        )
                    }
                }
            }
        }
    }

    private var planningSection: some View {
        GitLabDetailSection(title: "Planning") {
            VStack(alignment: .leading, spacing: 10) {
                if let milestone = issue.milestone {
                    LabeledContent(
                        "Milestone",
                        value: milestone.title
                    )
                }

                if let dueDate = issue.dueDate {
                    LabeledContent(
                        "Due",
                        value:
                            GitLabIssueDateFormatter.dueDate(dueDate)
                            ?? dueDate
                    )
                }
            }
        }
    }

    private var timestampsSection: some View {
        GitLabDetailSection(title: "Activity") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(
                    "Created",
                    value: issue.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                LabeledContent(
                    "Updated",
                    value: issue.updatedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                if let closedAt = issue.closedAt {
                    LabeledContent(
                        "Closed",
                        value: closedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
            }
        }
    }
}
