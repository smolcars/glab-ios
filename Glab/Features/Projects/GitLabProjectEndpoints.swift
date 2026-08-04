import Foundation

nonisolated enum GitLabProjectEndpoints {
    /// Smaller membership/activity limits can time out on GitLab.com.
    /// Work around gitlab-org/gitlab#591064 with the documented maximum.
    static let membershipActivityPageSize = 100

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
        for mode: GitLabProjectListMode,
        perPage: Int? = nil
    ) -> GitLabAPIRequest<[GitLabProject]> {
        let pageSize = perPage ?? (
            mode == .recent
                ? membershipActivityPageSize
                : 20
        )

        return .get(
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
                .init(
                    name: "per_page",
                    value: String(pageSize)
                ),
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
            .init(
                name: "per_page",
                value: String(membershipActivityPageSize)
            ),
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
