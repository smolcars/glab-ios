import Foundation

nonisolated enum GitLabDiscussionEndpoints {
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
