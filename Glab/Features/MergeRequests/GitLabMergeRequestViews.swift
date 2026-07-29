import SwiftUI

struct MergeRequestsView: View {
    let mode: GitLabMergeRequestListMode
    let loader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    let discussionLoader:
        any GitLabDiscussionLoading
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let editService:
        any GitLabResourceEditing
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    @State private var model: MergeRequestsModel

    init(
        mode: GitLabMergeRequestListMode,
        loader:
            any GitLabMergeRequestLoading
                & GitLabMergeRequestApprovalLoading
                & GitLabMergeRequestDiffLoading
                & GitLabMergeRequestDiffSummaryLoading,
        discussionLoader:
            any GitLabDiscussionLoading,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        editService:
            any GitLabResourceEditing,
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.mode = mode
        self.loader = loader
        self.discussionLoader =
            discussionLoader
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.editService = editService
        self.accountID = accountID
        self.appSession = appSession
        self.onResourceEdited =
            onResourceEdited
        _model = State(
            initialValue: MergeRequestsModel(
                mode: mode,
                loader: loader
            )
        )
    }

    var body: some View {
        @Bindable var model = model

        content
            .background(
                Color(uiColor: .systemGroupedBackground)
            )
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $model.searchText,
                placement:
                    .navigationBarDrawer(
                        displayMode: .always
                    ),
                prompt: "Search loaded merge requests"
            )
            .navigationDestination(
                for: GitLabMergeRequestRoute.self
            ) {
                GitLabMergeRequestDetailView(
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
                    accountID: accountID,
                    appSession: appSession,
                    onResourceEdited: {
                        result in
                        if
                            case let .mergeRequest(
                                mergeRequest
                            ) = result
                        {
                            _ = model
                                .reconcileMergeRequest(
                                    mergeRequest,
                                    mode: mode,
                                    currentUserID:
                                        accountID
                                        .userID
                                )
                        }
                        onResourceEdited(result)
                    }
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
                    message: "Loading \(mode.title.lowercased())"
                )
                .padding(20)
            }
        } else if
            model.mergeRequests.isEmpty,
            let error = model.loadError
        {
            GitLabContentStateScrollView {
                GitLabRetryStateView(
                    error: error
                ) {
                    Task {
                        await refresh()
                    }
                }
            }
        } else if
            model.mergeRequests.isEmpty,
            model.hasLoaded
        {
            GitLabContentStateScrollView {
                GitLabEmptyStateView(
                    title: mode.emptyTitle,
                    message: mode.emptyMessage,
                    systemImage: mode == .assigned
                        ? "arrow.triangle.branch"
                        : "person.crop.circle.badge.checkmark"
                )
            }
        } else {
            mergeRequestList
        }
    }

    private var mergeRequestList: some View {
        List {
            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title:
                        "Couldn’t refresh merge requests",
                    error: error,
                    accessibilityIdentifier:
                        "mergeRequests.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            if
                model.displayedMergeRequests.isEmpty,
                !model.searchText.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ).isEmpty
            {
                ContentUnavailableView.search(
                    text: model.searchText
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(
                    model.displayedMergeRequests
                ) { mergeRequest in
                    NavigationLink(
                        value: mergeRequest.route
                    ) {
                        GitLabMergeRequestRow(
                            mergeRequest: mergeRequest
                        )
                    }
                    .accessibilityIdentifier(
                        "mergeRequests.row."
                            + "\(mergeRequest.projectID)."
                            + "\(mergeRequest.iid)"
                    )
                    .task {
                        await model
                            .loadNextPageIfNeeded(
                                after: mergeRequest
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
                    title:
                        "Couldn’t load more merge requests",
                    error: error,
                    accessibilityIdentifier:
                        "mergeRequests.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(
            "mergeRequests.\(mode.rawValue).list"
        )
    }

    private func refresh() async {
        await model.refresh()
        await handleAuthenticationFailure()
    }

    private func handleAuthenticationFailure() async {
        guard
            let error = model.authenticationFailure
        else {
            return
        }
        await appSession.handleAuthenticationFailure(
            error,
            for: accountID
        )
    }
}

private struct GitLabMergeRequestRow: View {
    let mergeRequest: GitLabMergeRequest

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            Text(mergeRequest.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 3
                )

            if !mergeRequest.labels.isEmpty {
                labels
            }

            branchStatus
            people
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
        Text(mergeRequest.references.full)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(
                dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 1
            )
            .fixedSize(
                horizontal: false,
                vertical: dynamicTypeSize.isAccessibilitySize
            )
    }

    private var updatedTime: some View {
        Text(
            GitLabRelativeTimeFormatter.string(
                from: mergeRequest.updatedAt
            )
        )
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
        .accessibilityLabel(
            "Updated "
                + mergeRequest.updatedAt.formatted(
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
        ForEach(
            mergeRequest.labels.prefix(3),
            id: \.self
        ) {
            GitLabLabelPill(name: $0)
        }

        if mergeRequest.labels.count > 3 {
            Text(
                "+\(mergeRequest.labels.count - 3)"
            )
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var branchStatus: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                branch

                HStack(spacing: 12) {
                    draft
                    comments
                }
            }
        } else {
            HStack(spacing: 12) {
                branch
                draft
                Spacer(minLength: 4)
                comments
            }
        }
    }

    private var branch: some View {
        Label {
            Text(
                mergeRequest.sourceBranch
                    + " → "
                    + mergeRequest.targetBranch
            )
            .foregroundStyle(.secondary)
        } icon: {
            GitLabMergeRequestStateIcon(
                mergeRequest: mergeRequest
            )
        }
        .font(.caption)
        .lineLimit(
            dynamicTypeSize.isAccessibilitySize
                ? nil
                : 1
        )
        .accessibilityLabel(
            mergeRequest.stateTitle
                + ", from "
                + mergeRequest.sourceBranch
                + " to "
                + mergeRequest.targetBranch
        )
    }

    @ViewBuilder
    private var draft: some View {
        if mergeRequest.isDraft {
            GitLabMergeRequestDraftLabel()
                .font(.caption)
        }
    }

    private var comments: some View {
        Label(
            "\(mergeRequest.userNotesCount)",
            systemImage: "bubble.left"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var people: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                author
                if let peopleSummary {
                    Text(peopleSummary)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                author

                if let peopleSummary {
                    Text("•")
                    Text(peopleSummary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var author: some View {
        Label(
            mergeRequest.author.displayName,
            systemImage: "person.crop.circle"
        )
        .lineLimit(
            dynamicTypeSize.isAccessibilitySize
                ? nil
                : 1
        )
    }

    private var peopleSummary: String? {
        var parts: [String] = []

        if !mergeRequest.assignees.isEmpty {
            parts.append(
                "Assigned: "
                    + mergeRequest.assignees
                        .map(\.displayName)
                        .joined(separator: ", ")
            )
        }
        if !mergeRequest.reviewers.isEmpty {
            parts.append(
                "Reviewers: "
                    + mergeRequest.reviewers
                        .map(\.displayName)
                        .joined(separator: ", ")
            )
        }

        return parts.isEmpty
            ? nil
            : parts.joined(separator: " • ")
    }

    private var accessibilityLabel: String {
        var parts = [
            mergeRequest.references.full,
            mergeRequest.title,
            mergeRequest.isDraft
                ? "Draft"
                : mergeRequest.stateTitle,
            "From \(mergeRequest.sourceBranch) "
                + "to \(mergeRequest.targetBranch)",
            "Author \(mergeRequest.author.displayName)",
            "\(mergeRequest.userNotesCount) comments",
        ]
        if mergeRequest.isDraft {
            parts.append(mergeRequest.stateTitle)
        }
        if !mergeRequest.labels.isEmpty {
            parts.append(
                "Labels: "
                    + mergeRequest.labels.joined(
                        separator: ", "
                    )
            )
        }
        if let peopleSummary {
            parts.append(peopleSummary)
        }
        return parts.joined(separator: ", ")
    }
}

private struct GitLabMergeRequestStateIcon: View {
    let mergeRequest: GitLabMergeRequest

    var body: some View {
        Image(systemName: systemImage)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var systemImage: String {
        switch mergeRequest.stateKind {
        case .opened:
            "arrow.triangle.branch"
        case .closed:
            "xmark.circle.fill"
        case .merged:
            "arrow.triangle.merge"
        case .locked:
            "lock.fill"
        case .unknown:
            "questionmark.circle"
        }
    }

    private var color: Color {
        switch mergeRequest.stateKind {
        case .opened:
            .green
        case .closed:
            .red
        case .merged:
            .purple
        case .locked:
            .orange
        case .unknown:
            .secondary
        }
    }
}

private struct GitLabMergeRequestStateLabel: View {
    let mergeRequest: GitLabMergeRequest

    var body: some View {
        Label {
            Text(mergeRequest.stateTitle)
        } icon: {
            GitLabMergeRequestStateIcon(
                mergeRequest: mergeRequest
            )
        }
    }
}

private struct GitLabMergeRequestDraftLabel: View {
    var body: some View {
        Image(systemName: "pencil.line")
            .foregroundStyle(.orange)
            .accessibilityLabel("Draft")
    }
}

struct GitLabMergeRequestDetailView: View {
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
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void
    let diffLoader:
        any GitLabMergeRequestDiffLoading
    let diffSummaryLoader:
        any GitLabMergeRequestDiffSummaryLoading

    @State private var model:
        GitLabMergeRequestDetailModel
    @State private var approvalModel:
        GitLabMergeRequestApprovalModel
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
    @State private var
        showsMetadataEditor = false
    @State private var pendingStateEvent:
        GitLabResourceStateEvent?
    @State private var
        showsStateConfirmation = false
    @State private var stateFailureMessage:
        String?
    @State private var taskToggleModel:
        GitLabDescriptionTaskToggleModel
    @State private var resolutionModel:
        GitLabDiscussionResolutionModel

    init(
        route: GitLabMergeRequestRoute,
        loader:
            any GitLabMergeRequestLoading
                & GitLabMergeRequestApprovalLoading
                & GitLabMergeRequestDiffLoading
                & GitLabMergeRequestDiffSummaryLoading,
        discussionLoader:
            any GitLabDiscussionLoading,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        editService:
            any GitLabResourceEditing,
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
        self.onResourceEdited =
            onResourceEdited
        diffLoader = loader
        diffSummaryLoader = loader
        let discussionResource =
            GitLabDiscussionResource
                .mergeRequest(route)
        self.discussionResource =
            discussionResource
        let detailModel =
            GitLabMergeRequestDetailModel(
                route: route,
                loader: loader
            )
        let discussionModel =
            GitLabDiscussionsModel(
                resource: discussionResource,
                loader: discussionLoader
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
                            case let .mergeRequest(
                                updatedMergeRequest
                            ) = result,
                            detailModel
                                .reconcileAuthoritative(
                                    updatedMergeRequest
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
        _approvalModel = State(
            initialValue:
                GitLabMergeRequestApprovalModel(
                    route: route,
                    loader: loader
                )
        )
        _discussionModel = State(
            initialValue: discussionModel
        )
        _resolutionModel = State(
            initialValue:
                GitLabDiscussionResolutionModel(
                    accountID: accountID,
                    route: route,
                    apiAccess: apiAccess,
                    mutator: discussionMutator,
                    isAccountCurrent: {
                        appSession
                            .activeAccountID
                            == accountID
                    },
                    currentDiscussion: {
                        discussionID in
                        discussionModel
                            .discussions
                            .first {
                                $0.id
                                    == discussionID
                            }
                    },
                    reconcile: {
                        discussionModel
                            .reconcileAuthoritativeDiscussion(
                                $0
                            )
                    },
                    refreshReadiness: {
                        await detailModel.retry()
                    }
                )
        )
    }

    var body: some View {
        content
            .background(
                Color(uiColor: .systemGroupedBackground)
            )
            .navigationTitle("Merge Request")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isDetailLoaded {
                    GitLabResourceDetailToolbarActions(
                        destination:
                            detailWebURL,
                        openInGitLabAccessibilityIdentifier:
                            "mergeRequests.openInGitLab",
                        canEdit:
                            !taskToggleModel
                                .isBusy
                            && !(
                                metadataEditorModel?
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
                resolutionModel.cancelAll()
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
                isPresented:
                    $showsMetadataEditor,
                onDismiss: {
                    metadataEditorModel = nil
                }
            ) {
                if let metadataEditorModel {
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
                "Couldn’t update merge request",
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
                    message: "Loading merge request"
                )
                .padding(20)
            }
        case let .failed(error):
            GitLabRetryStateView(
                error: error
            ) {
                Task {
                    await refresh()
                }
            }
        case let .loaded(mergeRequest):
            VStack(spacing: 0) {
                if let error = model.refreshError {
                    GitLabInlineRetryRow(
                        title:
                            "Couldn’t refresh merge request",
                        error: error,
                        accessibilityIdentifier:
                            "mergeRequests.detailRefreshError"
                    ) {
                        Task {
                            await refresh()
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                }

                GitLabMergeRequestDetailContent(
                    mergeRequest: mergeRequest,
                    approvalState:
                        approvalModel.state,
                    approvalError:
                        approvalError,
                    hasReadinessRefreshFailure:
                        model.refreshError != nil
                        || approvalModel
                            .refreshError != nil,
                    retryApproval: {
                        Task {
                            await approvalModel
                                .retry()
                        }
                    },
                    discussionModel:
                        discussionModel,
                    resolutionModel:
                        resolutionModel,
                    discussionResource:
                        discussionResource,
                    accountID: accountID,
                    apiAccess:
                        apiAccess,
                    discussionMutator:
                        discussionMutator,
                    reactionService:
                        reactionService,
                    diffLoader:
                        diffLoader,
                    diffSummaryLoader:
                        diffSummaryLoader,
                    launchComposer:
                        launchComposer,
                    appSession: appSession,
                    taskInteraction:
                        GitLabMarkdownTaskInteraction(
                            model:
                                taskToggleModel,
                            snapshot:
                                GitLabResourceEditSnapshot(
                                    mergeRequest:
                                        mergeRequest
                                ),
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
            ?? approvalModel
                .authenticationFailure
            ?? discussionModel.authenticationFailure
            ?? resolutionModel
                .authenticationFailure
            ?? taskToggleModel
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
            case let .loaded(mergeRequest) =
                model.state
        else {
            return nil
        }
        return mergeRequest.safeWebURL
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
        guard !taskToggleModel.isBusy else {
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
            case let .loaded(mergeRequest) =
                model.state
        else {
            return
        }

        editorModel =
            GitLabResourceEditorModel(
                accountID: accountID,
                baseline:
                    GitLabResourceEditSnapshot(
                        mergeRequest:
                            mergeRequest
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
                        case let .mergeRequest(
                            updatedMergeRequest
                        ) = result
                    else {
                        return
                    }
                    guard
                        model
                            .reconcileAuthoritative(
                                updatedMergeRequest
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
            case let .loaded(mergeRequest) =
                model.state
        else {
            return
        }
        metadataEditorModel =
            makeMetadataEditor(
                for:
                    .mergeRequest(
                        mergeRequest
                    )
            )
        showsMetadataEditor = true
    }

    private func requestStateChange(
        _ event: GitLabResourceStateEvent
    ) {
        guard
            apiAccess.canWrite,
            !taskToggleModel.isBusy,
            case let .loaded(mergeRequest) =
                model.state
        else {
            return
        }
        metadataEditorModel =
            makeMetadataEditor(
                for:
                    .mergeRequest(
                        mergeRequest
                    )
            )
        pendingStateEvent = event
        showsStateConfirmation = true
    }

    private func performStateChange() {
        guard
            let event = pendingStateEvent,
            let metadataEditorModel
        else {
            return
        }
        pendingStateEvent = nil
        Task {
            await metadataEditorModel
                .changeState(event)
            guard !metadataEditorModel.didSucceed else {
                self.metadataEditorModel = nil
                return
            }
            if
                metadataEditorModel
                    .requiresDeliveryCheck
            {
                showsMetadataEditor = true
            } else {
                stateFailureMessage =
                    metadataEditorModel
                        .failure?
                        .description
            }
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
                    case let .mergeRequest(
                        updatedMergeRequest
                    ) = result,
                    model.reconcileAuthoritative(
                        updatedMergeRequest
                    )
                else {
                    return
                }
                taskToggleModel.cancel()
                onResourceEdited(result)
            }
        )
    }

    private var availableStateEvent:
        GitLabResourceStateEvent?
    {
        guard
            case let .loaded(mergeRequest) =
                model.state
        else {
            return nil
        }
        return switch
            mergeRequest.stateKind
        {
        case .opened:
            .close
        case .closed:
            .reopen
        case .merged,
             .locked,
             .unknown:
            nil
        }
    }

    private var stateConfirmationTitle: String {
        pendingStateEvent == .close
            ? "Close merge request?"
            : "Reopen merge request?"
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
            ? "This will close the merge request on GitLab."
            : "This will reopen the merge request on GitLab."
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

    private var approvalError:
        GitLabSessionClientError?
    {
        if let refreshError =
            approvalModel.refreshError
        {
            return refreshError
        }
        guard
            case let .failed(error) =
                approvalModel.state
        else {
            return nil
        }
        return error
    }

    private func load() async {
        async let detail: Void =
            model.loadIfNeeded()
        async let approval: Void =
            approvalModel.loadIfNeeded()
        async let discussion: Void =
            discussionModel.loadIfNeeded()
        _ = await (
            detail,
            approval,
            discussion
        )
    }

    private func refresh() async {
        async let detail: Void = model.retry()
        async let approval: Void =
            approvalModel.retry()
        async let discussion: Void =
            discussionModel.refresh()
        _ = await (
            detail,
            approval,
            discussion
        )
    }
}

private struct GitLabMergeRequestDetailContent: View {
    let mergeRequest: GitLabMergeRequest
    let approvalState:
        GitLabResourceDetailState<
            GitLabMergeRequestApprovalAvailability
        >
    let approvalError:
        GitLabSessionClientError?
    let hasReadinessRefreshFailure:
        Bool
    let retryApproval: () -> Void
    let discussionModel: GitLabDiscussionsModel
    let resolutionModel:
        GitLabDiscussionResolutionModel
    let discussionResource:
        GitLabDiscussionResource
    let accountID: GitLabAccountID
    let apiAccess: GitLabAPIAccess
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let diffLoader:
        any GitLabMergeRequestDiffLoading
    let diffSummaryLoader:
        any GitLabMergeRequestDiffSummaryLoading
    let launchComposer:
        (GitLabDiscussionComposerTarget) -> Void
    let appSession: AppSession
    let taskInteraction:
        GitLabMarkdownTaskInteraction

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer

    var body: some View {
        ScrollView {
            GitLabDetailScrollContent(
                bottomPadding: 76
            ) {
                header

                GitLabMergeRequestReadinessView(
                    readiness:
                        GitLabMergeRequestReadiness(
                            mergeRequest:
                                mergeRequest,
                            approvalState:
                                approvalState,
                            hasRefreshFailure:
                                hasReadinessRefreshFailure
                        ),
                    approvalError:
                        approvalError,
                    retryApproval:
                        retryApproval
                )

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
                descriptionSection
                branchesSection

                if !mergeRequest.labels.isEmpty {
                    labelsSection
                }

                peopleSection
                timestampsSection

                GitLabDiscussionSection(
                    model: discussionModel,
                    resource: discussionResource,
                    accountID: accountID,
                    webURL:
                        mergeRequest.safeWebURL,
                    apiAccess: apiAccess,
                    reactionService:
                        reactionService,
                    resolutionModel:
                        resolutionModel,
                    appSession: appSession,
                    launchComposer:
                        launchComposer
                )
            }
        }
        .accessibilityIdentifier(
            "mergeRequests.detail.scroll"
        )
        .safeAreaInset(edge: .bottom) {
            bottomControls
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(mergeRequest.references.full)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(mergeRequest.title)
                .font(.title2.bold())
                .textSelection(.enabled)

            HStack(spacing: 12) {
                GitLabMergeRequestStateLabel(
                    mergeRequest: mergeRequest
                )

                if mergeRequest.isDraft {
                    GitLabMergeRequestDraftLabel()
                }

                Label(
                    "\(mergeRequest.userNotesCount) comments",
                    systemImage: "bubble.left"
                )
                .foregroundStyle(.secondary)
            }
            .font(.subheadline.weight(.medium))
        }
    }

    private var descriptionSection: some View {
        GitLabDetailSection(title: "Description") {
            if
                let request =
                    GitLabDescriptionMarkdownRequest
                    .mergeRequest(
                        accountID: accountID,
                        mergeRequest:
                            mergeRequest
                    )
            {
                GitLabMarkdownContentView(
                    request: request,
                    revision: mergeRequest.updatedAt,
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

    private var branchesSection: some View {
        GitLabDetailSection(title: "Branches") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(
                    "Source",
                    value: mergeRequest.sourceBranch
                )
                LabeledContent(
                    "Target",
                    value: mergeRequest.targetBranch
                )
            }
            .textSelection(.enabled)
        }
    }

    private var bottomControls: some View {
        HStack {
            if
                let headSHA =
                    mergeRequest
                        .diffHeadSHA
            {
                GitLabMergeRequestDiffSummaryLink(
                    mergeRequest:
                        mergeRequest,
                    headSHA: headSHA,
                    loader:
                        diffSummaryLoader,
                    diffLoader:
                        diffLoader,
                    discussionModel:
                        discussionModel,
                    resolutionModel:
                        resolutionModel,
                    apiAccess: apiAccess,
                    discussionMutator:
                        discussionMutator,
                    reactionService:
                        reactionService,
                    accountID: accountID,
                    appSession: appSession
                )
                .id(headSHA)
            } else {
                Label(
                    "Preparing diff",
                    systemImage:
                        "hourglass"
                )
                .font(
                    .caption
                        .weight(.medium)
                )
                .foregroundStyle(
                    .secondary
                )
                .accessibilityIdentifier(
                    "mergeRequests.changes.preparing"
                )
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var labelsSection: some View {
        GitLabDetailSection(title: "Labels") {
            ScrollView(
                .horizontal,
                showsIndicators: false
            ) {
                HStack(spacing: 8) {
                    ForEach(
                        mergeRequest.labels,
                        id: \.self
                    ) {
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
                    user: mergeRequest.author,
                    role: "Author"
                )

                if mergeRequest.assignees.isEmpty {
                    LabeledContent(
                        "Assignees",
                        value: "Unassigned"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(mergeRequest.assignees) {
                        GitLabAPIUserRow(
                            user: $0,
                            role: "Assignee"
                        )
                    }
                }

                if mergeRequest.reviewers.isEmpty {
                    LabeledContent(
                        "Reviewers",
                        value: "No reviewers"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(mergeRequest.reviewers) {
                        GitLabAPIUserRow(
                            user: $0,
                            role: "Reviewer"
                        )
                    }
                }
            }
        }
    }

    private var timestampsSection: some View {
        GitLabDetailSection(title: "Activity") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent(
                    "Created",
                    value: mergeRequest.createdAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                LabeledContent(
                    "Updated",
                    value: mergeRequest.updatedAt.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
                )
                if let closedAt = mergeRequest.closedAt {
                    LabeledContent(
                        "Closed",
                        value: closedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
                if let mergedAt = mergeRequest.mergedAt {
                    LabeledContent(
                        "Merged",
                        value: mergedAt.formatted(
                            date: .abbreviated,
                            time: .shortened
                        )
                    )
                }
            }
        }
    }
}

private struct
    GitLabMergeRequestDiffSummaryLink:
    View
{
    let mergeRequest: GitLabMergeRequest
    let headSHA: String
    let diffLoader:
        any GitLabMergeRequestDiffLoading
    let discussionModel:
        GitLabDiscussionsModel
    let resolutionModel:
        GitLabDiscussionResolutionModel
    let apiAccess: GitLabAPIAccess
    let discussionMutator:
        any GitLabDiscussionMutating
    let reactionService:
        any GitLabEmojiReactionLoading
            & GitLabEmojiReactionMutating
    let accountID: GitLabAccountID
    let appSession: AppSession

    @State private var model:
        GitLabMergeRequestDiffSummaryModel

    init(
        mergeRequest: GitLabMergeRequest,
        headSHA: String,
        loader:
            any GitLabMergeRequestDiffSummaryLoading,
        diffLoader:
            any GitLabMergeRequestDiffLoading,
        discussionModel:
            GitLabDiscussionsModel,
        resolutionModel:
            GitLabDiscussionResolutionModel,
        apiAccess: GitLabAPIAccess,
        discussionMutator:
            any GitLabDiscussionMutating,
        reactionService:
            any GitLabEmojiReactionLoading
                & GitLabEmojiReactionMutating,
        accountID: GitLabAccountID,
        appSession: AppSession
    ) {
        self.mergeRequest = mergeRequest
        self.headSHA = headSHA
        self.diffLoader = diffLoader
        self.discussionModel =
            discussionModel
        self.resolutionModel =
            resolutionModel
        self.apiAccess = apiAccess
        self.discussionMutator =
            discussionMutator
        self.reactionService =
            reactionService
        self.accountID = accountID
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabMergeRequestDiffSummaryModel(
                    mergeRequestID:
                        mergeRequest.id,
                    loader: loader
                )
        )
    }

    var body: some View {
        NavigationLink {
            GitLabMergeRequestDiffListView(
                route: mergeRequest.route,
                headSHA: headSHA,
                changesURL:
                    mergeRequest
                        .safeChangesURL,
                diffVersion:
                    mergeRequest
                        .diffRefs?
                        .identity,
                loader: diffLoader,
                discussionModel:
                    discussionModel,
                resolutionModel:
                    resolutionModel,
                apiAccess: apiAccess,
                discussionMutator:
                    discussionMutator,
                reactionService:
                    reactionService,
                accountID: accountID,
                appSession: appSession
            )
        } label: {
            ViewThatFits(
                in: .horizontal
            ) {
                summaryLabel(
                    includesLineCounts:
                        true
                )
                summaryLabel(
                    includesLineCounts:
                        false
                )
            }
        }
        .buttonStyle(.glass)
        .controlSize(.regular)
        .accessibilityLabel(
            presentation
                .accessibilityLabel
        )
        .accessibilityHint(
            "Opens changed files."
        )
        .accessibilityIdentifier(
            "mergeRequests.changes"
        )
        .task(id: headSHA) {
            await model.loadIfNeeded()
        }
        .onChange(
            of:
                model
                    .authenticationFailure
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
    }

    private var presentation:
        GitLabMergeRequestDiffSummaryPresentation
    {
        GitLabMergeRequestDiffSummaryPresentation(
            state: model.state,
            restChangesCount:
                mergeRequest.changesCount
        )
    }

    private func summaryLabel(
        includesLineCounts: Bool
    ) -> some View {
        HStack(spacing: 7) {
            if presentation.isLoading {
                ProgressView()
                    .controlSize(.mini)
                    .accessibilityHidden(true)
            } else {
                Image(
                    systemName:
                        "doc.on.doc"
                )
                .font(.caption)
                .accessibilityHidden(true)
            }

            Text(presentation.fileText)
                .foregroundStyle(.primary)

            if
                includesLineCounts,
                let additions =
                    presentation
                        .additionsText,
                let deletions =
                    presentation
                        .deletionsText
            {
                Text(additions)
                    .foregroundStyle(.green)
                Text(deletions)
                    .foregroundStyle(.red)
            }
        }
        .font(
            .subheadline
                .weight(.semibold)
                .monospacedDigit()
        )
        .lineLimit(1)
    }
}
