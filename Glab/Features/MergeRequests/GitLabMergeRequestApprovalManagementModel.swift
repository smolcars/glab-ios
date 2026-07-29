import Foundation
import Observation

nonisolated enum
    GitLabMergeRequestApprovalManagementAction:
    Equatable,
    Sendable
{
    case approve
    case unapprove
}

nonisolated enum
    GitLabMergeRequestApprovalManagementPhase:
    Equatable,
    Sendable
{
    case idle
    case preflighting
    case mutating
    case reconciling
    case checkingGitLab
}

nonisolated struct
    GitLabMergeRequestApprovalConfirmation:
    Equatable,
    Sendable
{
    let action:
        GitLabMergeRequestApprovalManagementAction
    let headSHA: String
}

nonisolated enum
    GitLabMergeRequestApprovalManagementFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case load(
        GitLabSessionClientError
    )
    case readOnly
    case accountChanged
    case unavailable
    case staleRevision
    case approvalSyncing
    case permissionDenied
    case gitLabReauthenticationRequired
    case rejected(
        GitLabSessionClientError
    )
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
             .accountChanged,
             .unavailable,
             .staleRevision,
             .approvalSyncing,
             .permissionDenied,
             .gitLabReauthenticationRequired,
             .rejected,
             .deliveryUnknown,
             .authoritativeMismatch,
             .notApplied:
            nil
        }
    }

    var description: String {
        "GitLabMergeRequestApprovalManagementFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
@Observable
final class
    GitLabMergeRequestApprovalManagementModel
{
    private(set) var phase =
        GitLabMergeRequestApprovalManagementPhase
            .idle
    private(set) var failure:
        GitLabMergeRequestApprovalManagementFailure?
    private(set) var confirmation:
        GitLabMergeRequestApprovalConfirmation?

    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let route:
        GitLabMergeRequestRoute
    @ObservationIgnored
    private let accountID:
        GitLabAccountID
    @ObservationIgnored
    private let service:
        any GitLabMergeRequestApprovalServing
    @ObservationIgnored
    private let currentMergeRequest:
        @MainActor () -> GitLabMergeRequest?
    @ObservationIgnored
    private let currentApprovalSummary:
        @MainActor () -> GitLabMergeRequestApprovalSummary?
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onMergeRequestReconciled:
        @MainActor (
            GitLabMergeRequest
        ) -> Void
    @ObservationIgnored
    private let onApprovalSummaryReconciled:
        @MainActor (
            GitLabMergeRequestApprovalSummary
        ) -> Void
    @ObservationIgnored
    private var pendingMutation:
        PendingMutation?
    @ObservationIgnored
    private var operationGeneration:
        UInt64 = 0

    init(
        route: GitLabMergeRequestRoute,
        accountID: GitLabAccountID,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabMergeRequestApprovalServing,
        currentMergeRequest:
            @escaping @MainActor ()
                -> GitLabMergeRequest?,
        currentApprovalSummary:
            @escaping @MainActor ()
                -> GitLabMergeRequestApprovalSummary?,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onMergeRequestReconciled:
            @escaping @MainActor (
                GitLabMergeRequest
            ) -> Void,
        onApprovalSummaryReconciled:
            @escaping @MainActor (
                GitLabMergeRequestApprovalSummary
            ) -> Void
    ) {
        self.route = route
        self.accountID = accountID
        self.apiAccess = apiAccess
        self.service = service
        self.currentMergeRequest =
            currentMergeRequest
        self.currentApprovalSummary =
            currentApprovalSummary
        self.isAccountCurrent =
            isAccountCurrent
        self.onMergeRequestReconciled =
            onMergeRequestReconciled
        self.onApprovalSummaryReconciled =
            onApprovalSummaryReconciled
    }

    var isBusy: Bool {
        phase != .idle
    }

    var hasUnresolvedMutation: Bool {
        pendingMutation != nil
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    var canApprove: Bool {
        canRequest(.approve)
    }

    var canUnapprove: Bool {
        canRequest(.unapprove)
    }

    func requestApprove() {
        request(.approve)
    }

    func requestUnapprove() {
        request(.unapprove)
    }

    func cancelConfirmation() {
        confirmation = nil
    }

    func confirmAction() async {
        guard
            phase == .idle,
            pendingMutation == nil,
            let confirmation
        else {
            return
        }
        self.confirmation = nil
        failure = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard
            let rendered =
                currentMergeRequest(),
            rendered.route == route,
            rendered.stateKind == .opened,
            rendered.diffHeadSHA
                == confirmation.headSHA
        else {
            failure = .staleRevision
            return
        }
        guard
            !Self.isApprovalSyncing(
                rendered
            )
        else {
            failure = .approvalSyncing
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        phase = .preflighting
        defer {
            if
                operationGeneration
                    == generation
            {
                phase = .idle
            }
        }

        let freshMergeRequest:
            GitLabMergeRequest
        do {
            freshMergeRequest =
                try await service
                    .loadLatestMergeRequest(
                        at: route
                    )
        } catch {
            publishReadFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onMergeRequestReconciled(
            freshMergeRequest
        )
        guard
            freshMergeRequest.route
                == route
        else {
            failure =
                .authoritativeMismatch
            return
        }
        guard
            freshMergeRequest.stateKind
                == .opened,
            freshMergeRequest.diffHeadSHA
                == confirmation.headSHA
        else {
            failure = .staleRevision
            return
        }
        guard
            !Self.isApprovalSyncing(
                freshMergeRequest
            )
        else {
            failure = .approvalSyncing
            return
        }

        let freshSummary:
            GitLabMergeRequestApprovalSummary
        do {
            freshSummary =
                try await service
                    .loadApprovalSummary(
                        at: route
                    )
        } catch {
            publishReadFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onApprovalSummaryReconciled(
            freshSummary
        )
        guard
            Self.requiresMutation(
                confirmation.action,
                summary: freshSummary,
                userID: accountID.userID
            )
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let pending =
            PendingMutation(
                action:
                    confirmation.action,
                route: route,
                headSHA:
                    confirmation.headSHA,
                userID:
                    accountID.userID
            )
        pendingMutation = pending
        failure = .deliveryUnknown
        phase = .mutating

        do {
            switch confirmation.action {
            case .approve:
                _ = try await service.approve(
                    at: route,
                    sha:
                        confirmation.headSHA
                )
            case .unapprove:
                _ = try await service
                    .unapprove(at: route)
            }
        } catch {
            handleMutationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        phase = .reconciling
        await reconcilePendingMutation(
            generation: generation
        )
    }

    func checkGitLab() async {
        guard
            phase == .idle,
            pendingMutation != nil,
            isAccountCurrent()
        else {
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        phase = .checkingGitLab
        defer {
            if
                operationGeneration
                    == generation
            {
                phase = .idle
            }
        }

        await reconcilePendingMutation(
            generation: generation
        )
    }
}

private extension
    GitLabMergeRequestApprovalManagementModel
{
    nonisolated struct PendingMutation:
        Equatable,
        Sendable
    {
        let action:
            GitLabMergeRequestApprovalManagementAction
        let route:
            GitLabMergeRequestRoute
        let headSHA: String
        let userID: Int
    }

    func request(
        _ action:
            GitLabMergeRequestApprovalManagementAction
    ) {
        guard
            phase == .idle,
            confirmation == nil,
            pendingMutation == nil
        else {
            return
        }
        failure = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard
            let mergeRequest =
                currentMergeRequest(),
            mergeRequest.route == route,
            mergeRequest.stateKind
                == .opened,
            let headSHA =
                mergeRequest.diffHeadSHA,
            let summary =
                currentApprovalSummary()
        else {
            failure = .unavailable
            return
        }
        guard
            !Self.isApprovalSyncing(
                mergeRequest
            )
        else {
            failure = .approvalSyncing
            return
        }
        guard
            Self.requiresMutation(
                action,
                summary: summary,
                userID:
                    accountID.userID
            )
        else {
            return
        }

        confirmation =
            GitLabMergeRequestApprovalConfirmation(
                action: action,
                headSHA: headSHA
            )
    }

    func canRequest(
        _ action:
            GitLabMergeRequestApprovalManagementAction
    ) -> Bool {
        guard
            apiAccess.canWrite,
            isAccountCurrent(),
            phase == .idle,
            confirmation == nil,
            pendingMutation == nil,
            let mergeRequest =
                currentMergeRequest(),
            mergeRequest.route == route,
            mergeRequest.stateKind
                == .opened,
            mergeRequest.diffHeadSHA != nil,
            !Self.isApprovalSyncing(
                mergeRequest
            ),
            let summary =
                currentApprovalSummary()
        else {
            return false
        }
        return Self.requiresMutation(
            action,
            summary: summary,
            userID: accountID.userID
        )
    }

    func reconcilePendingMutation(
        generation: UInt64
    ) async {
        guard
            let pending =
                pendingMutation
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let mergeRequest:
            GitLabMergeRequest
        do {
            mergeRequest =
                try await service
                    .loadLatestMergeRequest(
                        at: pending.route
                    )
        } catch {
            publishReconciliationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onMergeRequestReconciled(
            mergeRequest
        )
        guard
            mergeRequest.route
                == pending.route
        else {
            failure =
                .authoritativeMismatch
            return
        }
        guard
            mergeRequest.diffHeadSHA
                == pending.headSHA
        else {
            pendingMutation = nil
            failure = .staleRevision
            return
        }

        let summary:
            GitLabMergeRequestApprovalSummary
        do {
            summary =
                try await service
                    .loadApprovalSummary(
                        at: pending.route
                    )
        } catch {
            publishReconciliationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onApprovalSummaryReconciled(
            summary
        )
        let isApproved =
            Self.isApproved(
                userID: pending.userID,
                in: summary
            )
        let wasApplied =
            switch pending.action {
            case .approve:
                isApproved
            case .unapprove:
                !isApproved
            }

        pendingMutation = nil
        failure =
            wasApplied
            ? nil
            : .notApplied
    }

    func publishReadFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard canPublish(generation) else {
            return
        }
        failure = .load(error)
    }

    func publishReconciliationFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard canPublish(generation) else {
            return
        }
        failure =
            .reconciliation(error)
    }

    func handleMutationFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard
            operationGeneration
                == generation
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        switch error {
        case .api(
            .validation(
                statusCode: 409
            )
        ):
            pendingMutation = nil
            failure = .staleRevision
        case .api(.forbidden):
            pendingMutation = nil
            failure = .permissionDenied
        case .api(.unauthenticated):
            pendingMutation = nil
            failure =
                .gitLabReauthenticationRequired
        default:
            if
                error.mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                failure = .deliveryUnknown
            } else {
                pendingMutation = nil
                failure = .rejected(error)
            }
        }
    }

    func canPublish(
        _ generation: UInt64
    ) -> Bool {
        operationGeneration == generation
            && !Task.isCancelled
            && isAccountCurrent()
    }

    nonisolated static func
        requiresMutation(
            _ action:
                GitLabMergeRequestApprovalManagementAction,
            summary:
                GitLabMergeRequestApprovalSummary,
            userID: Int
        ) -> Bool
    {
        let approved = isApproved(
            userID: userID,
            in: summary
        )
        return switch action {
        case .approve:
            !approved
        case .unapprove:
            approved
        }
    }

    nonisolated static func isApproved(
        userID: Int,
        in summary:
            GitLabMergeRequestApprovalSummary
    ) -> Bool {
        summary.approvedBy.contains {
            $0.user?.id == userID
        }
    }

    nonisolated static func
        isApprovalSyncing(
            _ mergeRequest:
                GitLabMergeRequest
        ) -> Bool
    {
        let status =
            mergeRequest
                .detailedMergeStatus?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
        return status == "checking"
            || status
                == "approvals_syncing"
    }
}
