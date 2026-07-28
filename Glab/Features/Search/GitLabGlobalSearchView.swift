import SwiftUI

struct GitLabGlobalSearchView: View {
    let model: GitLabGlobalSearchModel
    let accountID: GitLabAccountID
    let appSession: AppSession

    @FocusState private var searchIsFocused:
        Bool

    var body: some View {
        @Bindable var model = model

        List {
            if model.normalizedQuery.isEmpty {
                searchPrompt
                recentQueries
            } else {
                if model.allScopesFailed {
                    globalRetry
                }

                if model.hasPartialResults {
                    partialResultsNotice
                }

                ForEach(
                    GitLabSearchScope.allCases,
                    id: \.self
                ) { scope in
                    searchSection(scope)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $model.query,
            placement:
                .navigationBarDrawer(
                    displayMode: .always
                ),
            prompt:
                "Projects, issues, merge requests"
        )
        .searchFocused($searchIsFocused)
        .task {
            searchIsFocused = true
        }
        .task(id: model.query) {
            await model.search(model.query)
            await handleAuthenticationFailure()
        }
        .refreshable {
            guard
                !model.normalizedQuery.isEmpty
            else {
                return
            }
            await model.refresh()
            await handleAuthenticationFailure()
        }
        .background(
            Color(uiColor: .systemGroupedBackground)
        )
        .accessibilityIdentifier(
            "search.screen"
        )
    }

    private var globalRetry: some View {
        Button {
            Task {
                await model.refresh()
                await
                    handleAuthenticationFailure()
            }
        } label: {
            Label {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        "Couldn’t search GitLab"
                    )
                    .font(
                        .callout.weight(
                            .semibold
                        )
                    )
                    Text(
                        "Try all three categories again."
                    )
                    .font(.caption)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            } icon: {
                Image(
                    systemName:
                        "arrow.clockwise"
                )
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.red)
        .listRowBackground(
            Color.red.opacity(0.1)
        )
        .accessibilityHint(
            "Retries projects, issues, and merge requests."
        )
        .accessibilityIdentifier(
            "search.retry.all"
        )
    }

    private var searchPrompt: some View {
        ContentUnavailableView {
            Label(
                "Search GitLab",
                systemImage: "magnifyingglass"
            )
        } description: {
            Text(
                "Find projects, issues, and merge "
                    + "requests on this account."
            )
        }
        .listRowBackground(Color.clear)
        .accessibilityIdentifier(
            "search.emptyPrompt"
        )
    }

    @ViewBuilder
    private var recentQueries: some View {
        if !model.recentQueries.isEmpty {
            Section("Recent Searches") {
                ForEach(
                    model.recentQueries,
                    id: \.self
                ) { query in
                    Button {
                        model.useRecentQuery(
                            query
                        )
                    } label: {
                        Label(
                            query,
                            systemImage: "clock"
                        )
                        .frame(
                            maxWidth: .infinity,
                            alignment: .leading
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier(
                        "search.recent."
                            + accessibilityToken(
                                query
                            )
                    )
                }
            }
        }
    }

    private var partialResultsNotice:
        some View
    {
        Label {
            Text(
                "Some GitLab search categories "
                    + "couldn’t be loaded."
            )
        } icon: {
            Image(
                systemName:
                    "exclamationmark.triangle.fill"
            )
        }
        .font(.callout)
        .foregroundStyle(.orange)
        .listRowBackground(
            Color.orange.opacity(0.1)
        )
        .accessibilityIdentifier(
            "search.partialResults"
        )
    }

    private func searchSection(
        _ scope: GitLabSearchScope
    ) -> some View {
        let state = model.state(for: scope)

        return Section {
            scopeContent(
                scope,
                state: state
            )
        } header: {
            HStack {
                Label(
                    scope.title,
                    systemImage:
                        scope.systemImage
                )

                Spacer()

                if
                    let count =
                        state.totalCount,
                    state.status == .loaded
                {
                    Text(
                        count.formatted()
                    )
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                }
            }
            .textCase(nil)
            .accessibilityIdentifier(
                "search.section.\(scope.rawValue)"
            )
        }
    }

    @ViewBuilder
    private func scopeContent(
        _ scope: GitLabSearchScope,
        state: GitLabSearchScopeState
    ) -> some View {
        switch state.status {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text(
                    "Searching "
                        + scope.title
                            .lowercased()
                        + "…"
                )
                .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier(
                "search.loading.\(scope.rawValue)"
            )
        case .loaded:
            if state.results.isEmpty {
                Text(
                    scope.emptyMessage
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(
                    "search.empty.\(scope.rawValue)"
                )
            } else {
                ForEach(
                    Array(
                        state.results.enumerated()
                    ),
                    id: \.element.resourceID
                ) { index, result in
                    NavigationLink(
                        value: result.nativeRoute
                    ) {
                        GitLabSearchResultRow(
                            result: result
                        )
                    }
                    .accessibilityIdentifier(
                        "search.result."
                            + "\(scope.rawValue).\(index)"
                    )
                }
            }

            paginationControl(
                scope,
                state: state
            )
        case let .unavailable(error):
            Label {
                VStack(
                    alignment: .leading,
                    spacing: 3
                ) {
                    Text(
                        scope.title
                            + " aren’t available"
                    )
                    .font(
                        .callout.weight(
                            .semibold
                        )
                    )
                    Text(
                        GitLabRecoveryPresentation(
                            error: error
                        ).message
                    )
                    .font(.caption)
                }
            } icon: {
                Image(
                    systemName:
                        "lock.trianglebadge.exclamationmark"
                )
            }
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                "search.unavailable."
                    + scope.rawValue
            )
        case let .failed(error):
            GitLabInlineRetryRow(
                title:
                    "Couldn’t search "
                    + scope.title.lowercased(),
                error: error,
                accessibilityIdentifier:
                    "search.retry."
                    + scope.rawValue
            ) {
                Task {
                    await model.retry(scope)
                    await
                        handleAuthenticationFailure()
                }
            }
        }
    }

    @ViewBuilder
    private func paginationControl(
        _ scope: GitLabSearchScope,
        state: GitLabSearchScopeState
    ) -> some View {
        if state.isLoadingNextPage {
            HStack {
                Spacer()
                ProgressView("Loading more…")
                    .font(.footnote)
                Spacer()
            }
            .accessibilityIdentifier(
                "search.loadMore.loading."
                    + scope.rawValue
            )
        } else if
            let error = state.nextPageError
        {
            GitLabInlineRetryRow(
                title: "Couldn’t load more",
                error: error,
                accessibilityIdentifier:
                    "search.loadMore.retry."
                    + scope.rawValue
            ) {
                loadMore(scope)
            }
        } else if state.nextPageURL != nil {
            Button {
                loadMore(scope)
            } label: {
                Label(
                    "Load more",
                    systemImage:
                        "arrow.down.circle"
                )
                .frame(
                    maxWidth: .infinity,
                    alignment: .center
                )
            }
            .accessibilityIdentifier(
                "search.loadMore."
                    + scope.rawValue
            )
        }
    }

    private func loadMore(
        _ scope: GitLabSearchScope
    ) {
        Task {
            await model.loadNextPage(
                for: scope
            )
            await handleAuthenticationFailure()
        }
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

    private func accessibilityToken(
        _ value: String
    ) -> String {
        value.lowercased()
            .map {
                $0.isLetter || $0.isNumber
                    ? String($0)
                    : "-"
            }
            .joined()
    }
}

private struct GitLabSearchResultRow: View {
    let result: GitLabSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(
                systemName: result.systemImage
            )
            .font(.body.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(width: 34, height: 34)
            .background(
                Color.orange.opacity(0.12),
                in: .rect(cornerRadius: 9)
            )
            .accessibilityHidden(true)

            VStack(
                alignment: .leading,
                spacing: 4
            ) {
                Text(result.title)
                    .font(
                        .body.weight(.semibold)
                    )
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(result.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if
                    let description =
                        result.summaryPreview
                {
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(
            children: .ignore
        )
        .accessibilityLabel(
            result.title
                + ", "
                + result.subtitle
        )
        .accessibilityHint(
            "Opens the native GitLab detail"
        )
    }
}

private extension GitLabSearchScope {
    var title: String {
        switch self {
        case .projects:
            "Projects"
        case .issues:
            "Issues"
        case .mergeRequests:
            "Merge Requests"
        }
    }

    var systemImage: String {
        switch self {
        case .projects:
            "shippingbox"
        case .issues:
            "smallcircle.filled.circle"
        case .mergeRequests:
            "arrow.triangle.branch"
        }
    }

    var emptyMessage: String {
        "GitLab returned no matching "
            + title.lowercased()
            + "."
    }
}

private extension GitLabSearchResult {
    var systemImage: String {
        switch self {
        case .project:
            "shippingbox.fill"
        case .issue:
            "smallcircle.filled.circle"
        case .mergeRequest:
            "arrow.triangle.branch"
        }
    }

    var title: String {
        switch self {
        case let .project(project):
            project.nameWithNamespace
                ?? project.name
        case let .issue(issue):
            issue.title
        case let .mergeRequest(
            mergeRequest
        ):
            mergeRequest.title
        }
    }

    var subtitle: String {
        switch self {
        case let .project(project):
            project.pathWithNamespace
        case let .issue(issue):
            [
                "#\(issue.iid)",
                issue.state.capitalized,
                issue.author.map {
                    "@\($0.username)"
                },
            ]
            .compactMap(\.self)
            .joined(separator: "  •  ")
        case let .mergeRequest(
            mergeRequest
        ):
            [
                "!\(mergeRequest.iid)",
                mergeRequest.isDraft
                    ? "Draft"
                    : mergeRequest.state
                        .capitalized,
                mergeRequest.author.map {
                    "@\($0.username)"
                },
            ]
            .compactMap(\.self)
            .joined(separator: "  •  ")
        }
    }

}
