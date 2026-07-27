import Foundation

nonisolated enum GitLabProjectEndpoints {
    static func projects(
        for mode: GitLabProjectListMode
    ) -> GitLabAPIRequest<[GitLabProject]> {
        .get(
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
}

