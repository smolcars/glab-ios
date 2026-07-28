import Foundation
import Testing
@testable import Glab

@Suite("GitLab emoji reactions")
struct GitLabEmojiReactionTests {
    @Test("Decodes individual awards without losing server identity")
    func decodesAwards() throws {
        let data = try #require(
            """
            [
              {
                "id": 91,
                "name": "thumbsup",
                "user": {
                  "id": 7,
                  "username": "nitesh",
                  "name": "Nitesh",
                  "avatar_url": null,
                  "web_url": "https://gitlab.example.com/nitesh"
                },
                "created_at": "2026-07-28T10:00:00Z",
                "updated_at": "2026-07-28T10:00:01Z",
                "awardable_id": 501,
                "awardable_type": "Issue",
                "future_field": true
              },
              {
                "id": 92,
                "name": "party-parrot",
                "user": {
                  "id": 8,
                  "username": "reviewer",
                  "name": "Reviewer",
                  "avatar_url": null,
                  "web_url": null
                },
                "created_at": "2026-07-28T10:01:00Z",
                "updated_at": "2026-07-28T10:01:00Z",
                "awardable_id": 501,
                "awardable_type": "Issue"
              }
            ]
            """.data(using: .utf8)
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let awards = try decoder.decode(
            [GitLabEmojiAward].self,
            from: data
        )

        #expect(awards.map(\.id) == [91, 92])
        #expect(
            awards.map(\.name)
                == ["thumbsup", "party-parrot"]
        )
        #expect(awards[0].user.id == 7)
        #expect(awards[0].awardableID == 501)
        #expect(awards[0].awardableType == "Issue")
    }

    @Test("Groups identical names and preserves current-user award IDs")
    func groupsAwards() {
        let awards = [
            makeAward(
                id: 91,
                name: "thumbsup",
                userID: 7
            ),
            makeAward(
                id: 92,
                name: "thumbsup",
                userID: 8
            ),
            makeAward(
                id: 93,
                name: "heart",
                userID: 7
            ),
            makeAward(
                id: 94,
                name: "thumbsup",
                userID: 7
            ),
            makeAward(
                id: 95,
                name: "party-parrot",
                userID: 9
            ),
        ]

        let groups =
            GitLabEmojiReactionGroup.groups(
                awards: awards,
                currentUserID: 7
            )

        #expect(
            groups.map(\.name)
                == [
                    "thumbsup",
                    "heart",
                    "party-parrot",
                ]
        )
        #expect(groups[0].count == 3)
        #expect(
            groups[0].currentUserAwardIDs
                == [91, 94]
        )
        #expect(groups[0].display == "👍")
        #expect(groups[1].display == "❤️")
        #expect(
            groups[2].display
                == ":party-parrot:"
        )
    }

    @Test("Provides the deliberately bounded common picker")
    func commonPicker() {
        #expect(
            GitLabEmojiPickerItem.common
                .map(\.name)
                == [
                    "thumbsup",
                    "thumbsdown",
                    "heart",
                    "tada",
                    "eyes",
                    "rocket",
                ]
        )
        #expect(
            Set(
                GitLabEmojiPickerItem.common
                    .map(\.name)
            ).count == 6
        )
    }
}

private extension GitLabEmojiReactionTests {
    func makeAward(
        id: Int,
        name: String,
        userID: Int
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
            awardableID: 501,
            awardableType: "Issue"
        )
    }
}
