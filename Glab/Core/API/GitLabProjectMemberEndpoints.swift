import Foundation

nonisolated enum GitLabProjectMemberEndpoints {
    static func members(
        projectID: Int,
        search: String? = nil,
        perPage: Int = 20
    ) -> GitLabAPIRequest<
        [GitLabProjectMember]
    > {
        let normalizedSearch =
            search?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        var query = [
            URLQueryItem(
                name: "per_page",
                value: String(perPage)
            ),
        ]
        if
            let normalizedSearch,
            !normalizedSearch.isEmpty
        {
            query.append(
                URLQueryItem(
                    name: "query",
                    value: normalizedSearch
                )
            )
        }

        return .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "members",
                "all",
            ],
            query: query
        )
    }
}
