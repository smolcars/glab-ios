import SwiftUI

struct MergeRequestsView: View {
    let mode: GitLabMergeRequestListMode
    let model: MergeRequestsModel
    let loader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    let approvalService:
        any GitLabMergeRequestApprovalServing
    let mergeService:
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
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    init(
        mode: GitLabMergeRequestListMode,
        model: MergeRequestsModel,
        loader:
            any GitLabMergeRequestLoading
                & GitLabMergeRequestApprovalLoading
                & GitLabMergeRequestDiffLoading
                & GitLabMergeRequestDiffSummaryLoading,
        approvalService:
            any GitLabMergeRequestApprovalServing,
        mergeService:
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
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.mode = mode
        self.model = model
        self.loader = loader
        self.approvalService =
            approvalService
        self.mergeService =
            mergeService
        self.pipelineLoader =
            pipelineLoader
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
    }

    var body: some View {
        GitLabMergeRequestListView(
            model: model,
            configuration:
                GitLabMergeRequestListConfiguration(
                    title: mode.title,
                    loadingMessage:
                        "Loading \(mode.title.lowercased())",
                    emptyTitle:
                        mode.emptyTitle,
                    emptyMessage:
                        mode.emptyMessage,
                    emptySystemImage:
                        mode.emptySystemImage,
                    accessibilityIdentifier:
                        "mergeRequests.\(mode.rawValue).list"
                ),
            loader: loader,
            approvalService:
                approvalService,
            mergeService:
                mergeService,
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
    }
}

struct GitLabMergeRequestListConfiguration {
    let title: String
    let loadingMessage: String
    let emptyTitle: String
    let emptyMessage: String
    let emptySystemImage: String
    let accessibilityIdentifier: String
}

struct GitLabMergeRequestListView: View {
    let model:
        GitLabPaginatedResourceModel<
            GitLabMergeRequest,
            GitLabMergeRequestRoute
        >
    let configuration:
        GitLabMergeRequestListConfiguration
    let loader:
        any GitLabMergeRequestLoading
            & GitLabMergeRequestApprovalLoading
            & GitLabMergeRequestDiffLoading
            & GitLabMergeRequestDiffSummaryLoading
    let approvalService:
        any GitLabMergeRequestApprovalServing
    let mergeService:
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
    let accountID: GitLabAccountID
    let appSession: AppSession
    let onResourceEdited:
        (GitLabResourceEditResult) -> Void

    init(
        model:
            GitLabPaginatedResourceModel<
                GitLabMergeRequest,
                GitLabMergeRequestRoute
            >,
        configuration:
            GitLabMergeRequestListConfiguration,
        loader:
            any GitLabMergeRequestLoading
                & GitLabMergeRequestApprovalLoading
                & GitLabMergeRequestDiffLoading
                & GitLabMergeRequestDiffSummaryLoading,
        approvalService:
            any GitLabMergeRequestApprovalServing,
        mergeService:
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
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.model = model
        self.configuration = configuration
        self.loader = loader
        self.approvalService =
            approvalService
        self.mergeService =
            mergeService
        self.pipelineLoader =
            pipelineLoader
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
    }

    var body: some View {
        @Bindable var model = model

        content
            .background(
                Color(uiColor: .systemGroupedBackground)
            )
            .navigationTitle(
                configuration.title
            )
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(
                edge: .top,
                spacing: 0
            ) {
                GitLabSearchField(
                    text: $model.searchText,
                    prompt:
                        "Search loaded merge requests",
                    accessibilityIdentifier:
                        "mergeRequests.search"
                )
            }
            .ignoresSafeArea(
                .keyboard,
                edges: .bottom
            )
            .refreshable {
                await refresh()
            }
            .task(
                id: ObjectIdentifier(model)
            ) {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
    }

    @ViewBuilder
    private var content: some View {
        if model.isLoadingInitial {
            ScrollView {
                GitLabLoadingStateView(
                    message:
                        configuration
                        .loadingMessage
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
                    title:
                        configuration
                        .emptyTitle,
                    message:
                        configuration
                        .emptyMessage,
                    systemImage:
                        configuration
                        .emptySystemImage
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
                    NavigationLink {
                        mergeRequestDetail(
                            route:
                                mergeRequest.route
                        )
                    } label: {
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
            configuration
                .accessibilityIdentifier
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

    private func mergeRequestDetail(
        route: GitLabMergeRequestRoute
    ) -> some View {
        GitLabMergeRequestDetailView(
            route: route,
            loader: loader,
            approvalService:
                approvalService,
            mergeService:
                mergeService,
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
            .font(
                .callout.weight(
                    .semibold
                )
            )
            .frame(width: 20)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }

    private var systemImage: String {
        switch mergeRequest.stateKind {
        case .opened:
            "arrow.triangle.pull"
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
            .blue
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
    let route: GitLabMergeRequestRoute
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
    let pipelineLoader:
        any GitLabPipelineLoading

    @State private var model:
        GitLabMergeRequestDetailModel
    @State private var approvalModel:
        GitLabMergeRequestApprovalModel
    @State private var mergeModel:
        GitLabMergeRequestMergeModel
    @State private var
        approvalManagementModel:
        GitLabMergeRequestApprovalManagementModel
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
    @State private var showsPipelines = false
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
        approvalService:
            any GitLabMergeRequestApprovalServing,
        mergeService:
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
        accountID: GitLabAccountID,
        appSession: AppSession,
        onResourceEdited:
            @escaping (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.route = route
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
        self.pipelineLoader =
            pipelineLoader
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
        let approvalModel =
            GitLabMergeRequestApprovalModel(
                route: route,
                loader: loader
            )
        _approvalModel = State(
            initialValue: approvalModel
        )
        _mergeModel = State(
            initialValue:
                GitLabMergeRequestMergeModel(
                    accountID: accountID,
                    route: route,
                    apiAccess: apiAccess,
                    service: mergeService,
                    currentMergeRequest: {
                        guard
                            case let .loaded(
                                mergeRequest
                            ) = detailModel.state
                        else {
                            return nil
                        }
                        return mergeRequest
                    },
                    currentApprovalSummary: {
                        guard
                            case let .loaded(
                                availability
                            ) = approvalModel.state,
                            case let .available(
                                summary
                            ) = availability
                        else {
                            return nil
                        }
                        return summary
                    },
                    isAccountCurrent: {
                        appSession
                            .activeAccountID
                            == accountID
                    },
                    onMergeRequestReconciled: {
                        _ =
                            detailModel
                            .reconcileAuthoritative(
                                $0
                            )
                    },
                    onApprovalSummaryReconciled: {
                        _ =
                            approvalModel
                            .reconcileAuthoritative(
                                .available($0)
                            )
                    },
                    onResourceEdited: {
                        onResourceEdited($0)
                    }
                )
        )
        _approvalManagementModel = State(
            initialValue:
                GitLabMergeRequestApprovalManagementModel(
                    route: route,
                    accountID: accountID,
                    apiAccess: apiAccess,
                    service:
                        approvalService,
                    currentMergeRequest: {
                        guard
                            case let .loaded(
                                mergeRequest
                            ) =
                                detailModel.state
                        else {
                            return nil
                        }
                        return mergeRequest
                    },
                    currentApprovalSummary: {
                        guard
                            case let .loaded(
                                availability
                            ) =
                                approvalModel.state,
                            case let .available(
                                summary
                            ) =
                                availability
                        else {
                            return nil
                        }
                        return summary
                    },
                    isAccountCurrent: {
                        appSession
                            .activeAccountID
                            == accountID
                    },
                    onMergeRequestReconciled: {
                        _ =
                            detailModel
                            .reconcileAuthoritative(
                                $0
                            )
                    },
                    onApprovalSummaryReconciled: {
                        _ =
                            approvalModel
                            .reconcileAuthoritative(
                                .available($0)
                            )
                    }
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
            .navigationDestination(
                isPresented: $showsPipelines
            ) {
                GitLabMergeRequestPipelinesView(
                    route: route,
                    loader: pipelineLoader,
                    accountID: accountID,
                    appSession: appSession,
                    apiAccess: apiAccess,
                    isAccountCurrent: {
                        appSession
                            .activeAccountID
                            == accountID
                    },
                    isMergeRequestOpen: {
                        guard
                            case let .loaded(
                                mergeRequest
                            ) = model.state
                        else {
                            return false
                        }
                        return mergeRequest
                            .stateKind
                            == .opened
                    }
                )
            }
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
                resolutionModel.cancelAll()
                mergeModel.cancel()
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
            .gitLabMergeRequestMergeAlerts(
                model: mergeModel
            )
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
                    approvalManagementModel:
                        approvalManagementModel,
                    mergeModel: mergeModel,
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
                    openPipelines: {
                        showsPipelines = true
                    },
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
            ?? approvalManagementModel
                .authenticationFailure
            ?? mergeModel
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
    }

    private func requestStateChange(
        _ event: GitLabResourceStateEvent
    ) {
        guard
            apiAccess.canWrite,
            !taskToggleModel.isBusy,
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
            case let .loaded(mergeRequest) =
                model.state
        else {
            return
        }
        pendingStateEvent = nil
        let metadataEditorModel =
            makeMetadataEditor(
                for:
                    .mergeRequest(
                        mergeRequest
                    )
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
            ? "This will close the merge request on GitLab and may remove it from assigned or review-requested work."
            : "This will reopen the merge request on GitLab and may return it to assigned or review-requested work."
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
        async let approvalDetails: Void =
            approvalManagementModel
            .loadDetailsIfNeeded()
        async let discussion: Void =
            discussionModel.loadIfNeeded()
        _ = await (
            detail,
            approval,
            approvalDetails,
            discussion
        )
    }

    private func refresh() async {
        async let detail: Void = model.retry()
        async let approval: Void =
            approvalModel.retry()
        async let approvalDetails: Void =
            approvalManagementModel
            .refreshDetails()
        async let discussion: Void =
            discussionModel.refresh()
        _ = await (
            detail,
            approval,
            approvalDetails,
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
    let approvalManagementModel:
        GitLabMergeRequestApprovalManagementModel
    let mergeModel:
        GitLabMergeRequestMergeModel
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
    let openPipelines: () -> Void
    let launchComposer:
        (GitLabDiscussionComposerTarget) -> Void
    let appSession: AppSession
    let taskInteraction:
        GitLabMarkdownTaskInteraction

    @Environment(\.gitLabMarkdownRenderer)
    private var markdownRenderer
    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

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
                    mergeModel: mergeModel,
                    retryApproval:
                        retryApproval,
                    openPipelines:
                        openPipelines
                )

                GitLabMergeRequestApprovalManagementView(
                    approvalState:
                        approvalState,
                    model:
                        approvalManagementModel,
                    accountID: accountID
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

                if !mergeRequest.labels.isEmpty {
                    labelsSection
                }

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

            compactMetadata
        }
    }

    private var compactMetadata: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(
                mergeRequest.targetBranch
                    + " ← "
                    + mergeRequest.sourceBranch
            )
            .font(.caption.weight(.medium))
            .fontDesign(.monospaced)
            .foregroundStyle(.secondary)
            .lineLimit(
                dynamicTypeSize.isAccessibilitySize
                    ? nil
                    : 2
            )
            .textSelection(.enabled)
            .accessibilityLabel(
                "Merge \(mergeRequest.sourceBranch) into \(mergeRequest.targetBranch)"
            )

            peopleSummary

            Text(timestampSummary)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel(
                    timestampAccessibilityLabel
                )
        }
    }

    private var peopleSummary: some View {
        let otherAssignees =
            mergeRequest.assignees.filter {
                $0.id
                    != mergeRequest.author.id
            }
        let authorIsAssignee =
            otherAssignees.count
            != mergeRequest.assignees.count

        return VStack(alignment: .leading, spacing: 7) {
            GitLabMergeRequestCompactPeople(
                role:
                    authorIsAssignee
                    ? "Author & assignee"
                    : "Author",
                users: [mergeRequest.author]
            )

            if
                !authorIsAssignee
                    || !otherAssignees.isEmpty
            {
                GitLabMergeRequestCompactPeople(
                    role:
                        authorIsAssignee
                        ? "Also assigned"
                        : otherAssignees.count == 1
                        ? "Assignee"
                        : "Assignees",
                    users: otherAssignees
                )
            }
        }
    }

    private var timestampSummary: String {
        timestampValues
            .map {
                $0.label
                    + " "
                    + GitLabRelativeTimeFormatter
                    .string(from: $0.date)
            }
            .joined(separator: " · ")
    }

    private var timestampAccessibilityLabel: String {
        timestampValues
            .map {
                $0.label
                    + " "
                    + $0.date.formatted(
                        date: .abbreviated,
                        time: .shortened
                    )
            }
            .joined(separator: ", ")
    }

    private var timestampValues:
        [(label: String, date: Date)]
    {
        var values = [
            (
                label: "Created",
                date: mergeRequest.createdAt
            ),
            (
                label: "Updated",
                date: mergeRequest.updatedAt
            ),
        ]

        if let mergedAt = mergeRequest.mergedAt {
            values.append(
                (
                    label: "Merged",
                    date: mergedAt
                )
            )
        } else if let closedAt = mergeRequest.closedAt {
            values.append(
                (
                    label: "Closed",
                    date: closedAt
                )
            )
        }

        return values
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

    private var bottomControls: some View {
        HStack {
            Spacer(minLength: 0)

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
}

private struct GitLabMergeRequestCompactPeople: View {
    let role: String
    let users: [GitLabAPIUser]

    @Environment(\.dynamicTypeSize)
    private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 7) {
            avatar

            VStack(alignment: .leading, spacing: 1) {
                Text(role)
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(displaySummary)
                    .font(.caption.weight(.semibold))
                    .lineLimit(
                        dynamicTypeSize.isAccessibilitySize
                            ? nil
                            : 1
                    )
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    @ViewBuilder
    private var avatar: some View {
        if let user = users.first {
            GitLabUserAvatar(
                user: user.summary,
                size: 26
            )
        } else {
            Image(
                systemName:
                    "person.crop.circle.badge.questionmark"
            )
            .font(.title3)
            .foregroundStyle(.secondary)
            .frame(width: 26, height: 26)
        }
    }

    private var displaySummary: String {
        guard let first = users.first else {
            return "Unassigned"
        }
        guard users.count > 1 else {
            return first.displayName
        }
        return first.displayName
            + " +\(users.count - 1)"
    }

    private var accessibilitySummary: String {
        guard !users.isEmpty else {
            return "\(role), unassigned"
        }
        return role
            + ", "
            + users.map {
                "\($0.displayName), @\($0.username)"
            }
            .joined(separator: ", ")
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
