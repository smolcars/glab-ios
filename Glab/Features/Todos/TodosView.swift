import SwiftUI

struct TodosView: View {
    let model: TodosModel
    let issueLoader: any GitLabIssueLoading
    let mergeRequestLoader:
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isConfirmingMarkAllDone =
        false

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            List {
                filterControls(model: $model)
                    .listRowInsets(
                        EdgeInsets(
                            top: 4,
                            leading: 16,
                            bottom: 12,
                            trailing: 16
                        )
                    )
                    .listRowSeparator(
                        .visible,
                        edges: .bottom
                    )

                if
                    model.selectedState == .pending,
                    !model.canComplete
                {
                    readOnlyCompletionRow
                }

                if let failure = model.mutationFailure {
                    mutationFailureRow(failure)
                }

                if
                    isCompleting,
                    !model.todos.isEmpty
                {
                    completionProgressRow
                }

                resourceRows
            }
            .id(model.query)
            .listStyle(.plain)
            .accessibilityIdentifier("todos.list")
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Todos")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if model.selectedState == .pending {
                    ToolbarItem(
                        placement: .topBarTrailing
                    ) {
                        Button(
                            "Mark All",
                            systemImage:
                                "checkmark.circle"
                        ) {
                            isConfirmingMarkAllDone =
                                true
                        }
                        .disabled(
                            !model.canMarkAllDone
                        )
                        .accessibilityIdentifier(
                            "todos.markAllButton"
                        )
                        .accessibilityHint(
                            completionAccessibilityHint
                        )
                    }
                }
            }
            .navigationDestination(
                for: GitLabTodoNativeRoute.self
            ) { route in
                nativeDestination(for: route)
            }
            .refreshable {
                await refresh()
            }
            .task(id: model.query) {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
            .alert(
                "Mark all pending Todos done?",
                isPresented: $isConfirmingMarkAllDone
            ) {
                Button("Mark All Todos") {
                    Task {
                        await model.markAllDone()
                        await handleAuthenticationFailure()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "This updates every pending Todo on GitLab. "
                        + "Completed items remain available under Done."
                )
            }
        }
    }

    private func filterControls(
        model: Bindable<TodosModel>
    ) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 0) {
                    statePicker(model: model)
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)

                    Divider()

                    targetPicker(model: model)
                        .pickerStyle(.menu)
                        .frame(minHeight: 44)
                }
            } else {
                VStack(spacing: 10) {
                    statePicker(model: model)
                        .pickerStyle(.segmented)

                    targetPicker(model: model)
                        .pickerStyle(.segmented)
                }
            }
        }
    }

    private func statePicker(
        model: Bindable<TodosModel>
    ) -> some View {
        Picker(
            "State",
            selection: model.selectedState
        ) {
            ForEach(
                GitLabTodoState.allCases,
                id: \.self
            ) { state in
                Text(state.title)
                    .tag(state)
            }
        }
        .accessibilityIdentifier(
            "todos.statePicker"
        )
    }

    private func targetPicker(
        model: Bindable<TodosModel>
    ) -> some View {
        Picker(
            "Target",
            selection: model.selectedTargetFilter
        ) {
            ForEach(
                GitLabTodoTargetFilter.allCases,
                id: \.self
            ) { targetFilter in
                Text(targetFilter.title)
                    .tag(targetFilter)
            }
        }
        .accessibilityIdentifier(
            "todos.targetPicker"
        )
    }

    @ViewBuilder
    private var resourceRows: some View {
        if model.isLoadingInitial {
            GitLabLoadingStateView(
                message: "Loading \(listDescription)"
            )
            .padding(.vertical, 8)
            .listRowSeparator(.hidden)
        } else if
            model.todos.isEmpty,
            isCompleting
        {
            VStack(spacing: 14) {
                ProgressView()
                    .controlSize(.large)
                Text(completionProgressTitle)
                    .font(.headline)
                Text(
                    "The change is being saved to GitLab."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 430)
            .accessibilityElement(
                children: .combine
            )
            .gitLabAccessibilityAnnouncement(
                completionProgressTitle
            )
            .accessibilityIdentifier(
                "todos.completionProgress"
            )
            .listRowSeparator(.hidden)
        } else if
            model.todos.isEmpty,
            let error = model.loadError
        {
            GitLabRetryStateView(
                error: error
            ) {
                Task {
                    await refresh()
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 430)
            .listRowSeparator(.hidden)
        } else if
            model.todos.isEmpty,
            model.hasLoaded
        {
            GitLabEmptyStateView(
                title: emptyTitle,
                message: emptyMessage,
                systemImage:
                    model.selectedState == .pending
                    ? "checklist"
                    : "checkmark.circle"
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 430)
            .listRowSeparator(.hidden)
        } else {
            if
                model.didFailRefresh,
                let error = model.loadError
            {
                GitLabInlineRetryRow(
                    title: "Couldn’t refresh Todos",
                    error: error,
                    accessibilityIdentifier:
                        "todos.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            ForEach(model.todos) { todo in
                todoRow(todo)
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
                    title: "Couldn’t load more Todos",
                    error: error,
                    accessibilityIdentifier:
                        "todos.nextPageError"
                ) {
                    Task {
                        await model.retryNextPage()
                        await handleAuthenticationFailure()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func todoRow(
        _ todo: GitLabTodo
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            todoDestination(todo)

            if todo.state == .pending {
                Button {
                    Task {
                        await model.markDone(todo)
                        await handleAuthenticationFailure()
                    }
                } label: {
                    Image(
                        systemName:
                            "checkmark.circle"
                    )
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.orange)
                .disabled(
                    !model.canComplete
                        || model.isMarkingAllDone
                )
                .accessibilityLabel(
                    "Mark \(todo.title) done"
                )
                .accessibilityHint(
                    completionAccessibilityHint
                )
                .accessibilityIdentifier(
                    "todos.markDone.\(todo.id)"
                )
            }
        }
        .task {
            await model.loadNextPageIfNeeded(
                after: todo
            )
            await handleAuthenticationFailure()
        }
    }

    @ViewBuilder
    private func todoDestination(
        _ todo: GitLabTodo
    ) -> some View {
        Group {
            if let route = todo.nativeRoute {
                NavigationLink(value: route) {
                    GitLabTodoRow(todo: todo)
                }
            } else if let url = todo.safeTargetURL {
                Link(destination: url) {
                    GitLabTodoRow(todo: todo)
                }
            } else {
                GitLabTodoRow(todo: todo)
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .accessibilityIdentifier(
            "todos.row.\(todo.id)"
        )
    }

    @ViewBuilder
    private func nativeDestination(
        for route: GitLabTodoNativeRoute
    ) -> some View {
        switch route {
        case let .issue(issueRoute):
            GitLabIssueDetailView(
                route: issueRoute,
                loader: issueLoader,
                discussionLoader: discussionLoader,
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
        case let .mergeRequest(mergeRequestRoute):
            GitLabMergeRequestDetailView(
                route: mergeRequestRoute,
                loader: mergeRequestLoader,
                discussionLoader: discussionLoader,
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

    private var listDescription: String {
        [
            model.selectedState.title.lowercased(),
            targetDescription,
            "Todos",
        ]
        .joined(separator: " ")
    }

    private var readOnlyCompletionRow: some View {
        Label {
            Text(
                "Read-only access. The api scope is required "
                    + "to complete Todos."
            )
            .font(.footnote)
        } icon: {
            Image(systemName: "lock.fill")
        }
        .foregroundStyle(.orange)
        .listRowBackground(
            Color.orange.opacity(0.1)
        )
        .accessibilityIdentifier(
            "todos.readOnlyMessage"
        )
    }

    private var completionProgressRow: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(completionProgressTitle)
                .font(.footnote.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
        .gitLabAccessibilityAnnouncement(
            completionProgressTitle
        )
        .accessibilityIdentifier(
            "todos.completionProgress"
        )
    }

    private func mutationFailureRow(
        _ failure: GitLabTodoMutationFailure
    ) -> some View {
        GitLabInlineRetryRow(
            title: mutationFailureTitle(failure),
            error: failure.error,
            accessibilityIdentifier:
                "todos.mutationError"
        ) {
            Task {
                await model.retryFailedMutation()
                await handleAuthenticationFailure()
            }
        }
    }

    private var isCompleting: Bool {
        model.isMarkingAllDone
            || !model.completingTodoIDs.isEmpty
    }

    private var completionProgressTitle: String {
        model.isMarkingAllDone
            ? "Completing all Todos…"
            : "Completing Todo…"
    }

    private var completionAccessibilityHint: String {
        model.canComplete
            ? "Updates this Todo on GitLab."
            : "Requires a personal access token with the api scope."
    }

    private func mutationFailureTitle(
        _ failure: GitLabTodoMutationFailure
    ) -> String {
        switch failure {
        case .markDone:
            "Couldn’t complete Todo"
        case .markAllDone:
            "Couldn’t complete all Todos"
        }
    }

    private var targetDescription: String {
        switch model.selectedTargetFilter {
        case .all:
            "GitLab"
        case .issues:
            "issue"
        case .mergeRequests:
            "merge request"
        }
    }

    private var emptyTitle: String {
        "No \(model.selectedState.title.lowercased()) Todos"
    }

    private var emptyMessage: String {
        switch model.selectedTargetFilter {
        case .all:
            "You have no \(model.selectedState.rawValue) GitLab Todos."
        case .issues:
            "You have no \(model.selectedState.rawValue) issue Todos."
        case .mergeRequests:
            "You have no \(model.selectedState.rawValue) merge request Todos."
        }
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

private struct GitLabTodoRow: View {
    let todo: GitLabTodo

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            typeIcon

            VStack(alignment: .leading, spacing: 6) {
                header

                Text(todo.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(
                        dynamicTypeSize.isAccessibilitySize
                            ? nil
                            : 3
                    )

                if let body = todo.displayBody {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(
                            dynamicTypeSize.isAccessibilitySize
                                ? nil
                                : 2
                        )
                }

                footer
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var header: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                Text(todo.targetType.title)
                    .foregroundStyle(accentColor)
                Text(todo.projectTitle)
                updatedTime
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                Text(todo.targetType.title)
                    .foregroundStyle(accentColor)

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(todo.projectTitle)
                    .lineLimit(1)

                Spacer(minLength: 8)
                updatedTime
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var updatedTime: some View {
        Text(
            GitLabRelativeTimeFormatter.string(
                from: todo.updatedAt
            )
        )
        .monospacedDigit()
        .accessibilityLabel(
            "Updated "
                + todo.updatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
        )
    }

    @ViewBuilder
    private var footer: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 5) {
                author
                Text(todo.action.title)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                author

                Text("·")
                    .foregroundStyle(.tertiary)

                Text(todo.action.title)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var author: some View {
        HStack(spacing: 6) {
            if let author = todo.author {
                GitLabUserAvatar(
                    user: author.summary,
                    size: 20
                )
                .accessibilityHidden(true)
            } else {
                Image(
                    systemName:
                        "person.crop.circle"
                )
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            }

            Text(todo.authorTitle)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize
                        ? nil
                        : 1
                )
        }
    }

    private var typeIcon: some View {
        Image(systemName: todo.targetType.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(accentColor)
            .frame(width: 34, height: 34)
            .background(
                accentColor.opacity(0.12),
                in: .circle
            )
            .accessibilityHidden(true)
    }

    private var accentColor: Color {
        todo.state == .pending
            ? .orange
            : .secondary
    }

    private var accessibilityLabel: String {
        var parts = [
            todo.targetType.title,
            todo.projectTitle,
            todo.title,
        ]
        if let body = todo.displayBody {
            parts.append(body)
        }
        parts.append(todo.action.title)
        parts.append("By \(todo.authorTitle)")
        parts.append(
            "Updated "
                + todo.updatedAt.formatted(
                    date: .abbreviated,
                    time: .shortened
                )
        )
        return parts.joined(separator: ", ")
    }
}
