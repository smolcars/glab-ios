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
}
