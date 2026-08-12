#if DEBUG
    import SwiftUI

    struct TodoCatchUpFixtureView: View {
        @State private var path = NavigationPath()
        @State private var catchUpModel:
            TodoCatchUpModel

        init() {
            let service =
                TodoCatchUpFixtureService(
                    todos:
                        Self.fixtureTodos
                )
            let todosModel = TodosModel(
                loader: service,
                mutator: service,
                apiAccess: .readWrite
            )
            _catchUpModel = State(
                initialValue: TodoCatchUpModel(
                    todosModel: todosModel
                )
            )
        }

        var body: some View {
            NavigationStack(path: $path) {
                List {
                    if catchUpModel.shouldShowHomeShortcut {
                        Section {
                            NavigationLink(
                                value:
                                    TodoCatchUpFixtureRoute
                                    .catchUp
                            ) {
                                HomeCatchUpShortcutRow(
                                    count:
                                        catchUpModel
                                        .homeShortcutCount
                                )
                            }
                            .accessibilityIdentifier(
                                "fixture.home.catchUp"
                            )
                        }
                    }

                    Section("My Work") {
                        Label(
                            "Assigned issues",
                            systemImage:
                                "smallcircle.filled.circle"
                        )
                        Label(
                            "Merge requests",
                            systemImage:
                                "arrow.triangle.branch"
                        )
                    }
                }
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(
                    for:
                        TodoCatchUpFixtureRoute
                        .self
                ) { _ in
                    TodoCatchUpView(
                        model: catchUpModel
                    )
                }
                .navigationDestination(
                    for: GitLabNativeRoute.self
                ) { route in
                    TodoCatchUpFixtureDetailView(
                        route: route
                    )
                }
                .task {
                    await catchUpModel
                        .startIfNeeded()
                }
            }
            .environment(
                \.gitLabNativeNavigationAction,
                { route in
                    path.append(route)
                }
            )
        }

        private static let fixtureTodos: [
            GitLabTodo
        ] = [
            makeTodo(
                id: 101,
                title:
                    "Review the new OAuth token refresh flow",
                body:
                    "Please confirm the refresh flow keeps one shared request for concurrent failures and preserves the pending deep link.",
                action: .approvalRequired,
                targetType: .mergeRequest
            ),
            makeTodo(
                id: 102,
                title:
                    "Crash when opening a repository without a default branch",
                body:
                    "The source screen should preserve its cached state and show a compact recovery action instead of trying to construct a tree route with an empty ref.",
                action: .assigned,
                targetType: .issue
            ),
            makeTodo(
                id: 103,
                title:
                    "Pipeline failed on the release branch",
                body:
                    "The iOS 26 build failed during the archive step. Open the pipeline details and inspect the first failed job before retrying.",
                action: .buildFailed,
                targetType: .mergeRequest
            ),
            makeTodo(
                id: 104,
                title:
                    "Confirm Dynamic Type layout for long discussion threads",
                body:
                    "At accessibility sizes, metadata must stack vertically and every action must retain a minimum forty-four point target.",
                action: .mentioned,
                targetType: .issue
            ),
            makeTodo(
                id: 105,
                title:
                    "Resolve the merge conflict in the cache refactor",
                body:
                    "The response-cache branch changed the same invalidation path as the Todo completion work.",
                action: .unmergeable,
                targetType: .mergeRequest
            ),
        ]

        private static func makeTodo(
            id: Int,
            title: String,
            body: String,
            action: GitLabTodoAction,
            targetType: GitLabTodoTargetType
        ) -> GitLabTodo {
            GitLabTodo(
                id: id,
                project: GitLabTodoProject(
                    id: 42,
                    name: "Glab",
                    nameWithNamespace:
                        "Mobile / Glab",
                    path: "glab",
                    pathWithNamespace:
                        "mobile/glab"
                ),
                author: GitLabAPIUser(
                    id: 7,
                    username: "mona",
                    name: "Mona Lisa",
                    avatarURL: nil,
                    webURL: nil
                ),
                action: action,
                targetType: targetType,
                target: GitLabTodoTarget(
                    id: id + 1_000,
                    iid: id - 90,
                    projectID: 42,
                    title: title,
                    name: nil,
                    description: body,
                    state: "opened"
                ),
                targetURL: targetURL(
                    id: id - 90,
                    targetType: targetType
                ),
                body: body,
                state: .pending,
                createdAt:
                    Date(
                        timeIntervalSince1970:
                            1_786_500_000
                            - Double(id * 60)
                    ),
                updatedAt:
                    Date(
                        timeIntervalSince1970:
                            1_786_500_000
                            - Double(id * 30)
                    )
            )
        }

        private static func targetURL(
            id: Int,
            targetType: GitLabTodoTargetType
        ) -> URL? {
            let path =
                targetType == .mergeRequest
                ? "merge_requests"
                : "issues"
            return URL(
                string:
                    "https://gitlab.example.com/mobile/glab/-/\(path)/\(id)"
            )
        }

    }

    private enum TodoCatchUpFixtureRoute:
        Hashable
    {
        case catchUp
    }

    private struct TodoCatchUpFixtureDetailView:
        View
    {
        let route: GitLabNativeRoute

        var body: some View {
            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 16
                ) {
                    Label(
                        detailType,
                        systemImage: detailIcon
                    )
                    .font(.glabSubheadline.weight(.semibold))
                    .foregroundStyle(Color.glabAccent)

                    Text("Fixture Todo detail")
                        .font(.glabTitle.bold())

                    Text(
                        "This fixture verifies that tapping a card pushes a detail screen and the native Back button returns to the same Catch Up deck position."
                    )
                    .font(.glabBody)
                    .foregroundStyle(.secondary)
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
                .padding(20)
            }
            .background(Color.glabCanvas)
            .navigationTitle(detailType)
            .navigationBarTitleDisplayMode(.inline)
        }

        private var detailType: String {
            switch route {
            case .issue:
                "Issue"
            case .mergeRequest:
                "Merge request"
            case .project:
                "Project"
            case .repositoryFile:
                "Repository file"
            case .user:
                "User"
            }
        }

        private var detailIcon: String {
            switch route {
            case .issue:
                "smallcircle.filled.circle"
            case .mergeRequest:
                "arrow.triangle.branch"
            case .project:
                "folder"
            case .repositoryFile:
                "doc.text"
            case .user:
                "person"
            }
        }
    }

    private actor TodoCatchUpFixtureService:
        GitLabTodoLoading,
        GitLabTodoMutating
    {
        private var todos: [GitLabTodo]

        init(todos: [GitLabTodo]) {
            self.todos = todos
        }

        func loadTodosPage(
            state: GitLabTodoState,
            targetFilter: GitLabTodoTargetFilter,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabTodoPage
        {
            GitLabTodoPage(
                todos:
                    state == .pending
                    ? todos
                    : [],
                nextPageURL: nil,
                totalCount:
                    state == .pending
                    ? todos.count
                    : 0
            )
        }

        func markDone(
            id: Int
        ) async throws(GitLabSessionClientError)
            -> GitLabTodo
        {
            guard
                let index = todos.firstIndex(
                    where: { $0.id == id }
                )
            else {
                throw .api(.invalidResponse)
            }
            let pending = todos.remove(at: index)
            return GitLabTodo(
                id: pending.id,
                project: pending.project,
                author: pending.author,
                action: pending.action,
                targetType: pending.targetType,
                target: pending.target,
                targetURL: pending.targetURL,
                body: pending.body,
                state: .done,
                createdAt: pending.createdAt,
                updatedAt: pending.updatedAt
            )
        }

        func markAllDone()
            async throws(GitLabSessionClientError)
        {
            todos.removeAll()
        }
    }
#endif
