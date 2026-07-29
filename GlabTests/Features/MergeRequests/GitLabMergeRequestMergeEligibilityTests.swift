import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request merge eligibility")
struct GitLabMergeRequestMergeEligibilityTests {
    @Test("Offers immediate merge only for authoritative ready state")
    func offersImmediateMerge() {
        let mergeRequest = Self.readyMergeRequest()
        let readiness = Self.readiness(
            for: mergeRequest
        )

        #expect(readiness.overall == .ready)
        #expect(
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness: readiness,
                apiAccess: .readWrite
            ) == .mergeNow
        )
    }

    @Test("Offers auto-merge only for a recognized pending pipeline")
    func offersAutoMerge() {
        let mergeRequest = Self.readyMergeRequest(
            detailedStatus:
                "ci_still_running",
            pipelineStatus: "running"
        )
        let readiness = Self.readiness(
            for: mergeRequest
        )

        #expect(readiness.overall == .pending)
        #expect(
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness: readiness,
                apiAccess: .readWrite
            ) == .autoMerge
        )
    }

    @Test("Recognizes an authoritative pending auto-merge")
    func recognizesExistingAutoMerge() {
        let mergeRequest = Self.readyMergeRequest(
            detailedStatus:
                "ci_still_running",
            pipelineStatus: "running",
            mergeWhenPipelineSucceeds: true
        )

        #expect(
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readWrite
            ) == .alreadyAutoMerging
        )
    }

    @Test(
        "Blocks locally unsafe merge states",
        arguments: [
            (
                Self.readyMergeRequest(
                    draft: true
                ),
                GitLabMergeRequestMergeBlockReason
                    .draft
            ),
            (
                Self.readyMergeRequest(
                    state: "closed"
                ),
                .notOpen
            ),
            (
                Self.readyMergeRequest(
                    hasConflicts: true
                ),
                .conflict
            ),
            (
                Self.readyMergeRequest(
                    blockingDiscussionsResolved:
                        false
                ),
                .unresolvedDiscussions
            ),
            (
                Self.readyMergeRequest(
                    userCanMerge: false
                ),
                .permissionDenied
            ),
            (
                Self.readyMergeRequest(
                    sha: " "
                ),
                .missingHeadSHA
            ),
        ]
    )
    func blocksUnsafeState(
        mergeRequest: GitLabMergeRequest,
        expected:
            GitLabMergeRequestMergeBlockReason
    ) {
        let eligibility =
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readWrite
            )

        guard
            case let .blocked(reasons) =
                eligibility
        else {
            Issue.record(
                "Expected blocked eligibility"
            )
            return
        }
        #expect(reasons.contains(expected))
    }

    @Test("Blocks write actions for a read-only account")
    func blocksReadOnlyAccount() {
        let mergeRequest = Self.readyMergeRequest()
        let eligibility =
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readOnly
            )

        #expect(
            eligibility
                == .blocked([.readOnly])
        )
    }

    @Test("Waits for asynchronous mergeability checks")
    func waitsForMergeabilityCheck() {
        let mergeRequest = Self.readyMergeRequest(
            detailedStatus: "checking"
        )

        #expect(
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readWrite
            ) == .checking
        )
    }

    @Test("Does not infer auto-merge from a failed pipeline")
    func blocksFailedPipeline() {
        let mergeRequest = Self.readyMergeRequest(
            detailedStatus: "ci_must_pass",
            pipelineStatus: "failed"
        )
        let eligibility =
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readWrite
            )

        guard
            case let .blocked(reasons) =
                eligibility
        else {
            Issue.record(
                "Expected failed pipeline to block"
            )
            return
        }
        #expect(reasons.contains(.pipeline))
    }

    @Test("Treats a future status as unavailable")
    func futureStatusIsUnavailable() {
        let mergeRequest = Self.readyMergeRequest(
            detailedStatus:
                "future_merge_policy"
        )

        #expect(
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readWrite
            ) == .unavailable
        )
    }

    @Test("An older response without user permission projection remains eligible")
    func supportsOmittedUserPermission() {
        let mergeRequest =
            Self.readyMergeRequest(
                userCanMerge: nil
            )

        #expect(
            GitLabMergeRequestMergeEligibility(
                mergeRequest: mergeRequest,
                readiness:
                    Self.readiness(
                        for: mergeRequest
                    ),
                apiAccess: .readWrite
            ) == .mergeNow
        )
    }
}

private extension
    GitLabMergeRequestMergeEligibilityTests
{
    nonisolated static func readyMergeRequest(
        state: String = "opened",
        draft: Bool? = false,
        sha: String? = "fresh-head-sha",
        detailedStatus:
            String = "mergeable",
        hasConflicts: Bool? = false,
        blockingDiscussionsResolved:
            Bool? = true,
        pipelineStatus:
            String = "success",
        mergeWhenPipelineSucceeds:
            Bool? = false,
        userCanMerge: Bool? = true
    ) -> GitLabMergeRequest {
        makeTestMergeRequest(
            state: state,
            draft: draft,
            sha: sha,
            detailedMergeStatus:
                detailedStatus,
            hasConflicts: hasConflicts,
            blockingDiscussionsResolved:
                blockingDiscussionsResolved,
            headPipeline:
                GitLabMergeRequestHeadPipeline(
                    id: 501,
                    status: pipelineStatus,
                    webURL: nil
                ),
            mergeWhenPipelineSucceeds:
                mergeWhenPipelineSucceeds,
            userCanMerge: userCanMerge
        )
    }

    nonisolated static func readiness(
        for mergeRequest:
            GitLabMergeRequest
    ) -> GitLabMergeRequestReadiness {
        GitLabMergeRequestReadiness(
            mergeRequest: mergeRequest,
            approvalState:
                .loaded(
                    .available(
                        GitLabMergeRequestApprovalSummary(
                            approved: true,
                            approvalsRequired: 1,
                            approvalsLeft: 0,
                            approvedBy: []
                        )
                    )
                )
        )
    }
}
