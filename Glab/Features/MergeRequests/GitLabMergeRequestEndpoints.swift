import Foundation

nonisolated enum
    GitLabMergeRequestMergeEndpointError:
    Error,
    Equatable,
    Sendable
{
    case emptyHeadSHA
}

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

    static func projectMergeRequests(
        projectID: Int,
        state: GitLabProjectMergeRequestState
    ) -> GitLabAPIRequest<[GitLabMergeRequest]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "merge_requests",
            ],
            query: [
                .init(name: "scope", value: "all"),
                .init(
                    name: "state",
                    value: state.rawValue
                ),
                .init(
                    name: "order_by",
                    value: "updated_at"
                ),
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

    static func updateMetadata(
        at route: GitLabMergeRequestRoute,
        changes: GitLabResourceMetadataChanges
    ) throws -> GitLabAPIRequest<GitLabMergeRequest> {
        try .put(
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
            ],
            body:
                changes.updateBody(
                    allowsReviewers: true
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

    static func approvalDetails(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<
        GitLabMergeRequestApprovalDetails
    > {
        .get(
            requires: .read,
            path:
                mergeRequestPath(route)
                + ["approval_state"]
        )
    }

    static func approvalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int
    ) -> GitLabAPIRequest<
        GitLabMergeRequestApprovalRule
    > {
        .get(
            requires: .read,
            path:
                mergeRequestPath(route)
                + [
                    "approval_rules",
                    String(ruleID),
                ]
        )
    }

    static func approve(
        at route: GitLabMergeRequestRoute,
        sha: String
    ) throws -> GitLabAPIRequest<
        GitLabMergeRequestApprovalSummary
    > {
        try .post(
            requires: .write,
            path:
                mergeRequestPath(route)
                + ["approve"],
            body:
                GitLabMergeRequestApprovalBody(
                    sha: sha
                )
        )
    }

    static func merge(
        at route: GitLabMergeRequestRoute,
        sha: String,
        autoMerge: Bool
    ) throws -> GitLabAPIRequest<
        GitLabMergeRequest
    > {
        let normalizedSHA =
            sha.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !normalizedSHA.isEmpty else {
            throw GitLabMergeRequestMergeEndpointError
                .emptyHeadSHA
        }
        return try .put(
            path:
                mergeRequestPath(route)
                + ["merge"],
            body:
                GitLabMergeRequestMergeBody(
                    sha: normalizedSHA,
                    autoMerge:
                        autoMerge
                        ? true
                        : nil
                )
        )
    }

    static func unapprove(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<
        GitLabMergeRequestApprovalSummary
    > {
        .post(
            requires: .write,
            path:
                mergeRequestPath(route)
                + ["unapprove"]
        )
    }

    static func updateApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int,
        replacement:
            GitLabMergeRequestApprovalRuleReplacement
    ) throws -> GitLabAPIRequest<
        GitLabMergeRequestApprovalRule
    > {
        try .put(
            path:
                mergeRequestPath(route)
                + [
                    "approval_rules",
                    String(ruleID),
                ],
            body: replacement
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

    private static func mergeRequestPath(
        _ route: GitLabMergeRequestRoute
    ) -> [String] {
        [
            "projects",
            String(route.projectID),
            "merge_requests",
            String(route.mergeRequestIID),
        ]
    }
}

private nonisolated struct GitLabMergeRequestUpdateBody:
    Encodable,
    Sendable
{
    let title: String?
    let description: String?
}

private nonisolated struct
    GitLabMergeRequestApprovalBody:
    Encodable,
    Sendable
{
    let sha: String
}

private nonisolated struct
    GitLabMergeRequestMergeBody:
    Encodable,
    Sendable
{
    let sha: String
    let autoMerge: Bool?

    private enum CodingKeys: String, CodingKey {
        case sha
        case autoMerge = "auto_merge"
    }
}
