import SwiftUI

struct AssignedIssuesView: View {
    let model: AssignedIssuesModel
    let loader: any GitLabIssueLoading
    let appSession: AppSession

    var body: some View {
        @Bindable var model = model

        content
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Assigned Issues")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $model.searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search loaded issues"
            )
            .navigationDestination(for: GitLabIssueRoute.self) {
                GitLabIssueDetailView(
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
        await appSession.handleAuthenticationFailure(error)
    }
}

private struct GitLabIssueRow: View {
    let issue: GitLabIssue

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(issue.references.full)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if issue.confidential {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Confidential")
                }

                Spacer(minLength: 8)

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

            Text(issue.title)
                .font(.body.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)

            if !issue.labels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(issue.labels.prefix(3), id: \.self) {
                        GitLabLabelPill(name: $0)
                    }

                    if issue.labels.count > 3 {
                        Text("+\(issue.labels.count - 3)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                GitLabIssueStateLabel(issue: issue)

                if !issue.assignees.isEmpty {
                    Label(
                        issue.assignees
                            .map(\.displayName)
                            .joined(separator: ", "),
                        systemImage: "person.fill"
                    )
                    .lineLimit(1)
                }

                Spacer(minLength: 4)

                Label(
                    "\(issue.userNotesCount)",
                    systemImage: "bubble.left"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
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
    let appSession: AppSession

    @State private var model: GitLabIssueDetailModel

    init(
        route: GitLabIssueRoute,
        loader: any GitLabIssueLoading,
        appSession: AppSession
    ) {
        self.appSession = appSession
        _model = State(
            initialValue: GitLabIssueDetailModel(
                route: route,
                loader: loader
            )
        )
    }

    var body: some View {
        content
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Issue")
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
                    message: "Loading issue"
                )
                .padding(20)
            }
        case let .failed(error):
            GitLabRetryStateView(error: error) {
                Task {
                    await model.retry()
                    await handleAuthenticationFailure()
                }
            }
        case let .loaded(issue):
            GitLabIssueDetailContent(issue: issue)
        }
    }

    private func handleAuthenticationFailure() async {
        guard let error = model.authenticationFailure else {
            return
        }
        await appSession.handleAuthenticationFailure(error)
    }
}

private struct GitLabIssueDetailContent: View {
    let issue: GitLabIssue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

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
            }
            .padding(20)
            .padding(.bottom, issue.safeWebURL == nil ? 0 : 76)
        }
        .accessibilityIdentifier("issues.detail.scroll")
        .safeAreaInset(edge: .bottom) {
            if let webURL = issue.safeWebURL {
                GitLabOpenInGitLabLink(
                    destination: webURL,
                    accessibilityIdentifier:
                        "issues.openInGitLab"
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(issue.references.full)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            Text(issue.title)
                .font(.title2.bold())
                .textSelection(.enabled)

            HStack(spacing: 12) {
                GitLabIssueStateLabel(issue: issue)

                Label(
                    "\(issue.userNotesCount) comments",
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
                let description = issue.description?
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
