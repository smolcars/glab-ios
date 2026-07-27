import Foundation

nonisolated enum GitLabTodoEndpoints {
    static func todos(
        state: GitLabTodoState,
        targetFilter: GitLabTodoTargetFilter
    ) -> GitLabAPIRequest<[GitLabTodo]> {
        var query = [
            URLQueryItem(
                name: "state",
                value: state.rawValue
            ),
        ]
        if let type = targetFilter.queryValue {
            query.append(
                URLQueryItem(name: "type", value: type)
            )
        }
        query.append(
            URLQueryItem(name: "per_page", value: "20")
        )

        return .get(
            requires: .read,
            path: ["todos"],
            query: query
        )
    }

    static func markDone(
        id: Int
    ) -> GitLabAPIRequest<GitLabTodo> {
        .post(
            requires: .write,
            path: [
                "todos",
                String(id),
                "mark_as_done",
            ]
        )
    }

    static func markAllDone()
        -> GitLabAPIRequest<GitLabEmptyResponse>
    {
        .post(
            requires: .write,
            path: ["todos", "mark_as_done"]
        )
    }
}
