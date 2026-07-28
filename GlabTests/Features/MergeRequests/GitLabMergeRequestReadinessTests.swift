import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request readiness")
struct GitLabMergeRequestReadinessTests {
    @Test("Decodes complete and partial approval responses")
    func decodesApprovalResponses() throws {
        let complete = try decodeApprovalSummary(
            """
            {
              "approved": false,
              "approvals_required": 2,
              "approvals_left": 1,
              "approved_by": [
                {
                  "user": {
                    "id": 1,
                    "username": "octocat",
                    "name": "The Octocat",
                    "avatar_url": null,
                    "web_url": "https://gitlab.example.com/octocat"
                  }
                }
              ]
            }
            """
        )
        let partial = try decodeApprovalSummary(
            "{}"
        )

        #expect(complete.approved == false)
        #expect(complete.approvalsRequired == 2)
        #expect(complete.approvalsLeft == 1)
        #expect(complete.approvedBy.count == 1)
        #expect(partial.approved == nil)
        #expect(partial.approvalsRequired == nil)
        #expect(partial.approvalsLeft == nil)
        #expect(partial.approvedBy.isEmpty)
    }

    @Test("Requires every known component before reporting ready")
    func reportsReady() {
        let readiness = makeReadiness()

        #expect(readiness.overall == .ready)
        #expect(
            readiness.pipeline.state
                == .satisfied
        )
        #expect(
            readiness.approvals.state
                == .satisfied
        )
        #expect(
            readiness.conflicts.state
                == .satisfied
        )
        #expect(
            readiness.discussions.state
                == .satisfied
        )
        #expect(
            readiness.reviewState.state
                == .satisfied
        )
        #expect(
            readiness.checks.map(\.kind)
                == [
                    .pipeline,
                    .approvals,
                    .conflicts,
                    .discussions,
                    .reviewState,
                ]
        )
    }

    @Test("Provides complete stable accessibility labels")
    func providesAccessibilityLabels() {
        let readiness = makeReadiness()

        #expect(
            readiness.accessibilityLabel
                == "Merge readiness, Ready to merge"
        )
        #expect(
            readiness.pipeline.accessibilityLabel
                == "Pipeline, Passed. The head pipeline succeeded."
        )
        #expect(
            readiness.checks.map(\.accessibilityLabel)
                .allSatisfy {
                    !$0.isEmpty
                }
        )
    }

    @Test(
        "Maps transient detailed statuses to pending",
        arguments: [
            "approvals_syncing",
            "checking",
            "ci_still_running",
            "preparing",
            "unchecked",
        ]
    )
    func mapsTransientStatus(
        status: String
    ) {
        let readiness = makeReadiness(
            detailedStatus: status
        )

        #expect(readiness.overall == .pending)
    }

    @Test(
        "Maps documented merge blockers",
        arguments: [
            "ci_must_pass",
            "commits_status",
            "conflict",
            "discussions_not_resolved",
            "draft_status",
            "jira_association_missing",
            "merge_request_blocked",
            "merge_time",
            "need_rebase",
            "not_approved",
            "not_open",
            "requested_changes",
            "security_policy_pipeline_check",
            "security_policy_violations",
            "status_checks_must_pass",
            "locked_paths",
            "locked_lfs_files",
            "title_regex",
        ]
    )
    func mapsBlockingStatus(
        status: String
    ) {
        let readiness = makeReadiness(
            detailedStatus: status
        )

        #expect(readiness.overall == .blocked)
    }

    @Test(
        "Maps pipeline states without assuming future values",
        arguments: [
            (
                "success",
                GitLabMergeRequestReadinessCheckState
                    .satisfied,
                "Passed"
            ),
            (
                "running",
                .pending,
                "Running"
            ),
            (
                "pending",
                .pending,
                "Pending"
            ),
            (
                "failed",
                .blocked,
                "Failed"
            ),
            (
                "canceled",
                .blocked,
                "Canceled"
            ),
            (
                "skipped",
                .satisfied,
                "Skipped"
            ),
            (
                "manual",
                .pending,
                "Manual action"
            ),
            (
                "future_pipeline",
                .unknown,
                "Unknown pipeline status"
            ),
        ]
    )
    func mapsPipeline(
        status: String,
        state:
            GitLabMergeRequestReadinessCheckState,
        title: String
    ) {
        let readiness = makeReadiness(
            pipelineStatus: status
        )

        #expect(
            readiness.pipeline.state
                == state
        )
        #expect(readiness.pipeline.title == title)
    }

    @Test("Treats a missing visible pipeline as neutral")
    func mapsMissingPipeline() {
        let readiness = makeReadiness(
            pipelineStatus: nil
        )

        #expect(
            readiness.pipeline.state
                == .notRequired
        )
        #expect(
            readiness.pipeline.title
                == "No visible pipeline"
        )
        #expect(readiness.overall == .ready)
    }

    @Test("Supports Community Edition approval semantics")
    func mapsNoApprovalRequirement() {
        let readiness = makeReadiness(
            approvals:
                .available(
                    GitLabMergeRequestApprovalSummary(
                        approved: false,
                        approvalsRequired: 0,
                        approvalsLeft: 0,
                        approvedBy: []
                    )
                )
        )

        #expect(
            readiness.approvals.state
                == .notRequired
        )
        #expect(
            readiness.approvals.title
                == "No approval required"
        )
        #expect(readiness.overall == .ready)
    }

    @Test("Preserves the remaining approval count")
    func mapsPendingApprovals() {
        let readiness = makeReadiness(
            detailedStatus: "not_approved",
            approvals:
                .available(
                    GitLabMergeRequestApprovalSummary(
                        approved: false,
                        approvalsRequired: 3,
                        approvalsLeft: 2,
                        approvedBy: []
                    )
                )
        )

        #expect(
            readiness.approvals.state
                == .blocked
        )
        #expect(
            readiness.approvals.title
                == "2 approvals remaining"
        )
        #expect(readiness.overall == .blocked)
    }

    @Test(
        "Missing and failed approval data never produce a ready verdict",
        arguments: [
            GitLabResourceDetailState<
                GitLabMergeRequestApprovalAvailability
            >.idle,
            .loading,
            .loaded(.unavailable),
            .failed(
                .api(
                    .server(statusCode: 503)
                )
            ),
        ]
    )
    func preservesApprovalUncertainty(
        state:
            GitLabResourceDetailState<
                GitLabMergeRequestApprovalAvailability
            >
    ) {
        let readiness = makeReadiness(
            approvalState: state
        )

        #expect(readiness.overall != .ready)
        #expect(
            readiness.approvals.state
                == (
                    state == .idle
                        || state == .loading
                        ? .pending
                        : .unavailable
                )
        )
    }

    @Test("Explicit blockers override a nominal mergeable status")
    func blocksInconsistentMergeableResponse() {
        let conflict = makeReadiness(
            hasConflicts: true
        )
        let unresolved = makeReadiness(
            discussionsResolved: false
        )
        let draft = makeReadiness(
            draft: true
        )
        let failedPipeline = makeReadiness(
            pipelineStatus: "failed"
        )
        let missingApproval = makeReadiness(
            approvals:
                .available(
                    GitLabMergeRequestApprovalSummary(
                        approved: false,
                        approvalsRequired: 1,
                        approvalsLeft: 1,
                        approvedBy: []
                    )
                )
        )

        #expect(conflict.overall == .blocked)
        #expect(unresolved.overall == .blocked)
        #expect(draft.overall == .blocked)
        #expect(
            failedPipeline.overall == .blocked
        )
        #expect(
            missingApproval.overall == .blocked
        )
    }

    @Test("Refresh uncertainty prevents an optimistic ready verdict")
    func preventsReadyAfterRefreshFailure() {
        let staleReady = makeReadiness(
            hasRefreshFailure: true
        )
        let staleBlocked = makeReadiness(
            detailedStatus: "not_approved",
            approvals:
                .available(
                    GitLabMergeRequestApprovalSummary(
                        approved: false,
                        approvalsRequired: 1,
                        approvalsLeft: 1,
                        approvedBy: []
                    )
                ),
            hasRefreshFailure: true
        )

        #expect(staleReady.overall == .unknown)
        #expect(
            staleReady.approvals.state
                == .satisfied
        )
        #expect(
            staleReady.pipeline.state
                == .satisfied
        )
        #expect(staleBlocked.overall == .blocked)
    }

    @Test("Unknown and absent fields remain unknown")
    func preservesUnknownState() {
        let future = makeReadiness(
            detailedStatus: "future_status"
        )
        let missing = GitLabMergeRequestReadiness(
            mergeRequest:
                makeTestMergeRequest(
                    draft: nil,
                    legacyWorkInProgress: nil
                ),
            approvalState:
                .loaded(
                    .available(
                        approvedSummary
                    )
                )
        )

        #expect(future.overall == .unknown)
        #expect(missing.overall == .unknown)
        #expect(
            missing.conflicts.state
                == .unknown
        )
        #expect(
            missing.discussions.state
                == .unknown
        )
        #expect(
            missing.reviewState.state
                == .unknown
        )
    }

    @Test("Preserves an unknown merge request lifecycle state")
    func preservesUnknownLifecycle() {
        let readiness = GitLabMergeRequestReadiness(
            mergeRequest:
                makeTestMergeRequest(
                    state: "future_state",
                    draft: false,
                    detailedMergeStatus:
                        "mergeable",
                    hasConflicts: false,
                    blockingDiscussionsResolved:
                        true,
                    headPipeline:
                        GitLabMergeRequestHeadPipeline(
                            id: 501,
                            status: "success",
                            webURL: nil
                        )
                ),
            approvalState:
                .loaded(
                    .available(
                        approvedSummary
                    )
                )
        )

        #expect(readiness.overall == .unknown)
    }

    @Test("Exposes only a validated pipeline destination")
    func validatesPipelineDestination() {
        let safe = makeReadiness()
        let unsafe = makeReadiness(
            pipelineURL:
                URL(
                    string:
                        "http://gitlab.example.com/pipeline"
                )
        )

        #expect(
            safe.pipeline.destination != nil
        )
        #expect(
            unsafe.pipeline.destination == nil
        )
    }

    private func makeReadiness(
        detailedStatus: String = "mergeable",
        hasConflicts: Bool? = false,
        discussionsResolved: Bool? = true,
        draft: Bool? = false,
        pipelineStatus: String? = "success",
        pipelineURL: URL? = URL(
            string:
                "https://gitlab.example.com/group/project/-/pipelines/501"
        ),
        approvals:
            GitLabMergeRequestApprovalAvailability? =
                nil,
        approvalState:
            GitLabResourceDetailState<
                GitLabMergeRequestApprovalAvailability
            >? = nil,
        hasRefreshFailure: Bool = false
    ) -> GitLabMergeRequestReadiness {
        GitLabMergeRequestReadiness(
            mergeRequest:
                makeTestMergeRequest(
                    draft: draft,
                    detailedMergeStatus:
                        detailedStatus,
                    hasConflicts:
                        hasConflicts,
                    blockingDiscussionsResolved:
                        discussionsResolved,
                    headPipeline:
                        pipelineStatus.map {
                            GitLabMergeRequestHeadPipeline(
                                id: 501,
                                status: $0,
                                webURL:
                                    pipelineURL
                            )
                        }
                ),
            approvalState:
                approvalState
                ?? .loaded(
                    approvals
                        ?? .available(
                            approvedSummary
                        )
                ),
            hasRefreshFailure:
                hasRefreshFailure
        )
    }

    private var approvedSummary:
        GitLabMergeRequestApprovalSummary
    {
        GitLabMergeRequestApprovalSummary(
            approved: true,
            approvalsRequired: 2,
            approvalsLeft: 0,
            approvedBy: [
                GitLabMergeRequestApproval(
                    user: makeTestAPIUser()
                ),
            ]
        )
    }

    private func decodeApprovalSummary(
        _ json: String
    ) throws -> GitLabMergeRequestApprovalSummary {
        try JSONDecoder().decode(
            GitLabMergeRequestApprovalSummary.self,
            from: Data(json.utf8)
        )
    }
}
