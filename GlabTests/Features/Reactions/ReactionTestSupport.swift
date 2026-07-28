import Foundation
@testable import Glab

nonisolated func makeTestEmojiAward(
    id: Int = 91,
    name: String = "thumbsup",
    userID: Int = 7,
    awardableID: Int = 501,
    awardableType: String = "Issue"
) -> GitLabEmojiAward {
    GitLabEmojiAward(
        id: id,
        name: name,
        user: GitLabAPIUser(
            id: userID,
            username: "user-\(userID)",
            name: "User \(userID)",
            avatarURL: nil,
            webURL: nil
        ),
        createdAt: Date(
            timeIntervalSince1970:
                TimeInterval(id)
        ),
        updatedAt: Date(
            timeIntervalSince1970:
                TimeInterval(id)
        ),
        awardableID: awardableID,
        awardableType: awardableType
    )
}

nonisolated let testIssueAwardable:
    GitLabEmojiAwardable =
        .resource(
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )
