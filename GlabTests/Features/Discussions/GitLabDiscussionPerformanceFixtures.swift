import Foundation

enum GitLabDiscussionPerformanceFixtures {
    static func data(
        discussionCount: Int,
        leadingSystemDiscussionCount: Int? = nil
    ) throws -> Data {
        let discussions = (0..<discussionCount).map {
            index in
            discussion(
                index: index,
                isSystem:
                    leadingSystemDiscussionCount
                        .map { limit in
                            index < limit
                        }
            )
        }
        return try JSONSerialization.data(
            withJSONObject: discussions,
            options: [.sortedKeys]
        )
    }

    private static func discussion(
        index: Int,
        isSystem: Bool?
    ) -> [String: Any] {
        let isThread = index.isMultiple(of: 5)
        let notes = isThread
            ? (0..<3).map {
                note(
                    discussionIndex: index,
                    replyIndex: $0,
                    isSystem: isSystem
                )
            }
            : [
                note(
                    discussionIndex: index,
                    replyIndex: 0,
                    isSystem: isSystem
                ),
            ]

        return [
            "id": "discussion-\(index)",
            "individual_note": !isThread,
            "notes": notes,
        ]
    }

    private static func note(
        discussionIndex: Int,
        replyIndex: Int,
        isSystem systemOverride: Bool?
    ) -> [String: Any] {
        let noteID =
            discussionIndex * 10 + replyIndex + 1
        let isSystem =
            systemOverride
            ?? discussionIndex.isMultiple(of: 4)
        let isDiff =
            discussionIndex.isMultiple(of: 7)
        let isInternal =
            discussionIndex.isMultiple(of: 11)
        let noteType: Any =
            if isDiff {
                "DiffNote"
            } else if replyIndex > 0 {
                "DiscussionNote"
            } else {
                NSNull()
            }

        var note: [String: Any] = [
            "id": noteID,
            "type": noteType,
            "body": body(
                discussionIndex:
                    discussionIndex,
                replyIndex: replyIndex,
                isSystem: isSystem
            ),
            "author": [
                "id": discussionIndex % 12 + 1,
                "username":
                    "reviewer-\(discussionIndex % 12)",
                "name":
                    "Reviewer \(discussionIndex % 12)",
                "avatar_url": NSNull(),
                "web_url":
                    "https://gitlab.example.com/"
                    + "reviewer-\(discussionIndex % 12)",
            ],
            "created_at":
                "2026-07-27T12:00:00.000Z",
            "updated_at":
                replyIndex.isMultiple(of: 2)
                ? "2026-07-27T12:00:00.000Z"
                : "2026-07-27T12:05:00.000Z",
            "system": isSystem,
            "noteable_id": 501,
            "noteable_type":
                isDiff ? "MergeRequest" : "Issue",
            "project_id": 42,
            "noteable_iid": 7,
            "confidential": false,
            "internal": isInternal,
            "resolvable": isDiff,
            "resolved": isDiff
                && discussionIndex.isMultiple(of: 14),
            "resolved_by": NSNull(),
            "resolved_at": NSNull(),
        ]

        if isDiff {
            note["position"] = [
                "old_path": "Sources/Old.swift",
                "new_path":
                    "Sources/Feature\(discussionIndex).swift",
                "old_line": 10,
                "new_line": 14 + replyIndex,
            ]
        }

        return note
    }

    private static func body(
        discussionIndex: Int,
        replyIndex: Int,
        isSystem: Bool
    ) -> String {
        if isSystem {
            return
                "changed status for item "
                + "\(discussionIndex)"
        }

        return """
        ## Review \(discussionIndex).\(replyIndex)

        This comment contains **Markdown**, `inline code`, and a reference to #42.

        - First observation
        - Second observation
        - Follow-up item \(discussionIndex)
        """
    }
}
