import Foundation

nonisolated enum GitLabEmojiReactionEndpoints {
    static func reactions(
        for awardable: GitLabEmojiAwardable
    ) -> GitLabAPIRequest<[GitLabEmojiAward]> {
        .get(
            requires: .read,
            path:
                path(for: awardable)
                + ["award_emoji"],
            query: [
                URLQueryItem(
                    name: "per_page",
                    value: "100"
                ),
            ]
        )
    }

    static func add(
        name: String,
        to awardable: GitLabEmojiAwardable
    ) -> GitLabAPIRequest<GitLabEmojiAward> {
        .post(
            requires: .write,
            path:
                path(for: awardable)
                + ["award_emoji"],
            query: [
                URLQueryItem(
                    name: "name",
                    value: name
                ),
            ]
        )
    }

    static func remove(
        awardID: Int,
        from awardable:
            GitLabEmojiAwardable
    ) -> GitLabAPIRequest<GitLabEmptyResponse> {
        .delete(
            requires: .write,
            path:
                path(for: awardable)
                + [
                    "award_emoji",
                    String(awardID),
                ]
        )
    }

    private static func path(
        for awardable: GitLabEmojiAwardable
    ) -> [String] {
        var path: [String]
        switch awardable.resource {
        case let .issue(route):
            path = [
                "projects",
                String(route.projectID),
                "issues",
                String(route.issueIID),
            ]
        case let .mergeRequest(route):
            path = [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
            ]
        }

        if let noteID = awardable.noteID {
            path += [
                "notes",
                String(noteID),
            ]
        }
        return path
    }
}
