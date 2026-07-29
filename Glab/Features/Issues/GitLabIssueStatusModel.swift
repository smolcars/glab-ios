import Foundation
import Observation

nonisolated enum GitLabIssueStatusModelState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case unavailable
    case supported(
        GitLabIssueStatusSnapshot,
        isStale: Bool
    )
}

nonisolated enum GitLabIssueStatusModelFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case load(
        GitLabSessionClientError
    )
    case readOnly
    case permissionDenied
    case stale
    case rejected
    case deliveryUnknown
    case reconciliation(
        GitLabSessionClientError
    )
    case authoritativeMismatch
    case notApplied

    var authenticationFailure:
        GitLabSessionClientError?
    {
        switch self {
        case let .load(error),
             let .reconciliation(error):
            error.requiresReauthentication
                ? error
                : nil
        case .readOnly,
             .permissionDenied,
             .stale,
             .rejected,
             .deliveryUnknown,
             .authoritativeMismatch,
             .notApplied:
            nil
        }
    }

    var description: String {
        "GitLabIssueStatusModelFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated struct GitLabIssueStatusSelectionConfirmation:
    Equatable,
    Sendable
{
    let status: GitLabIssueWorkItemStatus
    let resultingState: GitLabWorkItemState
}

@MainActor
@Observable
final class GitLabIssueStatusModel {
    private(set) var state =
        GitLabIssueStatusModelState.idle
    private(set) var failure:
        GitLabIssueStatusModelFailure?
    private(set) var selectionConfirmation:
        GitLabIssueStatusSelectionConfirmation?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var isCheckingGitLab =
        false

    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let accountID: GitLabAccountID
    @ObservationIgnored
    private let statusService:
        any GitLabIssueStatusServing
    @ObservationIgnored
    private let resourceService:
        any GitLabResourceEditing
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onIssueReconciled:
        @MainActor (GitLabIssue) -> Void
    @ObservationIgnored
    private var issue: GitLabIssue
    @ObservationIgnored
    private var pendingMutation:
        PendingMutation?
    @ObservationIgnored
    private var pendingReconciliation:
        GitLabIssueStatusSnapshot?
    @ObservationIgnored
    private var operationGeneration:
        UInt64 = 0

    init(
        accountID: GitLabAccountID,
        issue: GitLabIssue,
        apiAccess: GitLabAPIAccess,
        statusService:
            any GitLabIssueStatusServing,
        resourceService:
            any GitLabResourceEditing,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onIssueReconciled:
            @escaping @MainActor (
                GitLabIssue
            ) -> Void
    ) {
        self.accountID = accountID
        self.issue = issue
        self.apiAccess = apiAccess
        self.statusService =
            statusService
        self.resourceService =
            resourceService
        self.isAccountCurrent =
            isAccountCurrent
        self.onIssueReconciled =
            onIssueReconciled
    }

    var snapshot:
        GitLabIssueStatusSnapshot?
    {
        guard
            case let .supported(
                snapshot,
                _
            ) = state
        else {
            return nil
        }
        return snapshot
    }

    var isBusy: Bool {
        isLoading
            || isSaving
            || isCheckingGitLab
    }

    var requiresDeliveryCheck: Bool {
        pendingMutation != nil
            || pendingReconciliation != nil
    }

    var canChangeStatus: Bool {
        apiAccess.canWrite
            && isAccountCurrent()
            && snapshot?.canUpdate == true
            && !isBusy
            && !requiresDeliveryCheck
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    func load() async {
        await performRead(
            forceProjectResolution: true
        )
    }

    func refresh() async {
        await performRead(
            forceProjectResolution: false
        )
    }

    func refreshAfterIssueMutation(
        _ updatedIssue: GitLabIssue
    ) async {
        guard
            updatedIssue.route
                == issue.route
        else {
            return
        }
        issue = updatedIssue
        await refresh()
    }

    func select(
        _ status:
            GitLabIssueWorkItemStatus
    ) async {
        guard
            !isBusy,
            !requiresDeliveryCheck,
            isAccountCurrent(),
            let baseline = snapshot
        else {
            return
        }
        failure = nil

        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard baseline.canUpdate else {
            failure = .permissionDenied
            return
        }
        guard
            baseline.allowedStatuses
                .contains(status)
        else {
            failure = .stale
            return
        }
        guard
            baseline.currentStatus?.id
                != status.id
        else {
            return
        }

        let resultingState =
            Self.workItemState(
                for: status.category
            )
        guard
            resultingState.issueState
                == baseline.state.issueState
        else {
            selectionConfirmation =
                GitLabIssueStatusSelectionConfirmation(
                    status: status,
                    resultingState:
                        resultingState
                )
            return
        }

        await performMutation(
            status,
            baseline: baseline
        )
    }

    func confirmSelection() async {
        guard
            let confirmation =
                selectionConfirmation,
            let baseline = snapshot,
            !isBusy,
            !requiresDeliveryCheck
        else {
            return
        }
        selectionConfirmation = nil
        await performMutation(
            confirmation.status,
            baseline: baseline
        )
    }

    func cancelSelection() {
        selectionConfirmation = nil
    }

    func checkGitLab() async {
        guard
            !isBusy,
            isAccountCurrent()
        else {
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        isCheckingGitLab = true
        defer {
            if
                operationGeneration
                    == generation
            {
                isCheckingGitLab =
                    false
            }
        }

        if
            let reconciliation =
                pendingReconciliation
        {
            _ = await reconcile(
                reconciliation,
                generation: generation,
                completionFailure: nil
            )
            return
        }

        guard
            let pending =
                pendingMutation
        else {
            return
        }

        let availability:
            GitLabIssueStatusAvailability
        do {
            availability =
                try await statusService
                    .refreshStatus(
                        projectPath:
                            pending
                                .projectPath,
                        issueIID:
                            issue.iid
                    )
        } catch {
            guard canPublish(generation) else {
                return
            }
            failure = .load(error)
            return
        }

        guard
            canPublish(generation),
            case let .supported(
                refreshed
            ) = availability,
            refreshed.workItemID
                == pending.workItemID
        else {
            return
        }

        let wasApplied =
            refreshed.currentStatus?.id
                == pending.statusID
        guard
            !wasApplied
                || refreshed.state
                    == pending.expectedState
        else {
            failure = .deliveryUnknown
            return
        }

        state = .supported(
            refreshed,
            isStale: false
        )
        pendingMutation = nil
        pendingReconciliation =
            refreshed
        _ = await reconcile(
            refreshed,
            generation: generation,
            completionFailure:
                wasApplied
                ? nil
                : .notApplied
        )
    }
}

private extension GitLabIssueStatusModel {
    nonisolated struct PendingMutation:
        Equatable,
        Sendable
    {
        let projectPath: String
        let workItemID: String
        let baselineStatusID: String?
        let statusID: String
        let expectedState:
            GitLabWorkItemState
    }

    func performRead(
        forceProjectResolution: Bool
    ) async {
        guard
            !isSaving,
            !isLoading,
            !isCheckingGitLab,
            isAccountCurrent()
        else {
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        let existingSnapshot = snapshot
        isLoading = true
        failure = nil
        if existingSnapshot == nil {
            state = .loading
        }
        defer {
            if
                operationGeneration
                    == generation
            {
                isLoading = false
            }
        }

        let availability:
            GitLabIssueStatusAvailability
        do {
            if
                !forceProjectResolution,
                let existingSnapshot
            {
                availability =
                    try await statusService
                        .refreshStatus(
                            projectPath:
                                existingSnapshot
                                    .projectPath,
                            issueIID:
                                issue.iid
                        )
            } else {
                availability =
                    try await statusService
                        .loadStatus(
                            for: issue
                        )
            }
        } catch {
            guard canPublish(generation) else {
                return
            }
            if let existingSnapshot {
                state = .supported(
                    existingSnapshot,
                    isStale: true
                )
            } else {
                state = .unavailable
            }
            failure = .load(error)
            return
        }

        guard canPublish(generation) else {
            return
        }
        switch availability {
        case let .supported(snapshot):
            state = .supported(
                snapshot,
                isStale: false
            )
        case .unavailable:
            if let existingSnapshot {
                state = .supported(
                    existingSnapshot,
                    isStale: true
                )
                failure = .stale
            } else {
                state = .unavailable
            }
        }
    }

    func performMutation(
        _ selectedStatus:
            GitLabIssueWorkItemStatus,
        baseline:
            GitLabIssueStatusSnapshot
    ) async {
        guard
            !isBusy,
            !requiresDeliveryCheck,
            isAccountCurrent()
        else {
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        isSaving = true
        failure = nil
        defer {
            if
                operationGeneration
                    == generation
            {
                isSaving = false
            }
        }

        let preflight:
            GitLabIssueStatusSnapshot
        do {
            let availability =
                try await statusService
                    .refreshStatus(
                        projectPath:
                            baseline
                                .projectPath,
                        issueIID:
                            baseline
                                .issueIID
                    )
            guard
                canPublish(generation),
                case let .supported(
                    refreshed
                ) = availability
            else {
                if canPublish(generation) {
                    state = .supported(
                        baseline,
                        isStale: true
                    )
                    failure = .stale
                }
                return
            }
            preflight = refreshed
        } catch {
            guard canPublish(generation) else {
                return
            }
            state = .supported(
                baseline,
                isStale: true
            )
            failure = .load(error)
            return
        }

        guard
            canPublish(generation)
        else {
            return
        }
        state = .supported(
            preflight,
            isStale: false
        )
        guard
            Self.sameMutationBaseline(
                baseline,
                preflight
            ),
            preflight.allowedStatuses
                .contains(
                    selectedStatus
                ),
            preflight.currentStatus?.id
                != selectedStatus.id
        else {
            failure = .stale
            return
        }

        let outcome:
            GitLabIssueStatusMutationOutcome
        do {
            outcome =
                try await statusService
                    .updateStatus(
                        from: preflight,
                        to: selectedStatus
                    )
        } catch {
            guard canPublish(generation) else {
                return
            }
            if error.requiresReauthentication {
                failure = .load(error)
            } else if
                error
                    .mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                retainUnknownMutation(
                    selectedStatus,
                    baseline: preflight
                )
            } else {
                failure = .rejected
            }
            return
        }

        guard canPublish(generation) else {
            return
        }
        switch outcome {
        case let .updated(result):
            let updated =
                Self.applying(
                    result,
                    to: preflight
                )
            state = .supported(
                updated,
                isStale: false
            )
            pendingReconciliation =
                updated
            _ = await reconcile(
                updated,
                generation: generation,
                completionFailure: nil
            )

        case .rejected:
            failure = .rejected

        case .deliveryUnknown:
            retainUnknownMutation(
                selectedStatus,
                baseline: preflight
            )
        }
    }

    func retainUnknownMutation(
        _ selectedStatus:
            GitLabIssueWorkItemStatus,
        baseline:
            GitLabIssueStatusSnapshot
    ) {
        pendingMutation =
            PendingMutation(
                projectPath:
                    baseline.projectPath,
                workItemID:
                    baseline.workItemID,
                baselineStatusID:
                    baseline
                        .currentStatus?.id,
                statusID:
                    selectedStatus.id,
                expectedState:
                    Self.workItemState(
                        for:
                            selectedStatus
                                .category
                    )
            )
        failure = .deliveryUnknown
    }

    func reconcile(
        _ statusSnapshot:
            GitLabIssueStatusSnapshot,
        generation: UInt64,
        completionFailure:
            GitLabIssueStatusModelFailure?
    ) async -> Bool {
        let target =
            GitLabResourceEditTarget
                .issue(issue.route)
        await resourceService
            .invalidateAffectedReads(
                for: target
            )
        guard canPublish(generation) else {
            return false
        }

        let result:
            GitLabResourceEditResult
        do {
            result =
                try await resourceService
                    .loadLatest(target)
        } catch {
            guard canPublish(generation) else {
                return false
            }
            pendingReconciliation =
                statusSnapshot
            failure =
                .reconciliation(error)
            return false
        }

        guard
            canPublish(generation),
            case let .issue(
                reconciledIssue
            ) = result,
            reconciledIssue.route
                == issue.route,
            reconciledIssue.stateKind
                == statusSnapshot
                    .state.issueState
        else {
            if canPublish(generation) {
                pendingReconciliation =
                    statusSnapshot
                failure =
                    .authoritativeMismatch
            }
            return false
        }

        issue = reconciledIssue
        pendingReconciliation = nil
        failure = completionFailure
        onIssueReconciled(
            reconciledIssue
        )
        return true
    }

    func canPublish(
        _ generation: UInt64
    ) -> Bool {
        operationGeneration
            == generation
            && isAccountCurrent()
            && !Task.isCancelled
    }

    nonisolated static func workItemState(
        for category:
            GitLabIssueStatusCategory
    ) -> GitLabWorkItemState {
        switch category {
        case .triage,
             .toDo,
             .inProgress:
            .open
        case .done,
             .canceled:
            .closed
        }
    }

    nonisolated static func sameMutationBaseline(
        _ lhs:
            GitLabIssueStatusSnapshot,
        _ rhs:
            GitLabIssueStatusSnapshot
    ) -> Bool {
        lhs.projectPath == rhs.projectPath
            && lhs.workItemID
                == rhs.workItemID
            && lhs.issueIID == rhs.issueIID
            && lhs.state == rhs.state
            && lhs.lockVersion
                == rhs.lockVersion
            && lhs.currentStatus
                == rhs.currentStatus
            && lhs.allowedStatuses
                == rhs.allowedStatuses
            && lhs.canUpdate
                == rhs.canUpdate
    }

    nonisolated static func applying(
        _ result:
            GitLabIssueStatusUpdateResult,
        to baseline:
            GitLabIssueStatusSnapshot
    ) -> GitLabIssueStatusSnapshot {
        let statuses =
            baseline.allowedStatuses.map {
                $0.id == result.status.id
                    ? result.status
                    : $0
            }
        return GitLabIssueStatusSnapshot(
            projectPath:
                baseline.projectPath,
            workItemID:
                result.workItemID,
            issueIID:
                result.issueIID,
            state: result.state,
            updatedAt:
                result.updatedAt,
            lockVersion:
                result.lockVersion,
            currentStatus:
                result.status,
            allowedStatuses:
                statuses,
            canUpdate:
                baseline.canUpdate
        )
    }
}
