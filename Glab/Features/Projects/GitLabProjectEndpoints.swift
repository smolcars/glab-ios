import Foundation

nonisolated enum GitLabProjectEndpoints {
    static func project(
        pathWithNamespace: String
    ) -> GitLabAPIRequest<GitLabProject> {
        .get(
            requires: .read,
            path: [
                "projects",
                pathWithNamespace,
            ]
        )
    }

    static func projects(
        for mode: GitLabProjectListMode
    ) -> GitLabAPIRequest<[GitLabProject]> {
        .get(
            requires: .read,
            path: ["projects"],
            query: [
                .init(
                    name: mode.filterName,
                    value: "true"
                ),
                .init(
                    name: "order_by",
                    value: "last_activity_at"
                ),
                .init(name: "sort", value: "desc"),
                .init(name: "simple", value: "true"),
                .init(name: "per_page", value: "20"),
            ]
        )
    }

    static func issueCreationProjects(
        search: String?
    ) -> GitLabAPIRequest<[GitLabProject]> {
        var query: [URLQueryItem] = [
            .init(
                name: "membership",
                value: "true"
            ),
            .init(
                name: "archived",
                value: "false"
            ),
            .init(
                name: "order_by",
                value: "last_activity_at"
            ),
            .init(name: "sort", value: "desc"),
            .init(name: "simple", value: "true"),
            .init(name: "per_page", value: "20"),
        ]
        if
            let search =
                search?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !search.isEmpty
        {
            query.append(
                .init(
                    name: "search",
                    value: search
                )
            )
        }

        return .get(
            requires: .read,
            path: ["projects"],
            query: query
        )
    }
}
