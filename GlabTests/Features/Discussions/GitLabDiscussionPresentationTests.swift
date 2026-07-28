import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion presentation")
struct GitLabDiscussionPresentationTests {
    @Test("Groups system-only discussions and preserves conversation order")
    func partitionsSystemActivity() throws {
        let firstComment = makeTestDiscussion(
            id: "first-comment",
            notes: [
                makeTestDiscussionNote(
                    id: 1
                ),
            ]
        )
        let firstActivity = makeTestDiscussion(
            id: "first-activity",
            notes: [
                makeTestDiscussionNote(
                    id: 2,
                    body: "approved",
                    system: true
                ),
                makeTestDiscussionNote(
                    id: 3,
                    body: "added commits",
                    system: true
                ),
            ]
        )
        let secondComment = makeTestDiscussion(
            id: "second-comment",
            notes: [
                makeTestDiscussionNote(
                    id: 4
                ),
            ]
        )
        let secondActivity = makeTestDiscussion(
            id: "second-activity",
            notes: [
                makeTestDiscussionNote(
                    id: 5,
                    body: "changed title",
                    system: true
                ),
            ]
        )
        let discussions = [
            firstComment,
            firstActivity,
            secondComment,
            secondActivity,
        ]

        let presentation =
            GitLabDiscussionPresentation(
                discussions: discussions
            )

        #expect(
            presentation.activityNotes
                .map(\.id)
                == [2, 3, 5]
        )
        #expect(
            presentation.conversations
                .map(\.id)
                == [
                    "first-comment",
                    "second-comment",
                ]
        )
        #expect(
            presentation.paginationAnchor?.id
                == "second-activity"
        )
    }

    @Test("Keeps mixed and empty discussions intact")
    func preservesMixedThreads() {
        let mixed = makeTestDiscussion(
            id: "mixed",
            notes: [
                makeTestDiscussionNote(
                    id: 10,
                    system: true
                ),
                makeTestDiscussionNote(
                    id: 11,
                    system: false
                ),
            ]
        )
        let empty = makeTestDiscussion(
            id: "empty",
            notes: []
        )

        let presentation =
            GitLabDiscussionPresentation(
                discussions: [
                    mixed,
                    empty,
                ]
            )

        #expect(
            presentation.activityNotes.isEmpty
        )
        #expect(
            presentation.conversations
                == [mixed, empty]
        )
        #expect(
            presentation.paginationAnchor?.id
                == "empty"
        )
    }
}

@Suite("GitLab activity text normalization")
struct GitLabActivityTextNormalizerTests {
    @Test("Converts bounded server HTML into compact readable text")
    func normalizesHTML() {
        let normalizer =
            GitLabActivityTextNormalizer()

        let value = normalizer.normalize(
            """
            added 2 commits
            <ul><li>abc123 &amp; tests</li><li>def456<br>docs</li></ul>
            """
        )

        #expect(
            value
                == "added 2 commits • abc123 & tests • def456 docs"
        )
    }

    @Test("Decodes common named, decimal, and hexadecimal entities")
    func decodesEntities() {
        let value =
            GitLabActivityTextNormalizer()
                .normalize(
                    "A &lt; B &amp;&amp; C &#39;ok&#39; &#x1F680;"
                )

        #expect(
            value
                == "A < B && C 'ok' 🚀"
        )
    }

    @Test("Preserves malformed unmatched markup as readable text")
    func preservesMalformedMarkup() {
        let value =
            GitLabActivityTextNormalizer()
                .normalize(
                    "approved <not closed &unknown;"
                )

        #expect(
            value
                == "approved <not closed &unknown;"
        )
    }

    @Test("Bounds source scanning and output size")
    func boundsWork() {
        let normalizer =
            GitLabActivityTextNormalizer(
                maximumSourceLength: 24,
                maximumOutputLength: 12
            )

        let value = normalizer.normalize(
            String(
                repeating: "abcdef",
                count: 100
            )
        )

        #expect(value == "abcdefabcdef")
        #expect(value.count == 12)
    }

    @Test("Provides a useful fallback for markup-only activity")
    func fallsBackForEmptyOutput() {
        let value =
            GitLabActivityTextNormalizer()
                .normalize(
                    "<div><br></div>"
                )

        #expect(
            value
                == "Activity details unavailable"
        )
    }
}

@Suite("GitLab discussion composer launch policy")
struct GitLabDiscussionComposerLaunchPolicyTests {
    @Test("Allows write-enabled comment and reply targets")
    func allowsWriteTargets() {
        #expect(
            GitLabDiscussionComposerLaunchPolicy
                .decision(
                    for: .newDiscussion,
                    apiAccess: .readWrite
                )
                == .present(.newDiscussion)
        )
        #expect(
            GitLabDiscussionComposerLaunchPolicy
                .decision(
                    for:
                        .reply(
                            discussionID: "thread"
                        ),
                    apiAccess: .readWrite
                )
                == .present(
                    .reply(
                        discussionID: "thread"
                    )
                )
        )
    }

    @Test("Explains read-only access without creating a target")
    func blocksReadOnlyTargets() {
        #expect(
            GitLabDiscussionComposerLaunchPolicy
                .decision(
                    for: .newDiscussion,
                    apiAccess: .readOnly
                )
                == .explainReadOnly
        )
    }
}
