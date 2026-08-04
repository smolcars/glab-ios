import Foundation

nonisolated enum GitLabProjectEndpoints {
    static func starredProjects(
        userID: Int,
        matching pathWithNamespace: String
    ) -> GitLabAPIRequest<
        [GitLabStarredProjectReference]
    > {
        .get(
            requires: .read,
            path: [
                "users",
                String(userID),
                "starred_projects",
            ],
            query: [
                .init(
                    name: "search",
                    value: pathWithNamespace
                ),
                .init(name: "simple", value: "true"),
                .init(name: "per_page", value: "100"),
            ]
        )
    }

    static func star(
        projectID: Int
    ) -> GitLabAPIRequest<GitLabProject> {
        .post(
            requires: .write,
            path: [
                "projects",
                String(projectID),
                "star",
            ]
        )
    }

    static func unstar(
        projectID: Int
    ) -> GitLabAPIRequest<GitLabProject> {
        .post(
            requires: .write,
            path: [
                "projects",
                String(projectID),
                "unstar",
            ]
        )
    }

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
