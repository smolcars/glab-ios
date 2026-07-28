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
