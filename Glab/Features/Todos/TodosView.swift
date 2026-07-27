import SwiftUI

struct TodosView: View {
    let model: TodosModel
    let appSession: AppSession

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

                resourceRows
            }
            .id(model.query)
            .listStyle(.plain)
            .accessibilityIdentifier("todos.list")
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("Todos")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await refresh()
            }
            .task(id: model.query) {
                await model.loadIfNeeded()
                await handleAuthenticationFailure()
            }
        }
    }

    private func filterControls(
        model: Bindable<TodosModel>
    ) -> some View {
        VStack(spacing: 10) {
            Picker(
                "Todo state",
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
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                "todos.statePicker"
            )

            Picker(
                "Target type",
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
            .pickerStyle(.segmented)
            .accessibilityIdentifier(
                "todos.targetPicker"
            )
        }
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
            let error = model.loadError
        {
            GitLabRetryStateView(
                message: error.description
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
                    message: error.description,
                    accessibilityIdentifier:
                        "todos.refreshError"
                ) {
                    Task {
                        await refresh()
                    }
                }
            }

            ForEach(model.todos) { todo in
                GitLabTodoRow(todo: todo)
                    .accessibilityIdentifier(
                        "todos.row.\(todo.id)"
                    )
                    .task {
                        await model.loadNextPageIfNeeded(
                            after: todo
                        )
                        await handleAuthenticationFailure()
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
                        "Try loading more Todos again",
                        systemImage: "arrow.clockwise"
                    )
                    .frame(maxWidth: .infinity)
                }
            }
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
        await appSession.handleAuthenticationFailure(error)
    }
}

private struct GitLabTodoRow: View {
    let todo: GitLabTodo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            typeIcon

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(todo.targetType.title)
                        .foregroundStyle(accentColor)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(todo.projectTitle)
                        .lineLimit(1)

                    Spacer(minLength: 8)

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
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(todo.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)

                if let body = todo.displayBody {
                    Text(body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

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
                        .lineLimit(1)

                    Text("·")
                        .foregroundStyle(.tertiary)

                    Text(todo.action.title)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
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
