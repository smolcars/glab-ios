import Foundation

nonisolated enum GitLabDiscussionEndpoints {
    private struct ResolutionBody:
        Encodable,
        Sendable
    {
        let resolved: Bool
    }

    private struct DiffDiscussionBody:
        Encodable
    {
        let body: String
        let position: DiffPositionBody
    }

    private struct DiffPositionBody:
        Encodable
    {
        let baseSHA: String
        let startSHA: String
        let headSHA: String
        let oldPath: String
        let newPath: String
        let oldLine: Int?
        let newLine: Int?
        let positionType = "text"

        private enum CodingKeys:
            String,
            CodingKey
        {
            case baseSHA = "base_sha"
            case startSHA = "start_sha"
            case headSHA = "head_sha"
            case oldPath = "old_path"
            case newPath = "new_path"
            case oldLine = "old_line"
            case newLine = "new_line"
            case positionType = "position_type"
        }
    }

    static func discussions(
        for resource: GitLabDiscussionResource
    ) -> GitLabAPIRequest<[GitLabDiscussion]> {
        .get(
            requires: .read,
            path: path(for: resource),
            query: [
                URLQueryItem(
                    name: "per_page",
                    value: "20"
                ),
            ]
        )
    }

    static func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws -> GitLabAPIRequest<GitLabDiscussion> {
        try .post(
            requires: .write,
            path: path(for: resource),
            body: body
        )
    }

    static func mergeRequestDiscussion(
        at route: GitLabMergeRequestRoute,
        discussionID: String
    ) -> GitLabAPIRequest<GitLabDiscussion> {
        .get(
            requires: .read,
            path:
                path(
                    for: .mergeRequest(route)
                )
                + [discussionID]
        )
    }

    static func setMergeRequestDiscussionResolution(
        at route: GitLabMergeRequestRoute,
        discussionID: String,
        resolved: Bool
    ) throws -> GitLabAPIRequest<GitLabDiscussion> {
        try .put(
            path:
                path(
                    for: .mergeRequest(route)
                )
                + [discussionID],
            body:
                ResolutionBody(
                    resolved: resolved
                )
        )
    }

    static func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) throws -> GitLabAPIRequest<GitLabDiscussion> {
        try .post(
            requires: .write,
            path:
                path(
                    for:
                        .mergeRequest(route)
                ),
            body: DiffDiscussionBody(
                body: body.body,
                position: DiffPositionBody(
                    baseSHA:
                        position.version.baseSHA,
                    startSHA:
                        position.version.startSHA,
                    headSHA:
                        position.version.headSHA,
                    oldPath: position.oldPath,
                    newPath: position.newPath,
                    oldLine: position.oldLine,
                    newLine: position.newLine
                )
            )
        )
    }

    static func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws -> GitLabAPIRequest<GitLabDiscussionNote> {
        try .post(
            requires: .write,
            path:
                path(for: resource)
                + [
                    discussionID,
                    "notes",
                ],
            body: body
        )
    }

    private static func path(
        for resource: GitLabDiscussionResource
    ) -> [String] {
        switch resource {
        case let .issue(route):
            [
                "projects",
                "\(route.projectID)",
                "issues",
                "\(route.issueIID)",
                "discussions",
            ]
        case let .mergeRequest(route):
            [
                "projects",
                "\(route.projectID)",
                "merge_requests",
                "\(route.mergeRequestIID)",
                "discussions",
            ]
        }
    }
}
