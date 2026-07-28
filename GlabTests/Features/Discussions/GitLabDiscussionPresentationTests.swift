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

@Suite("GitLab discussion resolution presentation")
struct GitLabDiscussionResolutionPresentationTests {
    @Test("Presents unresolved and resolved thread actions")
    func presentsAuthoritativeStates() {
        let resolver =
            GitLabAPIUser(
                id: 2,
                username: "resolver",
                name: "Resolve Person",
                avatarURL: nil,
                webURL: nil
            )
        let unresolved =
            GitLabDiscussionResolutionPresentation(
                status:
                    GitLabDiscussionResolutionStatus(
                        isResolved: false,
                        phase: .idle,
                        desiredResolved: nil,
                        resolvedBy: nil,
                        resolvedAt: nil,
                        failure: nil
                    ),
                apiAccess: .readWrite,
                discussionID: "thread"
            )
        let resolved =
            GitLabDiscussionResolutionPresentation(
                status:
                    GitLabDiscussionResolutionStatus(
                        isResolved: true,
                        phase: .idle,
                        desiredResolved: nil,
                        resolvedBy: resolver,
                        resolvedAt:
                            Date(
                                timeIntervalSince1970:
                                    1_000
                            ),
                        failure: nil
                    ),
                apiAccess: .readWrite,
                discussionID: "thread"
            )

        #expect(unresolved.action == .toggle)
        #expect(unresolved.actionTitle == "Resolve")
        #expect(unresolved.statusTitle == nil)
        #expect(unresolved.isActionEnabled)
        #expect(!unresolved.showsProgress)

        #expect(resolved.action == .toggle)
        #expect(resolved.actionTitle == "Reopen")
        #expect(
            resolved.statusTitle
                == "Resolved by Resolve Person"
        )
        #expect(resolved.isActionEnabled)
    }

    @Test("Presents optimistic resolution without fabricating resolver metadata")
    func presentsPendingStates() {
        let resolving =
            presentation(
                isResolved: true,
                phase: .pending,
                desiredResolved: true
            )
        let reopening =
            presentation(
                isResolved: false,
                phase: .pending,
                desiredResolved: false
            )

        #expect(resolving.action == nil)
        #expect(
            resolving.actionTitle
                == "Resolving…"
        )
        #expect(
            resolving.statusTitle
                == "Resolution pending"
        )
        #expect(resolving.showsProgress)
        #expect(!resolving.isActionEnabled)

        #expect(reopening.action == nil)
        #expect(
            reopening.actionTitle
                == "Reopening…"
        )
        #expect(
            reopening.statusTitle
                == "Reopen pending"
        )
        #expect(reopening.showsProgress)
    }

    @Test("Presents explicit check and retry recovery")
    func presentsRecovery() {
        let unknown =
            presentation(
                isResolved: true,
                phase: .deliveryUnknown,
                desiredResolved: true,
                failure:
                    .mutation(
                        .request(
                            .api(
                                .connectivity(
                                    .networkConnectionLost
                                )
                            )
                        ),
                        certainty:
                            .deliveryUnknown
                    )
            )
        let checking =
            presentation(
                isResolved: true,
                phase: .checkingGitLab,
                desiredResolved: true
            )
        let retry =
            presentation(
                isResolved: false,
                phase: .retryAvailable,
                desiredResolved: true
            )

        #expect(unknown.action == .checkGitLab)
        #expect(
            unknown.actionTitle
                == "Check GitLab"
        )
        #expect(
            unknown.statusTitle
                == "Resolution not confirmed"
        )
        #expect(unknown.isActionEnabled)

        #expect(checking.action == nil)
        #expect(
            checking.actionTitle
                == "Checking GitLab…"
        )
        #expect(checking.showsProgress)

        #expect(retry.action == .retry)
        #expect(
            retry.actionTitle
                == "Retry resolve"
        )
        #expect(
            retry.statusTitle
                == "Still unresolved"
        )
    }

    @Test("Uses safe read-only and permission-denied wording")
    func presentsAccessFailures() {
        let readOnly =
            GitLabDiscussionResolutionPresentation(
                status:
                    GitLabDiscussionResolutionStatus(
                        isResolved: false,
                        phase: .idle,
                        desiredResolved: nil,
                        resolvedBy: nil,
                        resolvedAt: nil,
                        failure: nil
                    ),
                apiAccess: .readOnly,
                discussionID: "thread"
            )
        let denied =
            presentation(
                isResolved: false,
                phase: .rejected,
                desiredResolved: true,
                failure:
                    .mutation(
                        .request(
                            .api(.forbidden)
                        ),
                        certainty:
                            .rejected
                    )
            )

        #expect(readOnly.action == nil)
        #expect(
            readOnly.actionTitle
                == "Read-only"
        )
        #expect(
            readOnly.failureMessage
                == "This account has read-only API access."
        )
        #expect(
            readOnly
                .showsUnavailableAccessLabel
        )
        #expect(!readOnly.isActionEnabled)

        #expect(denied.action == .toggle)
        #expect(
            denied.failureMessage
                == "GitLab did not allow this thread change."
        )
        #expect(
            !denied
                .showsUnavailableAccessLabel
        )
        #expect(denied.isActionEnabled)
    }

    @Test("Provides stable accessible resolution controls")
    func presentsAccessibility() {
        let resolved =
            presentation(
                isResolved: true,
                phase: .idle
            )
        let unknown =
            presentation(
                isResolved: false,
                phase: .deliveryUnknown,
                desiredResolved: false
            )

        #expect(
            resolved.accessibilityLabel
                == "Reopen thread"
        )
        #expect(
            resolved.accessibilityValue
                == "Resolved"
        )
        #expect(
            resolved.accessibilityHint
                == "Reopens this discussion on GitLab."
        )
        #expect(
            resolved.accessibilityIdentifier
                == "discussion.resolution.thread"
        )

        #expect(
            unknown.accessibilityLabel
                == "Check thread resolution on GitLab"
        )
        #expect(
            unknown.accessibilityValue
                == "Reopen not confirmed"
        )
        #expect(
            unknown.accessibilityHint
                == "Checks GitLab without sending another change."
        )
    }

    private func presentation(
        isResolved: Bool,
        phase:
            GitLabDiscussionResolutionPhase,
        desiredResolved: Bool? = nil,
        failure:
            GitLabDiscussionResolutionFailure?
            = nil
    ) -> GitLabDiscussionResolutionPresentation {
        GitLabDiscussionResolutionPresentation(
            status:
                GitLabDiscussionResolutionStatus(
                    isResolved: isResolved,
                    phase: phase,
                    desiredResolved:
                        desiredResolved,
                    resolvedBy: nil,
                    resolvedAt: nil,
                    failure: failure
                ),
            apiAccess: .readWrite,
            discussionID: "thread"
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
