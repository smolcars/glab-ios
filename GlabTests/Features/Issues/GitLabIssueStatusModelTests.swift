import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab issue status model")
struct GitLabIssueStatusModelTests {
    @Test("Loads supported and unavailable capability states")
    func loadsCapabilityStates() async {
        let supportedService =
            RecordingStatusService()
        let supported = makeModel(
            statusService:
                supportedService
        )

        await supported.model.load()

        #expect(
            supported.model.state
                == .supported(
                    makeStatusSnapshot(),
                    isStale: false
                )
        )
        #expect(supported.model.failure == nil)

        let unavailableService =
            RecordingStatusService(
                loadResults: [
                    .success(.unavailable),
                ]
            )
        let unavailable = makeModel(
            statusService:
                unavailableService
        )

        await unavailable.model.load()

        #expect(
            unavailable.model.state
                == .unavailable
        )
        #expect(unavailable.model.failure == nil)
    }

    @Test("Refresh failure preserves a stale supported snapshot")
    func preservesSnapshotAfterRefreshFailure() async {
        let failure =
            GitLabSessionClientError
                .api(
                    .connectivity(
                        .notConnectedToInternet
                    )
                )
        let service =
            RecordingStatusService(
                refreshResults: [
                    .failure(failure),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()

        await context.model.refresh()

        #expect(
            context.model.state
                == .supported(
                    makeStatusSnapshot(),
                    isStale: true
                )
        )
        #expect(
            context.model.failure
                == .load(failure)
        )
        #expect(
            context.model.authenticationFailure
                == nil
        )
    }

    @Test("Selecting the current status is a no-op")
    func currentSelectionIsNoOp() async {
        let service =
            RecordingStatusService()
        let context = makeModel(
            statusService: service
        )
        await context.model.load()

        await context.model.select(
            try! #require(
                context.model.snapshot?
                    .currentStatus
            )
        )

        #expect(
            await service.refreshCount == 0
        )
        #expect(
            await service.updateCount == 0
        )
        #expect(
            context.model.selectionConfirmation
                == nil
        )
    }

    @Test("Read-only and server permission block writes locally")
    func permissionsBlockWrites() async {
        let readOnlyService =
            RecordingStatusService()
        let readOnly = makeModel(
            statusService:
                readOnlyService,
            apiAccess: .readOnly
        )
        await readOnly.model.load()

        await readOnly.model.select(
            makeDoneStatus()
        )

        #expect(
            readOnly.model.failure
                == .readOnly
        )
        #expect(
            await readOnlyService
                .refreshCount == 0
        )

        let permissionService =
            RecordingStatusService(
                loadResults: [
                    .success(
                        .supported(
                            makeStatusSnapshot(
                                canUpdate: false
                            )
                        )
                    ),
                ]
            )
        let permission = makeModel(
            statusService:
                permissionService
        )
        await permission.model.load()

        await permission.model.select(
            makeDoneStatus()
        )

        #expect(
            permission.model.failure
                == .permissionDenied
        )
        #expect(
            await permissionService
                .refreshCount == 0
        )
    }

    @Test("A state-changing status requires confirmation")
    func confirmsClosingStatus() async {
        let service =
            RecordingStatusService()
        let context = makeModel(
            statusService: service
        )
        await context.model.load()

        await context.model.select(
            makeDoneStatus()
        )

        #expect(
            context.model.selectionConfirmation
                == GitLabIssueStatusSelectionConfirmation(
                    status: makeDoneStatus(),
                    resultingState: .closed
                )
        )
        #expect(
            await service.refreshCount == 0
        )
        #expect(
            await service.updateCount == 0
        )
    }

    @Test("A refreshed state invalidates stale transition confirmation")
    func refreshInvalidatesStaleConfirmation() async {
        let closed =
            makeStatusSnapshot(
                state: .closed,
                lockVersion: 9,
                currentStatus:
                    makeDoneStatus()
            )
        let service =
            RecordingStatusService(
                refreshResults: [
                    .success(
                        .supported(closed)
                    ),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )

        await context.model.refresh()
        await context.model
            .confirmSelection()

        #expect(
            context.model.snapshot == closed
        )
        #expect(
            context.model.failure == .stale
        )
        #expect(
            context.model.selectionConfirmation
                == nil
        )
        #expect(
            await service.refreshCount == 1
        )
        #expect(
            await service.updateCount == 0
        )
    }

    @Test("A status can reopen a closed issue after confirmation")
    func reopensClosedIssue() async {
        let inProgress =
            try! #require(
                makeStatusSnapshot()
                    .currentStatus
            )
        let baseline =
            makeStatusSnapshot(
                state: .closed,
                currentStatus:
                    makeDoneStatus()
            )
        let result =
            GitLabIssueStatusUpdateResult(
                workItemID:
                    baseline.workItemID,
                issueIID:
                    baseline.issueIID,
                state: .open,
                updatedAt:
                    Date(
                        timeIntervalSince1970:
                            1_785_240_300
                    ),
                lockVersion: 9,
                status: inProgress
            )
        let service =
            RecordingStatusService(
                loadResults: [
                    .success(
                        .supported(baseline)
                    ),
                ],
                refreshResults: [
                    .success(
                        .supported(baseline)
                    ),
                ],
                updateResults: [
                    .success(
                        .updated(result)
                    ),
                ]
            )
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .success(
                        .issue(
                            makeTestIssue(
                                iid: 17,
                                reference:
                                    "group/project#17"
                            )
                        )
                    ),
                ]
            )
        let context = makeModel(
            statusService: service,
            resourceService:
                resourceService
        )
        await context.model.load()

        await context.model.select(
            inProgress
        )

        #expect(
            context.model.selectionConfirmation
                == GitLabIssueStatusSelectionConfirmation(
                    status: inProgress,
                    resultingState: .open
                )
        )

        await context.model
            .confirmSelection()

        #expect(
            context.model.snapshot?
                .currentStatus == inProgress
        )
        #expect(
            context.model.snapshot?
                .state == .open
        )
        #expect(context.model.failure == nil)
    }

    @Test("A same-state status updates without confirmation")
    func sameStateStatusDoesNotConfirm() async {
        let todo = makeToDoStatus()
        let baseline =
            makeStatusSnapshot(
                allowedStatuses: [
                    todo,
                    try! #require(
                        makeStatusSnapshot()
                            .currentStatus
                    ),
                    makeDoneStatus(),
                ]
            )
        let result =
            GitLabIssueStatusUpdateResult(
                workItemID:
                    baseline.workItemID,
                issueIID:
                    baseline.issueIID,
                state: .open,
                updatedAt:
                    Date(
                        timeIntervalSince1970:
                            1_785_240_300
                    ),
                lockVersion: 9,
                status: todo
            )
        let service =
            RecordingStatusService(
                loadResults: [
                    .success(
                        .supported(baseline)
                    ),
                ],
                refreshResults: [
                    .success(
                        .supported(baseline)
                    ),
                ],
                updateResults: [
                    .success(
                        .updated(result)
                    ),
                ]
            )
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .success(
                        .issue(
                            makeTestIssue(
                                iid: 17,
                                reference:
                                    "group/project#17"
                            )
                        )
                    ),
                ]
            )
        let context = makeModel(
            statusService: service,
            resourceService:
                resourceService
        )
        await context.model.load()

        await context.model.select(todo)

        #expect(
            context.model.selectionConfirmation
                == nil
        )
        #expect(
            context.model.snapshot?
                .currentStatus == todo
        )
        #expect(
            await service.updateCount == 1
        )
    }

    @Test("Rapid selections perform only one preflight and mutation")
    func rapidSelectionsSendOnce() async {
        let baseline =
            makeStatusSnapshot(
                allowedStatuses: [
                    makeToDoStatus(),
                    try! #require(
                        makeStatusSnapshot()
                            .currentStatus
                    ),
                    makeDoneStatus(),
                ]
            )
        let service =
            SuspendedPreflightStatusService(
                baseline: baseline
            )
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .success(
                        .issue(
                            makeTestIssue(
                                iid: 17,
                                reference:
                                    "group/project#17"
                            )
                        )
                    ),
                ]
            )
        let context = makeModel(
            statusService: service,
            resourceService:
                resourceService
        )
        await context.model.load()

        let first = Task {
            await context.model.select(
                makeToDoStatus()
            )
        }
        await service
            .waitUntilPreflightStarted()
        await context.model.select(
            makeToDoStatus()
        )
        await service.resumePreflight()
        await first.value

        #expect(
            await service.refreshCount == 1
        )
        #expect(
            await service.updateCount == 1
        )
    }

    @Test("Confirmed update preflights, mutates once, and reconciles REST")
    func updatesAndReconciles() async {
        let service =
            RecordingStatusService()
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .success(
                        .issue(
                            makeClosedIssue()
                        )
                    ),
                ]
            )
        let context = makeModel(
            statusService: service,
            resourceService:
                resourceService
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )

        await context.model
            .confirmSelection()

        #expect(
            context.model.snapshot?
                .currentStatus?.id
                == "status-done"
        )
        #expect(
            context.model.snapshot?
                .state == .closed
        )
        #expect(
            context.model.failure == nil
        )
        #expect(
            !context.model
                .requiresDeliveryCheck
        )
        #expect(
            await service.refreshCount == 1
        )
        #expect(
            await service.updateCount == 1
        )
        #expect(
            await resourceService
                .invalidationCount == 1
        )
        #expect(
            context.reconciled.issue
                == makeClosedIssue()
        )
    }

    @Test("Changed preflight is adopted without mutation")
    func stalePreflightStopsMutation() async {
        let changed =
            makeStatusSnapshot(
                lockVersion: 9
            )
        let service =
            RecordingStatusService(
                refreshResults: [
                    .success(
                        .supported(changed)
                    ),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )

        await context.model
            .confirmSelection()

        #expect(
            context.model.snapshot == changed
        )
        #expect(
            context.model.failure == .stale
        )
        #expect(
            await service.updateCount == 0
        )
    }

    @Test("Rejected mutation preserves the preflight snapshot")
    func rejectedMutationPreservesStatus() async {
        let service =
            RecordingStatusService(
                updateResults: [
                    .success(.rejected),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )

        await context.model
            .confirmSelection()

        #expect(
            context.model.snapshot
                == makeStatusSnapshot()
        )
        #expect(
            context.model.failure
                == .rejected
        )
        #expect(
            !context.model
                .requiresDeliveryCheck
        )
    }

    @Test("Mutation authentication failure remains actionable")
    func preservesMutationAuthenticationFailure() async {
        let failure =
            GitLabSessionClientError
                .api(.unauthenticated)
        let service =
            RecordingStatusService(
                updateResults: [
                    .failure(failure),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )

        await context.model
            .confirmSelection()

        #expect(
            context.model.failure
                == .load(failure)
        )
        #expect(
            context.model
                .authenticationFailure
                == failure
        )
        #expect(
            !context.model
                .requiresDeliveryCheck
        )
    }

    @Test("Unknown delivery is resolved by an authoritative status check")
    func checksUnknownDelivery() async {
        let applied =
            makeStatusSnapshot(
                state: .closed,
                lockVersion: 9,
                currentStatus:
                    makeDoneStatus()
            )
        let service =
            RecordingStatusService(
                refreshResults: [
                    .success(
                        .supported(
                            makeStatusSnapshot()
                        )
                    ),
                    .success(
                        .supported(applied)
                    ),
                ],
                updateResults: [
                    .success(
                        .deliveryUnknown
                    ),
                ]
            )
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .success(
                        .issue(
                            makeClosedIssue()
                        )
                    ),
                ]
            )
        let context = makeModel(
            statusService: service,
            resourceService:
                resourceService
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )
        await context.model
            .confirmSelection()

        #expect(
            context.model
                .requiresDeliveryCheck
        )
        #expect(
            context.model.failure
                == .deliveryUnknown
        )

        await context.model.checkGitLab()

        #expect(
            context.model.snapshot == applied
        )
        #expect(
            !context.model
                .requiresDeliveryCheck
        )
        #expect(
            context.model.failure == nil
        )
        #expect(
            context.reconciled.issue
                == makeClosedIssue()
        )
    }

    @Test("Unknown delivery reports when the mutation was not applied")
    func reportsUnknownMutationNotApplied() async {
        let baseline =
            makeStatusSnapshot()
        let service =
            RecordingStatusService(
                refreshResults: [
                    .success(
                        .supported(baseline)
                    ),
                    .success(
                        .supported(baseline)
                    ),
                ],
                updateResults: [
                    .success(
                        .deliveryUnknown
                    ),
                ]
            )
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .success(
                        .issue(
                            makeTestIssue(
                                iid: 17,
                                reference:
                                    "group/project#17"
                            )
                        )
                    ),
                ]
            )
        let context = makeModel(
            statusService: service,
            resourceService:
                resourceService
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )
        await context.model
            .confirmSelection()

        await context.model.checkGitLab()

        #expect(
            context.model.snapshot == baseline
        )
        #expect(
            context.model.failure
                == .notApplied
        )
        #expect(
            !context.model
                .requiresDeliveryCheck
        )
        #expect(
            await service.updateCount == 1
        )
    }

    @Test("Unknown delivery keeps intent when state cannot be verified")
    func retainsUnverifiableUnknownIntent() async {
        let inconsistent =
            makeStatusSnapshot(
                state: .open,
                lockVersion: 9,
                currentStatus:
                    makeDoneStatus()
            )
        let service =
            RecordingStatusService(
                refreshResults: [
                    .success(
                        .supported(
                            makeStatusSnapshot()
                        )
                    ),
                    .success(
                        .supported(
                            inconsistent
                        )
                    ),
                ],
                updateResults: [
                    .success(
                        .deliveryUnknown
                    ),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )
        await context.model
            .confirmSelection()

        await context.model.checkGitLab()

        #expect(
            context.model
                .requiresDeliveryCheck
        )
        #expect(
            context.model.failure
                == .deliveryUnknown
        )
        #expect(
            context.reconciled.issue == nil
        )
    }

    @Test("REST reconciliation failure keeps the applied status recoverable")
    func retriesReconciliation() async {
        let failure =
            GitLabSessionClientError
                .api(
                    .server(
                        statusCode: 503
                    )
                )
        let resourceService =
            RecordingStatusResourceService(
                loadResults: [
                    .failure(failure),
                    .success(
                        .issue(
                            makeClosedIssue()
                        )
                    ),
                ]
            )
        let context = makeModel(
            resourceService:
                resourceService
        )
        await context.model.load()
        await context.model.select(
            makeDoneStatus()
        )
        await context.model
            .confirmSelection()

        #expect(
            context.model.snapshot?
                .currentStatus?.id
                == "status-done"
        )
        #expect(
            context.model
                .requiresDeliveryCheck
        )
        #expect(
            context.model.failure
                == .reconciliation(failure)
        )

        await context.model.checkGitLab()

        #expect(
            !context.model
                .requiresDeliveryCheck
        )
        #expect(
            context.model.failure == nil
        )
        #expect(
            await resourceService
                .loadCount == 2
        )
    }

    @Test("Account change rejects a late load result")
    func rejectsLateAccountResult() async {
        let service =
            SuspendedStatusService()
        let context = makeModel(
            statusService: service
        )
        let operation = Task {
            await context.model.load()
        }
        await service.waitUntilStarted()

        context.account.isCurrent = false
        await service.resume(
            with:
                .supported(
                    makeStatusSnapshot()
                )
        )
        await operation.value

        #expect(
            context.model.snapshot == nil
        )
        #expect(
            context.reconciled.issue == nil
        )
    }

    @Test("Cancellation rejects a late load result")
    func rejectsLateCancelledResult() async {
        let service =
            SuspendedStatusService()
        let context = makeModel(
            statusService: service
        )
        let operation = Task {
            await context.model.load()
        }
        await service.waitUntilStarted()

        operation.cancel()
        await service.resume(
            with:
                .supported(
                    makeStatusSnapshot()
                )
        )
        await operation.value

        #expect(
            context.model.snapshot == nil
        )
        #expect(
            context.model.failure == nil
        )
    }

    @Test("P3-06 issue mutation refreshes work-item status")
    func refreshesAfterIssueMutation() async {
        let refreshed =
            makeStatusSnapshot(
                lockVersion: 9
            )
        let service =
            RecordingStatusService(
                refreshResults: [
                    .success(
                        .supported(refreshed)
                    ),
                ]
            )
        let context = makeModel(
            statusService: service
        )
        await context.model.load()

        await context.model
            .refreshAfterIssueMutation(
                makeTestIssue(
                    iid: 17,
                    reference:
                        "group/project#17"
                )
            )

        #expect(
            context.model.snapshot
                == refreshed
        )
        #expect(
            await service.refreshCount == 1
        )
        #expect(
            await service.loadCount == 1
        )
    }
}

@MainActor
private struct IssueStatusModelContext {
    let model: GitLabIssueStatusModel
    let account: CurrentAccountBox
    let reconciled:
        ReconciledIssueBox
}

@MainActor
private func makeModel(
    statusService:
        any GitLabIssueStatusServing =
            RecordingStatusService(),
    resourceService:
        any GitLabResourceEditing =
            RecordingStatusResourceService(),
    apiAccess: GitLabAPIAccess =
        .readWrite
) -> IssueStatusModelContext {
    let account = CurrentAccountBox()
    let reconciled =
        ReconciledIssueBox()
    let issue = makeTestIssue(
        iid: 17,
        reference: "group/project#17"
    )
    let model =
        GitLabIssueStatusModel(
            accountID:
                GitLabAccountID(
                    host:
                        try! GitLabHost(
                            "gitlab.example.com"
                        ),
                    userID: 1
                ),
            issue: issue,
            apiAccess: apiAccess,
            statusService:
                statusService,
            resourceService:
                resourceService,
            isAccountCurrent: {
                account.isCurrent
            },
            onIssueReconciled: {
                reconciled.issue = $0
            }
        )
    return IssueStatusModelContext(
        model: model,
        account: account,
        reconciled: reconciled
    )
}

@MainActor
private final class CurrentAccountBox {
    var isCurrent = true
}

@MainActor
private final class ReconciledIssueBox {
    var issue: GitLabIssue?
}

private actor RecordingStatusService:
    GitLabIssueStatusServing
{
    private var loadResults:
        [
            Result<
                GitLabIssueStatusAvailability,
                GitLabSessionClientError
            >
        ]
    private var refreshResults:
        [
            Result<
                GitLabIssueStatusAvailability,
                GitLabSessionClientError
            >
        ]
    private var updateResults:
        [
            Result<
                GitLabIssueStatusMutationOutcome,
                GitLabSessionClientError
            >
        ]

    private(set) var loadCount = 0
    private(set) var refreshCount = 0
    private(set) var updateCount = 0

    init(
        loadResults:
            [
                Result<
                    GitLabIssueStatusAvailability,
                    GitLabSessionClientError
                >
            ] = [
                .success(
                    .supported(
                        makeStatusSnapshot()
                    )
                ),
            ],
        refreshResults:
            [
                Result<
                    GitLabIssueStatusAvailability,
                    GitLabSessionClientError
                >
            ] = [
                .success(
                    .supported(
                        makeStatusSnapshot()
                    )
                ),
            ],
        updateResults:
            [
                Result<
                    GitLabIssueStatusMutationOutcome,
                    GitLabSessionClientError
                >
            ] = [
                .success(
                    .updated(
                        makeStatusUpdateResult()
                    )
                ),
            ]
    ) {
        self.loadResults = loadResults
        self.refreshResults =
            refreshResults
        self.updateResults = updateResults
    }

    func loadStatus(
        for issue: GitLabIssue
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        loadCount += 1
        return try next(
            from: &loadResults
        )
    }

    func refreshStatus(
        projectPath: String,
        issueIID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        refreshCount += 1
        return try next(
            from: &refreshResults
        )
    }

    func updateStatus(
        from baseline:
            GitLabIssueStatusSnapshot,
        to selectedStatus:
            GitLabIssueWorkItemStatus
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusMutationOutcome
    {
        updateCount += 1
        return try next(
            from: &updateResults
        )
    }

    private func next<Value>(
        from results:
            inout [
                Result<
                    Value,
                    GitLabSessionClientError
                >
            ]
    ) throws(GitLabSessionClientError)
        -> Value
    {
        guard !results.isEmpty else {
            throw .api(.invalidResponse)
        }
        switch results.removeFirst() {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }
}

private actor RecordingStatusResourceService:
    GitLabResourceEditing
{
    private var loadResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]

    private(set) var loadCount = 0
    private(set) var invalidationCount = 0

    init(
        loadResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ] = [
                .success(
                    .issue(
                        makeClosedIssue()
                    )
                ),
            ]
    ) {
        self.loadResults = loadResults
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        loadCount += 1
        guard !loadResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        switch loadResults.removeFirst() {
        case let .success(value):
            return value
        case let .failure(error):
            throw error
        }
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
    }

    func invalidateAffectedReads(
        for target:
            GitLabResourceEditTarget
    ) async {
        invalidationCount += 1
    }
}

private actor SuspendedStatusService:
    GitLabIssueStatusServing
{
    private var continuation:
        CheckedContinuation<
            GitLabIssueStatusAvailability,
            Never
        >?
    private var started = false

    func loadStatus(
        for issue: GitLabIssue
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        started = true
        return await withCheckedContinuation {
            continuation = $0
        }
    }

    func refreshStatus(
        projectPath: String,
        issueIID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        .unavailable
    }

    func updateStatus(
        from baseline:
            GitLabIssueStatusSnapshot,
        to selectedStatus:
            GitLabIssueWorkItemStatus
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusMutationOutcome
    {
        .rejected
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func resume(
        with result:
            GitLabIssueStatusAvailability
    ) {
        continuation?.resume(
            returning: result
        )
        continuation = nil
    }
}

private actor SuspendedPreflightStatusService:
    GitLabIssueStatusServing
{
    let baseline:
        GitLabIssueStatusSnapshot
    private var continuation:
        CheckedContinuation<
            GitLabIssueStatusAvailability,
            Never
        >?
    private var startedWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var preflightStarted =
        false
    private(set) var refreshCount = 0
    private(set) var updateCount = 0

    init(
        baseline:
            GitLabIssueStatusSnapshot
    ) {
        self.baseline = baseline
    }

    func loadStatus(
        for issue: GitLabIssue
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        .supported(baseline)
    }

    func refreshStatus(
        projectPath: String,
        issueIID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusAvailability
    {
        refreshCount += 1
        return await withCheckedContinuation {
            continuation = $0
            preflightStarted = true
            let waiters = startedWaiters
            startedWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func updateStatus(
        from baseline:
            GitLabIssueStatusSnapshot,
        to selectedStatus:
            GitLabIssueWorkItemStatus
    ) async throws(GitLabSessionClientError)
        -> GitLabIssueStatusMutationOutcome
    {
        updateCount += 1
        return .updated(
            GitLabIssueStatusUpdateResult(
                workItemID:
                    baseline.workItemID,
                issueIID:
                    baseline.issueIID,
                state: .open,
                updatedAt:
                    Date(
                        timeIntervalSince1970:
                            1_785_240_300
                    ),
                lockVersion:
                    baseline.lockVersion + 1,
                status:
                    selectedStatus
            )
        )
    }

    func waitUntilPreflightStarted()
        async
    {
        guard !preflightStarted else {
            return
        }
        await withCheckedContinuation {
            startedWaiters.append($0)
        }
    }

    func resumePreflight() {
        continuation?.resume(
            returning:
                .supported(baseline)
        )
        continuation = nil
    }
}

private nonisolated func makeToDoStatus()
    -> GitLabIssueWorkItemStatus
{
    GitLabIssueWorkItemStatus(
        id: "status-todo",
        name: "To do",
        description: nil,
        iconName: nil,
        color: nil,
        position: 0,
        category: .toDo
    )
}

private nonisolated func makeClosedIssue()
    -> GitLabIssue
{
    makeTestIssue(
        iid: 17,
        state: "closed",
        closedAt:
            Date(
                timeIntervalSince1970:
                    1_785_240_300
            ),
        reference: "group/project#17"
    )
}
