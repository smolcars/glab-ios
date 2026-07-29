import Foundation
import Observation

nonisolated enum
    GitLabMergeRequestMergePhase:
    Equatable,
    Sendable
{
    case idle
    case preflighting
    case mutating
    case reconciling
}

nonisolated struct
    GitLabMergeRequestMergeConfirmation:
    Equatable,
    Sendable
{
    let action:
        GitLabMergeRequestMergeAction
    let route: GitLabMergeRequestRoute
    let title: String
    let sourceBranch: String
    let targetBranch: String
    let headSHA: String
}

nonisolated enum
    GitLabMergeRequestMergeFailure:
    Equatable,
    Sendable
{
    case readOnly
    case accountChanged
    case staleRevision
    case permissionDenied
    case unavailable
    case blocked(
        [GitLabMergeRequestMergeBlockReason]
    )
    case notApplied
    case load(GitLabSessionClientError)
    case rejected(GitLabSessionClientError)
    case reconciliation(
        GitLabSessionClientError
    )

    var authenticationFailure:
        GitLabSessionClientError?
    {
        switch self {
        case let .load(error),
             let .rejected(error),
             let .reconciliation(error):
            error.requiresReauthentication
                ? error
                : nil
        case .readOnly,
             .accountChanged,
             .staleRevision,
             .permissionDenied,
             .unavailable,
             .blocked,
             .notApplied:
            nil
        }
    }

    var message: String {
        switch self {
        case .readOnly:
            "This account has read-only API access."
        case .accountChanged:
            "The active GitLab account changed. Reopen this merge request and try again."
        case .staleRevision:
            "The source branch changed. Review the latest changes before trying again."
        case .permissionDenied:
            "GitLab did not allow this account to merge the request."
        case .unavailable:
            "This merge action is no longer available. Refresh the merge request and try again."
        case .blocked:
            "GitLab reports that this merge request is not ready to merge."
        case .notApplied:
            "GitLab did not apply the merge action. Review the current merge status before trying again."
        case let .load(error),
             let .rejected(error):
            error.description
        case let .reconciliation(error):
            "Glab could not verify GitLab’s result. Check this merge request in GitLab before trying again. \(error.description)"
        }
    }
}

@MainActor
@Observable
final class GitLabMergeRequestMergeModel {
    let accountID: GitLabAccountID
    let route: GitLabMergeRequestRoute
    let apiAccess: GitLabAPIAccess

    private(set) var phase:
        GitLabMergeRequestMergePhase = .idle
    private(set) var confirmation:
        GitLabMergeRequestMergeConfirmation?
    private(set) var failure:
        GitLabMergeRequestMergeFailure?

    @ObservationIgnored
    private let service:
        any GitLabMergeRequestMergeServing
    @ObservationIgnored
    private let currentMergeRequest:
        @MainActor () -> GitLabMergeRequest?
    @ObservationIgnored
    private let currentApprovalSummary:
        @MainActor ()
            -> GitLabMergeRequestApprovalSummary?
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
    private let onResourceEdited:
        @MainActor (
            GitLabResourceEditResult
        ) -> Void
    @ObservationIgnored
    private var operationGeneration:
        UInt64 = 0

    init(
        accountID: GitLabAccountID,
        route: GitLabMergeRequestRoute,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabMergeRequestMergeServing,
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
            ) -> Void,
        onResourceEdited:
            @escaping @MainActor (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.accountID = accountID
        self.route = route
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
        self.onResourceEdited =
            onResourceEdited
    }

    var isBusy: Bool {
        phase != .idle
    }

    var eligibility:
        GitLabMergeRequestMergeEligibility
    {
        guard
            let mergeRequest =
                currentMergeRequest(),
            mergeRequest.route == route,
            let summary =
                currentApprovalSummary()
        else {
            return .unavailable
        }
        return Self.eligibility(
            mergeRequest: mergeRequest,
            approvalSummary: summary,
            apiAccess: apiAccess
        )
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    func request(
        _ action:
            GitLabMergeRequestMergeAction
    ) async {
        guard
            phase == .idle,
            confirmation == nil
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

        let preflight:
            GitLabMergeRequestMergePreflight
        do {
            preflight =
                try await service.preflight(
                    at: route
                )
        } catch {
            guard canPublish(generation) else {
                return
            }
            failure = .load(error)
            return
        }
        guard canPublish(generation) else {
            return
        }
        guard
            preflight.mergeRequest.route
                == route
        else {
            failure = .unavailable
            return
        }
        onMergeRequestReconciled(
            preflight.mergeRequest
        )
        onApprovalSummaryReconciled(
            preflight.approvalSummary
        )

        let eligibility =
            Self.eligibility(
                mergeRequest:
                    preflight.mergeRequest,
                approvalSummary:
                    preflight
                    .approvalSummary,
                apiAccess: apiAccess
            )
        guard
            Self.action(
                action,
                matches: eligibility
            )
        else {
            failure =
                Self.failure(
                    for: eligibility
                )
            return
        }
        guard
            let headSHA =
                preflight.mergeRequest
                    .diffHeadSHA
        else {
            failure = .unavailable
            return
        }
        confirmation =
            GitLabMergeRequestMergeConfirmation(
                action: action,
                route: route,
                title:
                    preflight
                    .mergeRequest.title,
                sourceBranch:
                    preflight
                    .mergeRequest
                    .sourceBranch,
                targetBranch:
                    preflight
                    .mergeRequest
                    .targetBranch,
                headSHA: headSHA
            )
    }

    func dismissConfirmation() {
        guard phase == .idle else {
            return
        }
        confirmation = nil
    }

    func dismissFailure() {
        failure = nil
    }

    func cancel() {
        operationGeneration &+= 1
        confirmation = nil
        phase = .idle
    }

    func confirm() async {
        guard
            phase == .idle,
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
            confirmation.route == route,
            let rendered =
                currentMergeRequest(),
            rendered.route == route,
            rendered.diffHeadSHA
                == confirmation.headSHA,
            Self.action(
                confirmation.action,
                matches: eligibility
            )
        else {
            failure = .staleRevision
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        phase = .mutating
        defer {
            if
                operationGeneration
                    == generation
            {
                phase = .idle
            }
        }

        do {
            let response =
                try await service.merge(
                    at: route,
                    sha:
                        confirmation.headSHA,
                    action:
                        confirmation.action
                )
            guard canPublish(generation) else {
                return
            }
            publish(response)
            phase = .reconciling
            await reconcile(
                confirmation,
                generation: generation,
                preferredFailure: nil
            )
        } catch {
            guard canPublish(generation) else {
                return
            }
            await handleMutationFailure(
                error,
                confirmation: confirmation,
                generation: generation
            )
        }
    }
}

private extension
    GitLabMergeRequestMergeModel
{
    static func eligibility(
        mergeRequest: GitLabMergeRequest,
        approvalSummary:
            GitLabMergeRequestApprovalSummary,
        apiAccess: GitLabAPIAccess
    ) -> GitLabMergeRequestMergeEligibility {
        GitLabMergeRequestMergeEligibility(
            mergeRequest: mergeRequest,
            readiness:
                GitLabMergeRequestReadiness(
                    mergeRequest:
                        mergeRequest,
                    approvalState:
                        .loaded(
                            .available(
                                approvalSummary
                            )
                        )
                ),
            apiAccess: apiAccess
        )
    }

    static func action(
        _ action:
            GitLabMergeRequestMergeAction,
        matches eligibility:
            GitLabMergeRequestMergeEligibility
    ) -> Bool {
        switch (action, eligibility) {
        case (.mergeNow, .mergeNow),
             (.autoMerge, .autoMerge):
            true
        default:
            false
        }
    }

    static func failure(
        for eligibility:
            GitLabMergeRequestMergeEligibility
    ) -> GitLabMergeRequestMergeFailure {
        switch eligibility {
        case let .blocked(reasons):
            .blocked(reasons)
        case .mergeNow,
             .autoMerge,
             .alreadyAutoMerging,
             .checking,
             .unavailable:
            .unavailable
        }
    }

    func canPublish(
        _ generation: UInt64
    ) -> Bool {
        operationGeneration == generation
            && !Task.isCancelled
            && isAccountCurrent()
    }

    func publish(
        _ mergeRequest:
            GitLabMergeRequest
    ) {
        onMergeRequestReconciled(
            mergeRequest
        )
        onResourceEdited(
            .mergeRequest(mergeRequest)
        )
    }

    func handleMutationFailure(
        _ error:
            GitLabSessionClientError,
        confirmation:
            GitLabMergeRequestMergeConfirmation,
        generation: UInt64
    ) async {
        switch error {
        case .api(
            .validation(
                statusCode: 409
            )
        ):
            phase = .reconciling
            await reconcile(
                confirmation,
                generation: generation,
                preferredFailure:
                    .staleRevision
            )
        case .api(.forbidden),
             .api(.unauthenticated):
            failure =
                error.requiresReauthentication
                ? .rejected(error)
                : .permissionDenied
        default:
            guard
                error
                    .mutationDeliveryCertainty
                    == .deliveryUnknown
            else {
                failure = .rejected(error)
                return
            }
            phase = .reconciling
            await reconcile(
                confirmation,
                generation: generation,
                preferredFailure: nil
            )
        }
    }

    func reconcile(
        _ confirmation:
            GitLabMergeRequestMergeConfirmation,
        generation: UInt64,
        preferredFailure:
            GitLabMergeRequestMergeFailure?
    ) async {
        let preflight:
            GitLabMergeRequestMergePreflight
        do {
            preflight =
                try await service.preflight(
                    at: confirmation.route
                )
        } catch {
            guard canPublish(generation) else {
                return
            }
            failure =
                preferredFailure
                ?? .reconciliation(error)
            return
        }
        guard canPublish(generation) else {
            return
        }
        guard
            preflight.mergeRequest.route
                == route
        else {
            failure = .unavailable
            return
        }
        let shouldPropagateResourceEdit =
            currentMergeRequest()
            != preflight.mergeRequest
        onMergeRequestReconciled(
            preflight.mergeRequest
        )
        onApprovalSummaryReconciled(
            preflight.approvalSummary
        )

        if
            Self.wasApplied(
                confirmation.action,
                to: preflight.mergeRequest
            )
        {
            if shouldPropagateResourceEdit {
                onResourceEdited(
                    .mergeRequest(
                        preflight
                            .mergeRequest
                    )
                )
            }
            failure = nil
            return
        }
        if let preferredFailure {
            failure = preferredFailure
            return
        }
        if
            preflight.mergeRequest
                .diffHeadSHA
                != confirmation.headSHA
        {
            failure = .staleRevision
            return
        }
        failure = .notApplied
    }

    static func wasApplied(
        _ action:
            GitLabMergeRequestMergeAction,
        to mergeRequest:
            GitLabMergeRequest
    ) -> Bool {
        if mergeRequest.stateKind == .merged {
            return true
        }
        return action == .autoMerge
            && mergeRequest
                .mergeWhenPipelineSucceeds
                == true
    }
}
