import Foundation

nonisolated enum GitLabIssueCreationEndpoints {
    static func labels(
        projectID: Int,
        search: String? = nil
    ) -> GitLabAPIRequest<[GitLabProjectLabel]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "labels",
            ],
            query: [
                .init(
                    name: "with_counts",
                    value: "false"
                ),
                .init(
                    name: "include_ancestor_groups",
                    value: "true"
                ),
                .init(
                    name: "per_page",
                    value: "20"
                ),
            ] + searchQuery(
                name: "search",
                value: search
            )
        )
    }

    static func members(
        projectID: Int,
        search: String? = nil
    ) -> GitLabAPIRequest<[GitLabProjectMember]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "members",
                "all",
            ],
            query: [
                .init(
                    name: "per_page",
                    value: "20"
                ),
            ] + searchQuery(
                name: "query",
                value: search
            )
        )
    }

    private static func searchQuery(
        name: String,
        value: String?
    ) -> [URLQueryItem] {
        let normalized =
            value?.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            let normalized,
            !normalized.isEmpty
        else {
            return []
        }
        return [
            URLQueryItem(
                name: name,
                value: normalized
            ),
        ]
    }
}
