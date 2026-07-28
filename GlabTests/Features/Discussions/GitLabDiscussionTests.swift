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
                    "body": "added commits <ul><li>abc123 &amp; tests</li></ul>",
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
        #expect(
            discussions[1].notes[0].activityText
                == "added commits • abc123 & tests"
        )
        #expect(discussions[0].notes[0].activityText == nil)
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
                          "base_sha": "base-secret",
                          "start_sha": "start-secret",
                          "head_sha": "head-secret",
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
                    baseSHA: "base-secret",
                    startSHA: "start-secret",
                    headSHA: "head-secret",
                    positionType: "text",
                    oldPath: "Sources/Old.swift",
                    newPath: "Sources/New.swift",
                    oldLine: 18,
                    newLine: 21
                )
        )
        #expect(note.position?.displayPath == "Sources/New.swift")
        #expect(note.position?.displayLine == 21)
        #expect(
            note.position?.versionIdentity
                == GitLabMergeRequestDiffVersionIdentity(
                    baseSHA: "base-secret",
                    startSHA: "start-secret",
                    headSHA: "head-secret"
                )
        )
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

    @Test("Derives unresolved and resolved thread state from the first resolvable note")
    func derivesThreadResolution() {
        let resolver = GitLabAPIUser(
            id: 44,
            username: "resolver",
            name: "Resolve Person",
            avatarURL: nil,
            webURL: nil
        )
        let resolvedAt = Date(
            timeIntervalSince1970: 2_000
        )
        let unresolved =
            makeTestDiscussion(
                id: "unresolved",
                notes: [
                    makeTestDiscussionNote(
                        resolvable: true,
                        resolved: false
                    ),
                ]
            )
        let resolved =
            makeTestDiscussion(
                id: "resolved",
                notes: [
                    makeTestDiscussionNote(
                        resolvable: true,
                        resolved: true,
                        resolvedBy: resolver,
                        resolvedAt: resolvedAt
                    ),
                ]
            )

        #expect(
            unresolved.threadResolution
                == GitLabDiscussionThreadResolution(
                    discussionID: "unresolved",
                    isResolved: false,
                    resolvedBy: nil,
                    resolvedAt: nil
                )
        )
        #expect(
            resolved.threadResolution
                == GitLabDiscussionThreadResolution(
                    discussionID: "resolved",
                    isResolved: true,
                    resolvedBy: resolver,
                    resolvedAt: resolvedAt
                )
        )
    }

    @Test("Ignores individual, empty, system-only, and non-resolvable discussions")
    func ignoresNonActionableResolutionSources() {
        let resolvable =
            makeTestDiscussionNote(
                type: "DiscussionNote",
                resolvable: true
            )
        let discussions = [
            makeTestDiscussion(
                id: "individual",
                individualNote: true,
                notes: [resolvable]
            ),
            makeTestDiscussion(
                id: "empty",
                notes: []
            ),
            makeTestDiscussion(
                id: "system",
                notes: [
                    makeTestDiscussionNote(
                        system: true,
                        resolvable: false,
                        resolved: true
                    ),
                ]
            ),
            makeTestDiscussion(
                id: "ordinary",
                notes: [
                    makeTestDiscussionNote(
                        resolvable: false,
                        resolved: true
                    ),
                ]
            ),
        ]

        #expect(
            discussions.allSatisfy {
                $0.threadResolution == nil
            }
        )
    }

    @Test("Uses the first resolvable note and never infers from a resolved reply")
    func usesFirstResolvableNote() {
        let firstResolver =
            GitLabAPIUser(
                id: 1,
                username: "first",
                name: "First",
                avatarURL: nil,
                webURL: nil
            )
        let discussion =
            makeTestDiscussion(
                notes: [
                    makeTestDiscussionNote(
                        id: 1,
                        resolvable: false,
                        resolved: true
                    ),
                    makeTestDiscussionNote(
                        id: 2,
                        resolvable: true,
                        resolved: false,
                        resolvedBy: firstResolver,
                        resolvedAt: Date(
                            timeIntervalSince1970:
                                3_000
                        )
                    ),
                    makeTestDiscussionNote(
                        id: 3,
                        resolvable: true,
                        resolved: true
                    ),
                ]
            )

        #expect(
            discussion.threadResolution?
                .isResolved == false
        )
        #expect(
            discussion.threadResolution?
                .resolvedBy == nil
        )
        #expect(
            discussion.threadResolution?
                .resolvedAt == nil
        )
    }

    @Test("Diff position age and mapping do not affect thread resolution")
    func derivesResolutionForEveryDiffPosition() {
        let positions: [
            GitLabDiscussionPosition?
        ] = [
            GitLabDiscussionPosition(
                baseSHA: "base",
                startSHA: "start",
                headSHA: "head",
                positionType: "text",
                oldPath: "Old.swift",
                newPath: "New.swift",
                oldLine: 2,
                newLine: 3
            ),
            GitLabDiscussionPosition(
                baseSHA: "old-base",
                startSHA: "old-start",
                headSHA: "old-head",
                positionType: "text",
                oldPath: "Old.swift",
                newPath: "New.swift",
                oldLine: 2,
                newLine: 3
            ),
            GitLabDiscussionPosition(
                positionType: "text"
            ),
            nil,
        ]

        for (index, position) in
            positions.enumerated()
        {
            let discussion =
                makeTestDiscussion(
                    id: "diff-\(index)",
                    notes: [
                        makeTestDiscussionNote(
                            type: "DiffNote",
                            resolvable: true,
                            resolved: false,
                            position: position
                        ),
                    ]
                )

            #expect(
                discussion.threadResolution?
                    .discussionID
                    == "diff-\(index)"
            )
            #expect(
                discussion.threadResolution?
                    .isResolved == false
            )
        }
    }

    @Test("Missing resolved state is unresolved and malformed metadata is hidden")
    func handlesEvolvingResolutionFields() {
        let resolver =
            GitLabAPIUser(
                id: 1,
                username: "resolver",
                name: "Resolver",
                avatarURL: nil,
                webURL: nil
            )
        let discussion =
            makeTestDiscussion(
                notes: [
                    makeTestDiscussionNote(
                        resolvable: true,
                        resolved: nil,
                        resolvedBy: resolver,
                        resolvedAt: Date(
                            timeIntervalSince1970:
                                4_000
                        )
                    ),
                ]
            )

        #expect(
            discussion.threadResolution?
                .isResolved == false
        )
        #expect(
            discussion.threadResolution?
                .resolvedBy == nil
        )
        #expect(
            discussion.threadResolution?
                .resolvedAt == nil
        )
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
