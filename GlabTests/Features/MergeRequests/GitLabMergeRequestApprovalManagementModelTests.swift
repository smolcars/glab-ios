import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab merge request approval management model")
struct GitLabMergeRequestApprovalManagementModelTests {
    @Test("Loads cached then network approval details independently")
    func loadsApprovalDetailsIndependently()
        async
    {
        let cached =
            makeApprovalDetails(
                ruleName: "Cached rule"
            )
        let network =
            makeApprovalDetails(
                ruleName: "Network rule"
            )
        let service =
            RecordingApprovalManagementService(
                detailsEventResults: [
                    .success([
                        makeApprovalDetailsEvent(
                            cached,
                            source:
                                .cache(.stale)
                        ),
                        makeApprovalDetailsEvent(
                            network,
                            source: .network
                        ),
                    ]),
                ]
            )
        let fixture = makeFixture(
            service: service
        )
        let mergeRequest =
            fixture.currentMergeRequest
        let summary =
            fixture.currentSummary

        await fixture.model
            .loadDetailsIfNeeded()

        #expect(
            fixture.model.detailsModel.state
                == .loaded(
                    .available(network)
                )
        )
        #expect(
            fixture.model
                .detailsModel
                .resourceSource
                == .network
        )
        #expect(
            await service
                .detailsRefreshBehaviors
                == [.ifStale]
        )
        #expect(
            fixture.currentMergeRequest
                == mergeRequest
        )
        #expect(
            fixture.currentSummary == summary
        )
        #expect(fixture.model.failure == nil)
    }

    @Test("Failed detail refresh retains content and basic owners")
    func retainsDetailsAfterRefreshFailure()
        async
    {
        let details =
            makeApprovalDetails(
                ruleName: "Security"
            )
        let error =
            GitLabSessionClientError
                .api(
                    .server(statusCode: 503)
                )
        let service =
            RecordingApprovalManagementService(
                detailsEventResults: [
                    .success([
                        makeApprovalDetailsEvent(
                            details,
                            source: .network
                        ),
                    ]),
                    .failure(error),
                ]
            )
        let fixture = makeFixture(
            service: service
        )
        let mergeRequest =
            fixture.currentMergeRequest
        let summary =
            fixture.currentSummary

        await fixture.model
            .loadDetailsIfNeeded()
        await fixture.model
            .refreshDetails()

        #expect(
            fixture.model.detailsModel.state
                == .loaded(
                    .available(details)
                )
        )
        #expect(
            fixture.model
                .detailsModel
                .refreshError == error
        )
        #expect(
            await service
                .detailsRefreshBehaviors
                == [.ifStale, .always]
        )
        #expect(
            fixture.currentMergeRequest
                == mergeRequest
        )
        #expect(
            fixture.currentSummary == summary
        )
        #expect(fixture.model.failure == nil)
    }

    @Test("Applied approval refreshes details without replacing basic success")
    func refreshesDetailsAfterApproval()
        async
    {
        let approved =
            makeApprovalSummary(
                approvedUserIDs: [7]
            )
        let details =
            makeApprovalDetails(
                ruleName: "Before approval"
            )
        let error =
            GitLabSessionClientError
                .api(
                    .server(statusCode: 503)
                )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(makeApprovalSummary()),
                    .success(approved),
                ],
                approveResults: [
                    .success(approved),
                ],
                detailsEventResults: [
                    .success([
                        makeApprovalDetailsEvent(
                            details,
                            source: .network
                        ),
                    ]),
                    .failure(error),
                ]
            )
        let fixture = makeFixture(
            service: service
        )
        await fixture.model
            .loadDetailsIfNeeded()

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.currentSummary == approved
        )
        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model.detailsModel.state
                == .loaded(
                    .available(details)
                )
        )
        #expect(
            fixture.model
                .detailsModel
                .refreshError == error
        )
        #expect(
            await service
                .detailsRefreshBehaviors
                == [.ifStale, .always]
        )
    }

    @Test("Detailed authentication failure remains independently actionable")
    func exposesDetailAuthenticationFailure()
        async
    {
        let error =
            GitLabSessionClientError
                .api(.unauthenticated)
        let service =
            RecordingApprovalManagementService(
                detailsEventResults: [
                    .failure(error),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        await fixture.model
            .loadDetailsIfNeeded()

        #expect(
            fixture.model.detailsModel.state
                == .failed(error)
        )
        #expect(
            fixture.model.authenticationFailure
                == error
        )
        #expect(fixture.model.failure == nil)
    }

    @Test("Approves the exact fresh head and reconciles authoritative reads")
    func approvesExactHead() async {
        let approved =
            makeApprovalSummary(
                approvedUserIDs: [7]
            )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(makeApprovalSummary()),
                    .success(approved),
                ],
                approveResults: [
                    .success(approved),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        #expect(
            fixture.model.confirmation?
                .action == .approve
        )

        await fixture.model.confirmAction()

        #expect(
            await service.approveSHAs
                == ["rendered-head"]
        )
        #expect(await service.unapproveCount == 0)
        #expect(
            fixture.currentSummary == approved
        )
        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model.hasUnresolvedMutation
                == false
        )
    }

    @Test("Unapproves only the current user on the same fresh head")
    func unapprovesCurrentUser() async {
        let approved =
            makeApprovalSummary(
                approvedUserIDs: [7, 9]
            )
        let remaining =
            makeApprovalSummary(
                approvedUserIDs: [9]
            )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(approved),
                    .success(remaining),
                ],
                unapproveResults: [
                    .success(remaining),
                ]
            )
        let fixture = makeFixture(
            service: service,
            summary: approved
        )

        fixture.model.requestUnapprove()
        await fixture.model.confirmAction()

        #expect(await service.unapproveCount == 1)
        #expect(await service.approveSHAs.isEmpty)
        #expect(
            fixture.currentSummary == remaining
        )
        #expect(fixture.model.failure == nil)
    }

    @Test("Blocks read-only and inapplicable actions before preflight")
    func blocksLocalInvalidActions() async {
        let service =
            RecordingApprovalManagementService()
        let readOnly = makeFixture(
            service: service,
            apiAccess: .readOnly
        )

        readOnly.model.requestApprove()

        #expect(
            readOnly.model.failure == .readOnly
        )
        #expect(
            readOnly.model.confirmation == nil
        )

        let alreadyApproved = makeFixture(
            service: service,
            summary:
                makeApprovalSummary(
                    approvedUserIDs: [7]
                )
        )
        alreadyApproved.model.requestApprove()
        #expect(
            alreadyApproved.model.confirmation
                == nil
        )

        let notApproved = makeFixture(
            service: service
        )
        notApproved.model.requestUnapprove()
        #expect(
            notApproved.model.confirmation
                == nil
        )
        #expect(await service.mergeRequestCount == 0)
    }

    @Test("Rejects a fresh head change without sending a write")
    func rejectsChangedHead() async {
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(
                        makeMergeRequest(
                            headSHA: "new-head"
                        )
                    ),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .staleRevision
        )
        #expect(await service.summaryCount == 0)
        #expect(await service.approveSHAs.isEmpty)
        #expect(
            fixture.currentMergeRequest?
                .diffHeadSHA == "new-head"
        )
    }

    @Test(
        "Blocks GitLab approval synchronization states",
        arguments: [
            "checking",
            " APPROVALS_SYNCING ",
        ]
    )
    func blocksSyncState(
        status: String
    ) async {
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(
                        makeMergeRequest(
                            detailedMergeStatus:
                                status
                        )
                    ),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .approvalSyncing
        )
        #expect(await service.summaryCount == 0)
        #expect(await service.approveSHAs.isEmpty)
    }

    @Test("Maps stale, permission, and GitLab reauthentication rejections")
    func mapsDefiniteRejections() async {
        let cases: [
            (
                GitLabSessionClientError,
                GitLabMergeRequestApprovalManagementFailure
            )
        ] = [
            (
                .api(
                    .validation(
                        statusCode: 409
                    )
                ),
                .staleRevision
            ),
            (
                .api(.forbidden),
                .permissionDenied
            ),
            (
                .api(.unauthenticated),
                .gitLabReauthenticationRequired
            ),
        ]

        for (error, expected) in cases {
            let service =
                RecordingApprovalManagementService(
                    mergeRequestResults: [
                        .success(
                            makeMergeRequest()
                        ),
                    ],
                    summaryResults: [
                        .success(
                            makeApprovalSummary()
                        ),
                    ],
                    approveResults: [
                        .failure(error),
                    ]
                )
            let fixture = makeFixture(
                service: service
            )

            fixture.model.requestApprove()
            await fixture.model
                .confirmAction()

            #expect(
                fixture.model.failure
                    == expected
            )
            #expect(
                fixture.model
                    .hasUnresolvedMutation
                    == false
            )
            #expect(
                fixture.model
                    .authenticationFailure
                    == nil
            )
        }
    }

    @Test("Treats an unapprove 401 as an account authentication failure")
    func exposesUnapproveAuthenticationFailure() async {
        let error =
            GitLabSessionClientError
                .api(.unauthenticated)
        let approvedSummary =
            makeApprovalSummary(
                approvedUserIDs: [7]
            )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(
                        makeMergeRequest()
                    ),
                ],
                summaryResults: [
                    .success(
                        approvedSummary
                    ),
                ],
                unapproveResults: [
                    .failure(error),
                ]
            )
        let fixture = makeFixture(
            service: service,
            summary: approvedSummary
        )

        fixture.model.requestUnapprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .rejected(error)
        )
        #expect(
            fixture.model
                .authenticationFailure
                == error
        )
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
        #expect(await service.unapproveCount == 1)
    }

    @Test("Rapid confirmations send only one approval")
    func ignoresRapidConfirmations() async {
        let approved =
            makeApprovalSummary(
                approvedUserIDs: [7]
            )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(makeApprovalSummary()),
                    .success(approved),
                ],
                approveResults: [
                    .success(approved),
                ]
            )
        let fixture = makeFixture(
            service: service
        )
        fixture.model.requestApprove()

        async let first: Void =
            fixture.model.confirmAction()
        async let second: Void =
            fixture.model.confirmAction()
        _ = await (first, second)

        #expect(
            await service.approveSHAs.count
                == 1
        )
    }

    @Test("Unknown approval delivery is reconciled explicitly")
    func reconcilesUnknownDelivery() async {
        let approved =
            makeApprovalSummary(
                approvedUserIDs: [7]
            )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(makeApprovalSummary()),
                    .success(approved),
                ],
                approveResults: [
                    .failure(
                        .api(
                            .server(
                                statusCode: 503
                            )
                        )
                    ),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .deliveryUnknown
        )
        #expect(
            fixture.model.hasUnresolvedMutation
        )

        await fixture.model.checkGitLab()

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
        #expect(
            fixture.currentSummary == approved
        )
        #expect(
            await service.approveSHAs
                == ["rendered-head"]
        )
    }

    @Test("An unapplied unknown delivery permits a new deliberate attempt")
    func permitsRetryAfterUnappliedCheck() async {
        let baseline =
            makeApprovalSummary()
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(baseline),
                    .success(baseline),
                ],
                approveResults: [
                    .failure(
                        .api(
                            .connectivity(
                                .networkConnectionLost
                            )
                        )
                    ),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()
        await fixture.model.checkGitLab()

        #expect(
            fixture.model.failure
                == .notApplied
        )
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )

        fixture.model.requestApprove()
        #expect(
            fixture.model.confirmation?
                .action == .approve
        )
    }

    @Test("A new commit makes an unresolved approval stale")
    func resetsUnknownIntentForNewHead() async {
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(
                        makeMergeRequest(
                            headSHA: "new-head"
                        )
                    ),
                ],
                summaryResults: [
                    .success(
                        makeApprovalSummary()
                    ),
                    .success(
                        makeApprovalSummary()
                    ),
                ],
                approveResults: [
                    .failure(
                        .api(.cancelled)
                    ),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()
        await fixture.model.checkGitLab()

        #expect(
            fixture.model.failure
                == .staleRevision
        )
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
    }

    @Test("Failed post-write reconciliation remains checkable")
    func retainsPostWriteReconciliation() async {
        let approved =
            makeApprovalSummary(
                approvedUserIDs: [7]
            )
        let failure =
            GitLabSessionClientError.api(
                .connectivity(
                    .notConnectedToInternet
                )
            )
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .failure(failure),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(
                        makeApprovalSummary()
                    ),
                    .success(approved),
                ],
                approveResults: [
                    .success(approved),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .reconciliation(failure)
        )
        #expect(
            fixture.model.hasUnresolvedMutation
        )

        await fixture.model.checkGitLab()

        #expect(fixture.model.failure == nil)
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
    }

    @Test("An account switch during preflight prevents the write")
    func blocksLateAccountSwitch() async {
        let gate = ApprovalManagementTestGate()
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(
                        makeApprovalSummary()
                    ),
                ],
                summaryGate: gate
            )
        let fixture = makeFixture(
            service: service
        )
        fixture.model.requestApprove()

        let operation = Task {
            await fixture.model
                .confirmAction()
        }
        await gate.waitUntilEntered()
        fixture.isAccountCurrent = false
        await gate.open()
        await operation.value

        #expect(await service.approveSHAs.isEmpty)
        #expect(
            fixture.model.confirmation == nil
        )
        #expect(
            fixture.model.phase == .idle
        )
    }

    @Test("Cancellation during preflight sends no write")
    func cancelsBeforeWrite() async {
        let gate = ApprovalManagementTestGate()
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(
                        makeApprovalSummary()
                    ),
                ],
                summaryGate: gate
            )
        let fixture = makeFixture(
            service: service
        )
        fixture.model.requestApprove()

        let operation = Task {
            await fixture.model
                .confirmAction()
        }
        await gate.waitUntilEntered()
        operation.cancel()
        await gate.open()
        await operation.value

        #expect(await service.approveSHAs.isEmpty)
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
        #expect(
            fixture.model.phase == .idle
        )
    }

    @Test("Authenticated preflight failures remain session failures")
    func preservesReadAuthenticationFailure() async {
        let error =
            GitLabSessionClientError
                .api(.unauthenticated)
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .failure(error),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .load(error)
        )
        #expect(
            fixture.model
                .authenticationFailure
                == error
        )
        #expect(await service.approveSHAs.isEmpty)
    }

    @Test("A confirmed write without authoritative membership is not applied")
    func rejectsMissingPostWriteMembership() async {
        let baseline =
            makeApprovalSummary()
        let service =
            RecordingApprovalManagementService(
                mergeRequestResults: [
                    .success(makeMergeRequest()),
                    .success(makeMergeRequest()),
                ],
                summaryResults: [
                    .success(baseline),
                    .success(baseline),
                ],
                approveResults: [
                    .success(baseline),
                ]
            )
        let fixture = makeFixture(
            service: service
        )

        fixture.model.requestApprove()
        await fixture.model.confirmAction()

        #expect(
            fixture.model.failure
                == .notApplied
        )
        #expect(
            fixture.model
                .hasUnresolvedMutation
                == false
        )
    }
}

@MainActor
private final class ApprovalManagementFixture {
    var currentMergeRequest:
        GitLabMergeRequest?
    var currentSummary:
        GitLabMergeRequestApprovalSummary?
    var isAccountCurrent = true
    private let service:
        any GitLabMergeRequestApprovalServing
    private let apiAccess:
        GitLabAPIAccess
    private let accountID = makeAccountID()
    private let route:
        GitLabMergeRequestRoute
    lazy var model =
        GitLabMergeRequestApprovalManagementModel(
            route: route,
            accountID: accountID,
            apiAccess: apiAccess,
            service: service,
            currentMergeRequest: {
                [weak self] in
                self?.currentMergeRequest
            },
            currentApprovalSummary: {
                [weak self] in
                self?.currentSummary
            },
            isAccountCurrent: {
                [weak self] in
                self?.isAccountCurrent
                    == true
            },
            onMergeRequestReconciled: {
                [weak self] value in
                self?.currentMergeRequest =
                    value
            },
            onApprovalSummaryReconciled: {
                [weak self] value in
                self?.currentSummary =
                    value
            }
        )

    init(
        service:
            any GitLabMergeRequestApprovalServing,
        mergeRequest: GitLabMergeRequest,
        summary:
            GitLabMergeRequestApprovalSummary,
        apiAccess: GitLabAPIAccess
    ) {
        currentMergeRequest = mergeRequest
        currentSummary = summary
        self.service = service
        self.apiAccess = apiAccess
        route = mergeRequest.route
    }
}

@MainActor
private func makeFixture(
    service:
        any GitLabMergeRequestApprovalServing,
    mergeRequest:
        GitLabMergeRequest =
            makeMergeRequest(),
    summary:
        GitLabMergeRequestApprovalSummary =
            makeApprovalSummary(),
    apiAccess:
        GitLabAPIAccess = .readWrite
) -> ApprovalManagementFixture {
    ApprovalManagementFixture(
        service: service,
        mergeRequest: mergeRequest,
        summary: summary,
        apiAccess: apiAccess
    )
}

private nonisolated func makeAccountID()
    -> GitLabAccountID
{
    GitLabAccountID(
        host:
            try! GitLabHost(
                "https://gitlab.example.com"
            ),
        userID: 7
    )
}

private nonisolated func makeMergeRequest(
    headSHA: String = "rendered-head",
    state: String = "opened",
    detailedMergeStatus: String? = "mergeable"
) -> GitLabMergeRequest {
    makeTestMergeRequest(
        state: state,
        sha: headSHA,
        diffRefs:
            GitLabMergeRequestDiffRefs(
                baseSHA: "base",
                startSHA: "start",
                headSHA: headSHA
            ),
        detailedMergeStatus:
            detailedMergeStatus
    )
}

private nonisolated func makeApprovalSummary(
    approvedUserIDs: [Int] = []
) -> GitLabMergeRequestApprovalSummary {
    GitLabMergeRequestApprovalSummary(
        approved:
            !approvedUserIDs.isEmpty,
        approvalsRequired: 1,
        approvalsLeft:
            approvedUserIDs.isEmpty
            ? 1
            : 0,
        approvedBy:
            approvedUserIDs.map {
                userID in
                GitLabMergeRequestApproval(
                    user:
                        makeTestAPIUser(
                            id: userID,
                            username:
                                "user-\(userID)",
                            name:
                                "User \(userID)"
                        )
                )
            }
    )
}

private nonisolated func makeApprovalDetails(
    ruleName: String
) -> GitLabMergeRequestApprovalDetails {
    GitLabMergeRequestApprovalDetails(
        approvalRulesOverwritten: false,
        rules: [
            GitLabMergeRequestApprovalRule(
                id: 41,
                name: ruleName,
                ruleType: "regular",
                eligibleApprovers: [],
                approvalsRequired: 1,
                users: [],
                groups: [],
                containsHiddenGroups: false,
                approvedBy: [],
                approved: false,
                overridden: false
            ),
        ]
    )
}

private nonisolated func makeApprovalDetailsEvent(
    _ details:
        GitLabMergeRequestApprovalDetails,
    source: GitLabAPIResponseSource
) -> GitLabAPIResponseEvent<
    GitLabMergeRequestApprovalDetailsAvailability
> {
    GitLabAPIResponseEvent(
        value: .available(details),
        metadata:
            GitLabResponseMetadata(),
        source: source
    )
}

private actor ApprovalManagementTestGate {
    private var isEntered = false
    private var continuation:
        CheckedContinuation<Void, Never>?

    func wait() async {
        isEntered = true
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func waitUntilEntered() async {
        while !isEntered {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private actor RecordingApprovalManagementService:
    GitLabMergeRequestApprovalServing
{
    private var mergeRequestResults:
        [
            Result<
                GitLabMergeRequest,
                GitLabSessionClientError
            >
        ]
    private var summaryResults:
        [
            Result<
                GitLabMergeRequestApprovalSummary,
                GitLabSessionClientError
            >
        ]
    private var approveResults:
        [
            Result<
                GitLabMergeRequestApprovalSummary,
                GitLabSessionClientError
            >
        ]
    private var unapproveResults:
        [
            Result<
                GitLabMergeRequestApprovalSummary,
                GitLabSessionClientError
            >
        ]
    private var detailsEventResults:
        [
            Result<
                [
                    GitLabAPIResponseEvent<
                        GitLabMergeRequestApprovalDetailsAvailability
                    >
                ],
                GitLabSessionClientError
            >
        ]
    private let summaryGate:
        ApprovalManagementTestGate?

    private(set) var mergeRequestCount = 0
    private(set) var summaryCount = 0
    private(set) var approveSHAs:
        [String] = []
    private(set) var unapproveCount = 0
    private(set) var
        detailsRefreshBehaviors:
        [GitLabCacheRefreshBehavior] = []

    init(
        mergeRequestResults:
            [
                Result<
                    GitLabMergeRequest,
                    GitLabSessionClientError
                >
            ] = [],
        summaryResults:
            [
                Result<
                    GitLabMergeRequestApprovalSummary,
                    GitLabSessionClientError
                >
            ] = [],
        approveResults:
            [
                Result<
                    GitLabMergeRequestApprovalSummary,
                    GitLabSessionClientError
                >
            ] = [],
        unapproveResults:
            [
                Result<
                    GitLabMergeRequestApprovalSummary,
                    GitLabSessionClientError
                >
            ] = [],
        detailsEventResults:
            [
                Result<
                    [
                        GitLabAPIResponseEvent<
                            GitLabMergeRequestApprovalDetailsAvailability
                        >
                    ],
                    GitLabSessionClientError
                >
            ] = [],
        summaryGate:
            ApprovalManagementTestGate? = nil
    ) {
        self.mergeRequestResults =
            mergeRequestResults
        self.summaryResults =
            summaryResults
        self.approveResults =
            approveResults
        self.unapproveResults =
            unapproveResults
        self.detailsEventResults =
            detailsEventResults
        self.summaryGate = summaryGate
    }

    func loadLatestMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        mergeRequestCount += 1
        return try next(
            from: &mergeRequestResults
        )
    }

    func loadApprovalSummary(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        summaryCount += 1
        if let summaryGate {
            await summaryGate.wait()
        }
        return try next(
            from: &summaryResults
        )
    }

    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalDetailsAvailability
    {
        .unavailable
    }

    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalDetailsAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        detailsRefreshBehaviors.append(
            refreshBehavior
        )
        guard !detailsEventResults.isEmpty else {
            await onResponse(
                GitLabAPIResponseEvent(
                    value: .unavailable,
                    metadata:
                        GitLabResponseMetadata(),
                    source: .network
                )
            )
            return
        }
        switch detailsEventResults
            .removeFirst()
        {
        case let .success(events):
            for event in events {
                await onResponse(event)
            }
        case let .failure(error):
            throw error
        }
    }

    func loadApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
    {
        throw .api(.invalidResponse)
    }

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        GitLabResourcePage(
            items: [],
            nextPageURL: nil
        )
    }

    func approve(
        at route: GitLabMergeRequestRoute,
        sha: String
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        approveSHAs.append(sha)
        return try next(
            from: &approveResults
        )
    }

    func unapprove(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        unapproveCount += 1
        return try next(
            from: &unapproveResults
        )
    }

    func updateApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int,
        replacement:
            GitLabMergeRequestApprovalRuleReplacement
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
    {
        throw .api(.invalidResponse)
    }

    private func next<Value>(
        from values:
            inout [
                Result<
                    Value,
                    GitLabSessionClientError
                >
            ]
    ) throws(GitLabSessionClientError)
        -> Value
    {
        guard !values.isEmpty else {
            throw .api(.invalidResponse)
        }
        switch values.removeFirst() {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}
