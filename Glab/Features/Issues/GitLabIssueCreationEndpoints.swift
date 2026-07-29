import Foundation

nonisolated enum GitLabIssueCreationEndpoints {
    static func labels(
        projectID: Int
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
            ]
        )
    }

    static func members(
        projectID: Int
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
            ]
        )
    }
}
