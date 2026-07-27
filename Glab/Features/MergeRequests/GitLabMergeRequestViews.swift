import SwiftUI

struct MergeRequestsView: View {
    let mode: GitLabMergeRequestListMode
    let loader: any GitLabMergeRequestLoading
    let appSession: AppSession

    @State private var model: MergeRequestsModel

    init(
        mode: GitLabMergeRequestListMode,
        loader: any GitLabMergeRequestLoading,
        appSession: AppSession
    ) {
        self.mode = mode
        self.loader = loader
        self.appSession = appSession
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
                    appSession: appSession
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
                    message: error.description
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
                    message: error.description,
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
            } else if model.didFailNextPage {
                Button {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                } label: {
                    Label(
                        "Try loading more merge requests again",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
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
        await appSession.handleAuthenticationFailure(error)
    }
}

private struct GitLabMergeRequestRow: View {
    let mergeRequest: GitLabMergeRequest

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(mergeRequest.references.full)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

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

            Text(mergeRequest.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !mergeRequest.labels.isEmpty {
                HStack(spacing: 6) {
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
            }

            Label(
                mergeRequest.sourceBranch
                    + " → "
                    + mergeRequest.targetBranch,
                systemImage: "arrow.triangle.branch"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: 12) {
                GitLabMergeRequestStateLabel(
                    mergeRequest: mergeRequest
                )

                if mergeRequest.isDraft {
                    GitLabMergeRequestDraftLabel()
                }

                Spacer(minLength: 4)

                Label(
                    "\(mergeRequest.userNotesCount)",
                    systemImage: "bubble.left"
                )
                .foregroundStyle(.secondary)
            }
            .font(.caption)

            HStack(spacing: 6) {
                Label(
                    mergeRequest.author.displayName,
                    systemImage: "person.crop.circle"
                )
                .lineLimit(1)

                if let peopleSummary {
                    Text("•")
                    Text(peopleSummary)
                        .lineLimit(1)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
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

private struct GitLabMergeRequestStateLabel: View {
    let mergeRequest: GitLabMergeRequest

    var body: some View {
        Label(
            mergeRequest.stateTitle,
            systemImage: systemImage
        )
        .foregroundStyle(color)
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

private struct GitLabMergeRequestDraftLabel: View {
    var body: some View {
        Label(
            "Draft",
            systemImage: "pencil.line"
        )
        .foregroundStyle(.orange)
    }
}

struct GitLabMergeRequestDetailView: View {
    let appSession: AppSession

    @State private var model:
        GitLabMergeRequestDetailModel

    init(
        route: GitLabMergeRequestRoute,
        loader: any GitLabMergeRequestLoading,
        appSession: AppSession
    ) {
        self.appSession = appSession
        _model = State(
            initialValue:
                GitLabMergeRequestDetailModel(
                    route: route,
                    loader: loader
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
            .task {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
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
                message: error.description
            ) {
                Task {
                    await model.retry()
                    await handleAuthenticationFailure()
                }
            }
        case let .loaded(mergeRequest):
            GitLabMergeRequestDetailContent(
                mergeRequest: mergeRequest
            )
        }
    }

    private func handleAuthenticationFailure() async {
        guard
            let error = model.authenticationFailure
        else {
            return
        }
        await appSession.handleAuthenticationFailure(error)
    }
}

private struct GitLabMergeRequestDetailContent: View {
    let mergeRequest: GitLabMergeRequest

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                descriptionSection
                branchesSection

                if !mergeRequest.labels.isEmpty {
                    labelsSection
                }

                peopleSection
                timestampsSection
            }
            .padding(20)
            .padding(
                .bottom,
                mergeRequest.safeWebURL == nil ? 0 : 76
            )
        }
        .accessibilityIdentifier(
            "mergeRequests.detail.scroll"
        )
        .safeAreaInset(edge: .bottom) {
            if let webURL = mergeRequest.safeWebURL {
                GitLabOpenInGitLabLink(
                    destination: webURL,
                    accessibilityIdentifier:
                        "mergeRequests.openInGitLab"
                )
            }
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
                let description = mergeRequest.description?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
                !description.isEmpty
            {
                Text(
                    GitLabDescriptionFormatter
                        .attributedString(description)
                )
                .font(.body)
                .textSelection(.enabled)
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
