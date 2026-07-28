import Foundation

nonisolated enum GitLabMergeRequestEndpoints {
    static func mergeRequests(
        for mode: GitLabMergeRequestListMode
    ) -> GitLabAPIRequest<[GitLabMergeRequest]> {
        .get(
            requires: .read,
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
            requires: .read,
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
            ]
        )
    }

    static func update(
        at route: GitLabMergeRequestRoute,
        changes: GitLabResourceEditChanges
    ) throws -> GitLabAPIRequest<GitLabMergeRequest> {
        try .put(
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
            ],
            body:
                GitLabMergeRequestUpdateBody(
                    title: changes.title,
                    description:
                        changes.description
                )
        )
    }

    static func approvals(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<
        GitLabMergeRequestApprovalSummary
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
                "approvals",
            ]
        )
    }

    static func diffVersions(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<
        [GitLabMergeRequestDiffVersion]
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
                "versions",
            ],
            query: [
                URLQueryItem(
                    name: "per_page",
                    value: "1"
                ),
            ]
        )
    }
}

private nonisolated struct GitLabMergeRequestUpdateBody:
    Encodable,
    Sendable
{
    let title: String?
    let description: String?
}
