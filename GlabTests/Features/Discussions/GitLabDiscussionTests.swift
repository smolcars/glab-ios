import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion decoding")
struct GitLabDiscussionTests {
    @Test("Builds note Markdown identities for both resource types")
    func markdownResourceIdentities() {
        let issue: GitLabDiscussionResource =
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        let mergeRequest: GitLabDiscussionResource =
            .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 9
                )
            )

        #expect(
            issue.markdownResourceID(noteID: 101)
                == .issueNote(
                    projectID: 42,
                    issueIID: 7,
                    noteID: 101
                )
        )
        #expect(
            mergeRequest
                .markdownResourceID(noteID: 202)
                == .mergeRequestNote(
                    projectID: 42,
                    mergeRequestIID: 9,
                    noteID: 202
                )
        )
    }

    @Test("Decodes threads, replies, system activity, and evolving fields")
    func decodesDiscussionVariants() throws {
        let discussions = try decode(
            """
            [
              {
                "id": "thread-1",
                "individual_note": false,
                "future_discussion_field": {"ignored": true},
                "notes": [
                  {
                    "id": 101,
                    "type": "DiscussionNote",
                    "body": "Root **comment**",
                    "author": {
                      "id": 1,
                      "username": "reviewer",
                      "name": "Review Person",
                      "avatar_url": null,
                      "web_url": "https://gitlab.example.com/reviewer"
                    },
                    "created_at": "2026-07-27T10:00:00Z",
                    "updated_at": "2026-07-27T10:00:00Z",
                    "system": false,
                    "noteable_id": 501,
                    "noteable_type": "MergeRequest",
                    "project_id": 42,
                    "noteable_iid": 7,
                    "resolvable": true,
                    "resolved": true,
                    "resolved_by": {
                      "id": 2,
                      "username": "resolver",
                      "name": "Resolve Person",
                      "avatar_url": null,
                      "web_url": "https://gitlab.example.com/resolver"
                    },
                    "resolved_at": "2026-07-27T10:03:00Z",
                    "unknown_note_field": ["ignored"]
                  },
                  {
                    "id": 102,
                    "type": "FutureNote",
                    "body": "A reply",
                    "author": {
                      "id": 3,
                      "username": "reply",
                      "name": "Reply Person",
                      "avatar_url": null,
                      "web_url": "https://gitlab.example.com/reply"
                    },
                    "created_at": "2026-07-27T10:01:00Z",
                    "updated_at": "2026-07-27T10:02:00Z",
                    "system": false,
                    "noteable_id": 501,
                    "noteable_type": "MergeRequest",
                    "project_id": 42,
                    "noteable_iid": 7,
                    "internal": true
                  }
                ]
              },
              {
                "id": "activity-1",
                "individual_note": true,
                "notes": [
                  {
                    "id": 103,
                    "type": null,
                    "body": "changed the milestone",
                    "author": {
                      "id": 4,
                      "username": "maintainer",
                      "name": "Maintainer",
                      "avatar_url": null,
                      "web_url": "https://gitlab.example.com/maintainer"
                    },
                    "created_at": "2026-07-27T11:00:00Z",
                    "updated_at": "2026-07-27T11:00:00Z",
                    "system": true,
                    "noteable_id": 501,
                    "noteable_type": "MergeRequest",
                    "project_id": 42
                  }
                ]
              }
            ]
            """
        )

        #expect(discussions.map(\.id) == ["thread-1", "activity-1"])
        #expect(discussions[0].notes.map(\.id) == [101, 102])
        #expect(!discussions[0].individualNote)
        #expect(discussions[0].notes[0].kind == .discussion)
        #expect(discussions[0].notes[0].isResolved)
        #expect(
            discussions[0].notes[0].resolvedBy?
                .username == "resolver"
        )
        #expect(
            discussions[0].notes[0].resolvedAt
                == date("2026-07-27T10:03:00Z")
        )
        #expect(
            discussions[0].notes[1].kind
                == .unknown("FutureNote")
        )
        #expect(discussions[0].notes[1].isInternal)
        #expect(discussions[0].notes[1].isEdited)
        #expect(discussions[1].isSystemActivity)
        #expect(discussions[1].notes[0].kind == .individual)
    }

    @Test("Decodes diff position and legacy confidential notes")
    func decodesDiffPosition() throws {
        let discussion = try #require(
            decode(
                """
                [
                  {
                    "id": "diff-1",
                    "individual_note": false,
                    "notes": [
                      {
                        "id": 201,
                        "type": "DiffNote",
                        "body": "Please rename this.",
                        "author": {
                          "id": 1,
                          "username": "reviewer",
                          "name": "Reviewer",
                          "avatar_url": null,
                          "web_url": "https://gitlab.example.com/reviewer"
                        },
                        "created_at": "2026-07-27T12:00:00Z",
                        "updated_at": "2026-07-27T12:00:00Z",
                        "system": false,
                        "noteable_id": 99,
                        "noteable_type": "MergeRequest",
                        "project_id": 42,
                        "confidential": true,
                        "resolvable": true,
                        "resolved": false,
                        "position": {
                          "position_type": "text",
                          "old_path": "Sources/Old.swift",
                          "new_path": "Sources/New.swift",
                          "old_line": 18,
                          "new_line": 21,
                          "future_position_field": true
                        },
                        "suggestions": [{"from_line": 21}]
                      }
                    ]
                  }
                ]
                """
            ).first
        )
        let note = try #require(discussion.notes.first)

        #expect(note.kind == .diff)
        #expect(note.isInternal)
        #expect(note.isResolvable)
        #expect(!note.isResolved)
        #expect(
            note.position
                == GitLabDiscussionPosition(
                    oldPath: "Sources/Old.swift",
                    newPath: "Sources/New.swift",
                    oldLine: 18,
                    newLine: 21
                )
        )
        #expect(note.position?.displayPath == "Sources/New.swift")
        #expect(note.position?.displayLine == 21)
    }

    @Test("Decodes empty collections and empty discussion notes")
    func decodesEmptyValues() throws {
        #expect(try decode("[]").isEmpty)

        let discussion = try #require(
            decode(
                """
                [
                  {
                    "id": "empty",
                    "individual_note": false,
                    "notes": []
                  }
                ]
                """
            ).first
        )

        #expect(discussion.notes.isEmpty)
        #expect(!discussion.isSystemActivity)
    }

    @Test("Only user notes surface the edited presentation status")
    func editedPresentationStatus() {
        let updatedAt = Date(
            timeIntervalSince1970: 2_000
        )
        let userNote = makeTestDiscussionNote(
            updatedAt: updatedAt
        )
        let systemActivity = makeTestDiscussionNote(
            updatedAt: updatedAt,
            system: true
        )

        #expect(userNote.showsEditedStatus)
        #expect(!systemActivity.showsEditedStatus)
    }

    @Test(
        "Rejects missing required discussion and note identity",
        arguments: [
            """
            [{"individual_note":true,"notes":[]}]
            """,
            """
            [{
              "id":"thread",
              "individual_note":true,
              "notes":[{
                "type":null,
                "body":"Missing ID",
                "author":{
                  "id":1,
                  "username":"user",
                  "name":"User",
                  "avatar_url":null,
                  "web_url":"https://gitlab.example.com/user"
                },
                "created_at":"2026-07-27T10:00:00Z",
                "updated_at":"2026-07-27T10:00:00Z",
                "system":false,
                "noteable_id":1,
                "noteable_type":"Issue",
                "project_id":42
              }]
            }]
            """,
        ]
    )
    func rejectsMissingIdentity(json: String) {
        #expect(throws: (any Error).self) {
            try decode(json)
        }
    }

    private func decode(
        _ json: String
    ) throws -> [GitLabDiscussion] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            [GitLabDiscussion].self,
            from: Data(json.utf8)
        )
    }

    private func date(
        _ value: String
    ) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
