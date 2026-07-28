import Foundation

nonisolated enum GitLabMergeRequestDiffEndpoints {
    static func diffs(
        at route: GitLabMergeRequestRoute,
        headSHA: String
    ) -> GitLabAPIRequest<[GitLabMergeRequestDiffFile]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
                "diffs",
            ],
            query: [
                .init(
                    name: "per_page",
                    value: "20"
                ),
            ],
            cacheVariant: headSHA
        )
    }
}
