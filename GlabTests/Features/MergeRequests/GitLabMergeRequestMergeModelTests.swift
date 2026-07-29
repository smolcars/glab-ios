import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request merge model")
@MainActor
struct GitLabMergeRequestMergeModelTests {
    @Test("Preflights before presenting an exact confirmation")
    func preflightsConfirmation() async throws {
        let fixture = try fixture()

        await fixture.model.request(
            .mergeNow
        )

        #expect(
            await fixture.service
                .preflightCount == 1
        )
        #expect(
            fixture.model.confirmation?
                .headSHA
                == "fresh-head-sha"
        )
        #expect(
            fixture.model.confirmation?
                .targetBranch == "main"
        )
        #expect(
            fixture.state.events
                == [
                    "mergeRequest",
                    "approvals",
                ]
        )
    }

    @Test("Merges once with the confirmed SHA and reconciles")
    func mergesAndReconciles() async throws {
        let merged =
            mergeRequest(
                state: "merged",
                detailedStatus: "not_open"
            )
        let fixture = try fixture(
            mergeResponse: merged,
            preflights: [
                preflight(),
                preflight(
                    mergeRequest: merged
                ),
            ]
        )

        await fixture.model.request(
            .mergeNow
        )
        await fixture.model.confirm()

        #expect(
            await fixture.service
                .mergeCount == 1
        )
        #expect(
            await fixture.service
                .receivedSHA
                == "fresh-head-sha"
        )
        #expect(
            await fixture.service
                .receivedAction
                == .mergeNow
        )
        #expect(
            fixture.state.mergeRequest?
                .stateKind == .merged
        )
        #expect(fixture.model.failure == nil)
        #expect(
            fixture.state.editedCount == 1
        )
    }

    @Test("Auto-merge reconciles an authoritative pending request")
    func setsAutoMerge() async throws {
        let pending =
            mergeRequest(
                detailedStatus:
                    "ci_still_running",
                pipelineStatus: "running",
                mergeWhenPipelineSucceeds:
                    true
            )
        let fixture = try fixture(
            initial:
                mergeRequest(
                    detailedStatus:
                        "ci_still_running",
                    pipelineStatus:
                        "running"
                ),
            mergeResponse: pending,
            preflights: [
                preflight(
                    mergeRequest:
                        mergeRequest(
                            detailedStatus:
                                "ci_still_running",
                            pipelineStatus:
                                "running"
                        )
                ),
                preflight(
                    mergeRequest: pending
                ),
            ]
        )

        await fixture.model.request(
            .autoMerge
        )
        await fixture.model.confirm()

        #expect(
            await fixture.service
                .receivedAction
                == .autoMerge
        )
        #expect(
            fixture.state.mergeRequest?
                .mergeWhenPipelineSucceeds
                == true
        )
        #expect(fixture.model.failure == nil)
    }

    @Test("A changed rendered SHA invalidates confirmation")
    func rejectsStaleRenderedSHA() async throws {
        let fixture = try fixture()
        await fixture.model.request(
            .mergeNow
        )
        fixture.state.mergeRequest =
            mergeRequest(
                sha: "newer-head-sha"
            )

        await fixture.model.confirm()

        #expect(
            fixture.model.failure
                == .staleRevision
        )
        #expect(
            await fixture.service
                .mergeCount == 0
        )
    }

    @Test("Cancellation and rapid taps never duplicate delivery")
    func cancellationAndRapidTaps() async throws {
        let fixture = try fixture()
        await fixture.model.request(
            .mergeNow
        )
        await fixture.model.request(
            .mergeNow
        )

        #expect(
            await fixture.service
                .preflightCount == 1
        )
        fixture.model.dismissConfirmation()
        await fixture.model.confirm()
        #expect(
            await fixture.service
                .mergeCount == 0
        )
    }

    @Test("Unknown delivery trusts an authoritative merged refresh")
    func reconcilesUnknownDelivery()
        async throws
    {
        let error =
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            )
        let merged =
            mergeRequest(
                state: "merged",
                detailedStatus: "not_open"
            )
        let fixture = try fixture(
            mutationError: error,
            preflights: [
                preflight(),
                preflight(
                    mergeRequest: merged
                ),
            ]
        )

        await fixture.model.request(
            .mergeNow
        )
        await fixture.model.confirm()

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.state.mergeRequest?
                .stateKind == .merged
        )
        #expect(
            fixture.state.editedCount == 1
        )
    }

    @Test("Unknown delivery reports a verified not-applied state")
    func reportsNotApplied() async throws {
        let error =
            GitLabSessionClientError.api(
                .connectivity(
                    .networkConnectionLost
                )
            )
        let fixture = try fixture(
            mutationError: error,
            preflights: [
                preflight(),
                preflight(),
            ]
        )

        await fixture.model.request(
            .mergeNow
        )
        await fixture.model.confirm()

        #expect(
            fixture.model.failure
                == .notApplied
        )
        #expect(
            await fixture.service
                .mergeCount == 1
        )
    }

    @Test("Stale SHA and permission rejection map safely")
    func mapsExplicitRejection() async throws {
        let stale = try fixture(
            mutationError:
                .api(
                    .validation(
                        statusCode: 409
                    )
                ),
            preflights: [
                preflight(),
                preflight(),
            ]
        )
        await stale.model.request(.mergeNow)
        await stale.model.confirm()
        #expect(
            stale.model.failure
                == .staleRevision
        )

        let forbidden = try fixture(
            mutationError:
                .api(.forbidden)
        )
        await forbidden.model.request(
            .mergeNow
        )
        await forbidden.model.confirm()
        #expect(
            forbidden.model.failure
                == .permissionDenied
        )
    }

    @Test("An authoritative merged state wins over a stale-SHA rejection")
    func reconcilesConcurrentMergeAfterStaleSHA()
        async throws
    {
        let merged =
            mergeRequest(
                state: "merged",
                detailedStatus: "not_open"
            )
        let fixture = try fixture(
            mutationError:
                .api(
                    .validation(
                        statusCode: 409
                    )
                ),
            preflights: [
                preflight(),
                preflight(
                    mergeRequest: merged
                ),
            ]
        )

        await fixture.model.request(
            .mergeNow
        )
        await fixture.model.confirm()

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.state.mergeRequest?
                .stateKind == .merged
        )
        #expect(
            fixture.state.editedCount == 1
        )
    }

    @Test("Account replacement prevents delivery")
    func rejectsAccountReplacement()
        async throws
    {
        let fixture = try fixture()
        await fixture.model.request(
            .mergeNow
        )
        fixture.state.isAccountCurrent =
            false

        await fixture.model.confirm()

        #expect(
            fixture.model.failure
                == .accountChanged
        )
        #expect(
            await fixture.service
                .mergeCount == 0
        )
    }

    private func fixture(
        apiAccess:
            GitLabAPIAccess = .readWrite,
        initial:
            GitLabMergeRequest? = nil,
        mergeResponse:
            GitLabMergeRequest? = nil,
        mutationError:
            GitLabSessionClientError? = nil,
        preflights:
            [GitLabMergeRequestMergePreflight]? =
                nil
    ) throws -> Fixture {
        let initial =
            initial ?? mergeRequest()
        let state =
            MergeRequestMergeState(
                mergeRequest: initial,
                approvalSummary:
                    approvalSummary()
            )
        let service =
            RecordingMergeRequestMergeService(
                preflights:
                    preflights
                    ?? [preflight()],
                mergeResponse:
                    mergeResponse
                    ?? mergeRequest(
                        state: "merged",
                        detailedStatus:
                            "not_open"
                    ),
                mutationError:
                    mutationError
            )
        let model =
            GitLabMergeRequestMergeModel(
                accountID:
                    GitLabAccountID(
                        host:
                            try GitLabHost(
                                "gitlab.example.com"
                            ),
                        userID: 7
                    ),
                route: initial.route,
                apiAccess: apiAccess,
                service: service,
                currentMergeRequest: {
                    state.mergeRequest
                },
                currentApprovalSummary: {
                    state.approvalSummary
                },
                isAccountCurrent: {
                    state.isAccountCurrent
                },
                onMergeRequestReconciled: {
                    state.mergeRequest = $0
                    state.events.append(
                        "mergeRequest"
                    )
                },
                onApprovalSummaryReconciled: {
                    state.approvalSummary = $0
                    state.events.append(
                        "approvals"
                    )
                },
                onResourceEdited: {
                    guard
                        case let .mergeRequest(
                            mergeRequest
                        ) = $0
                    else {
                        return
                    }
                    state.mergeRequest =
                        mergeRequest
                    state.editedCount += 1
                }
            )
        return Fixture(
            model: model,
            service: service,
            state: state
        )
    }

    private func preflight(
        mergeRequest:
            GitLabMergeRequest? = nil
    ) -> GitLabMergeRequestMergePreflight {
        GitLabMergeRequestMergePreflight(
            mergeRequest:
                mergeRequest
                ?? self.mergeRequest(),
            approvalSummary:
                approvalSummary()
        )
    }

    private func approvalSummary()
        -> GitLabMergeRequestApprovalSummary
    {
        GitLabMergeRequestApprovalSummary(
            approved: true,
            approvalsRequired: 1,
            approvalsLeft: 0,
            approvedBy: []
        )
    }

    private func mergeRequest(
        state: String = "opened",
        sha: String = "fresh-head-sha",
        detailedStatus:
            String = "mergeable",
        pipelineStatus:
            String = "success",
        mergeWhenPipelineSucceeds:
            Bool = false
    ) -> GitLabMergeRequest {
        makeTestMergeRequest(
            title: "Ship safe merge",
            state: state,
            draft: false,
            sourceBranch: "feature/safe-merge",
            targetBranch: "main",
            sha: sha,
            detailedMergeStatus:
                detailedStatus,
            hasConflicts: false,
            blockingDiscussionsResolved:
                true,
            headPipeline:
                GitLabMergeRequestHeadPipeline(
                    id: 501,
                    status: pipelineStatus,
                    webURL: nil
                ),
            mergeWhenPipelineSucceeds:
                mergeWhenPipelineSucceeds,
            userCanMerge: true
        )
    }

    private struct Fixture {
        let model:
            GitLabMergeRequestMergeModel
        let service:
            RecordingMergeRequestMergeService
        let state:
            MergeRequestMergeState
    }
}

@MainActor
private final class MergeRequestMergeState {
    var mergeRequest: GitLabMergeRequest?
    var approvalSummary:
        GitLabMergeRequestApprovalSummary?
    var isAccountCurrent = true
    var editedCount = 0
    var events: [String] = []

    init(
        mergeRequest: GitLabMergeRequest?,
        approvalSummary:
            GitLabMergeRequestApprovalSummary?
    ) {
        self.mergeRequest = mergeRequest
        self.approvalSummary =
            approvalSummary
    }
}

private actor
    RecordingMergeRequestMergeService:
    GitLabMergeRequestMergeServing
{
    private var preflights:
        [GitLabMergeRequestMergePreflight]
    private let mergeResponse:
        GitLabMergeRequest
    private let mutationError:
        GitLabSessionClientError?
    private(set) var preflightCount = 0
    private(set) var mergeCount = 0
    private(set) var receivedSHA: String?
    private(set) var receivedAction:
        GitLabMergeRequestMergeAction?

    init(
        preflights:
            [GitLabMergeRequestMergePreflight],
        mergeResponse:
            GitLabMergeRequest,
        mutationError:
            GitLabSessionClientError?
    ) {
        self.preflights = preflights
        self.mergeResponse = mergeResponse
        self.mutationError =
            mutationError
    }

    func preflight(
        at route: GitLabMergeRequestRoute
    ) throws(GitLabSessionClientError)
        -> GitLabMergeRequestMergePreflight
    {
        preflightCount += 1
        guard !preflights.isEmpty else {
            throw .api(.invalidResponse)
        }
        return preflights.removeFirst()
    }

    func merge(
        at route: GitLabMergeRequestRoute,
        sha: String,
        action:
            GitLabMergeRequestMergeAction
    ) throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        mergeCount += 1
        receivedSHA = sha
        receivedAction = action
        if let mutationError {
            throw mutationError
        }
        return mergeResponse
    }
}
