import Foundation

nonisolated enum GitLabMergeRequestEndpoints {
    static func mergeRequests(
        for mode: GitLabMergeRequestListMode
    ) -> GitLabAPIRequest<[GitLabMergeRequest]> {
        .get(
            path: ["merge_requests"],
            query: [
                .init(name: "scope", value: mode.scope),
                .init(name: "state", value: "opened"),
                .init(name: "order_by", value: "updated_at"),
                .init(name: "sort", value: "desc"),
                .init(name: "per_page", value: "20"),
            ]
        )
    }

    static func mergeRequest(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<GitLabMergeRequest> {
        .get(
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
            ]
        )
    }
}
