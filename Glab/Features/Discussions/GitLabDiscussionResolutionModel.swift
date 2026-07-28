import Foundation
import Observation

nonisolated enum GitLabDiscussionResolutionPhase:
    Equatable,
    Sendable
{
    case idle
    case pending
    case refreshingReadiness
    case deliveryUnknown
    case checkingGitLab
    case retryAvailable
    case rejected
}

nonisolated enum GitLabDiscussionResolutionFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case readOnly
    case inactiveAccount
    case mutation(
        GitLabDiscussionMutationError,
        certainty:
            GitLabMutationDeliveryCertainty
    )
    case reconciliation(
        GitLabDiscussionMutationError
    )

    var description: String {
        "GitLabDiscussionResolutionFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        let error:
            GitLabDiscussionMutationError?
        switch self {
        case let .mutation(
            mutationError,
            _
        ):
            error = mutationError
        case let .reconciliation(
            reconciliationError
        ):
            error = reconciliationError
        case .readOnly,
             .inactiveAccount:
            error = nil
        }
        guard
            let authenticationFailure =
                error?.authenticationFailure,
            authenticationFailure
                .requiresReauthentication
        else {
            return nil
        }
        return authenticationFailure
    }
}

nonisolated struct GitLabDiscussionResolutionStatus:
    Equatable,
    Sendable
{
    let isResolved: Bool
    let phase:
        GitLabDiscussionResolutionPhase
    let desiredResolved: Bool?
    let resolvedBy: GitLabAPIUser?
    let resolvedAt: Date?
    let failure:
        GitLabDiscussionResolutionFailure?
}

@MainActor
@Observable
final class GitLabDiscussionResolutionModel {
    private struct TransientState:
        Equatable
    {
        let baseline:
            GitLabDiscussion
        let baselineResolution:
            GitLabDiscussionThreadResolution
        let desiredResolved: Bool
        let generation: UInt64
        var phase:
            GitLabDiscussionResolutionPhase
        var failure:
            GitLabDiscussionResolutionFailure?
    }

    let accountID: GitLabAccountID
    let route: GitLabMergeRequestRoute
    let apiAccess: GitLabAPIAccess

    private var states:
        [String: TransientState] = [:]

    @ObservationIgnored
    private let mutator:
        any GitLabDiscussionMutating
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let currentDiscussion:
        @MainActor (
            String
        ) -> GitLabDiscussion?
    @ObservationIgnored
    private let reconcile:
        @MainActor (
            GitLabDiscussion
        ) -> Bool
    @ObservationIgnored
    private let refreshReadiness:
        @MainActor () async -> Void
    @ObservationIgnored
    private var tasks:
        [String: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var taskGenerations:
        [String: UInt64] = [:]
    @ObservationIgnored
    private var nextGeneration: UInt64 = 0

    init(
        accountID: GitLabAccountID,
        route: GitLabMergeRequestRoute,
        apiAccess: GitLabAPIAccess,
        mutator:
            any GitLabDiscussionMutating,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        currentDiscussion:
            @escaping @MainActor (
                String
            ) -> GitLabDiscussion?,
        reconcile:
            @escaping @MainActor (
                GitLabDiscussion
            ) -> Bool,
        refreshReadiness:
            @escaping @MainActor () async
                -> Void
    ) {
        self.accountID = accountID
        self.route = route
        self.apiAccess = apiAccess
        self.mutator = mutator
        self.isAccountCurrent =
            isAccountCurrent
        self.currentDiscussion =
            currentDiscussion
        self.reconcile = reconcile
        self.refreshReadiness =
            refreshReadiness
    }

    deinit {
        for task in tasks.values {
            task.cancel()
        }
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        states.values.lazy
            .compactMap {
                $0.failure?
                    .authenticationFailure
            }
            .first
    }

    func status(
        for discussion: GitLabDiscussion
    ) -> GitLabDiscussionResolutionStatus?
    {
        guard
            let authoritative =
                discussion.threadResolution
        else {
            return nil
        }
        guard
            let state =
                states[discussion.id]
        else {
            return Self.status(
                resolution: authoritative,
                phase: .idle,
                desiredResolved: nil,
                failure: nil
            )
        }

        switch state.phase {
        case .pending,
             .deliveryUnknown,
             .checkingGitLab:
            return GitLabDiscussionResolutionStatus(
                isResolved:
                    state.desiredResolved,
                phase: state.phase,
                desiredResolved:
                    state.desiredResolved,
                resolvedBy: nil,
                resolvedAt: nil,
                failure: state.failure
            )
        case .refreshingReadiness:
            return Self.status(
                resolution:
                    state.baselineResolution,
                phase: state.phase,
                desiredResolved: nil,
                failure: nil
            )
        case .retryAvailable,
             .rejected:
            return Self.status(
                resolution:
                    state.baselineResolution,
                phase: state.phase,
                desiredResolved:
                    state.desiredResolved,
                failure: state.failure
            )
        case .idle:
            return Self.status(
                resolution: authoritative,
                phase: .idle,
                desiredResolved: nil,
                failure: nil
            )
        }
    }

    func toggle(
        _ discussion: GitLabDiscussion
    ) async {
        guard !Task.isCancelled else {
            return
        }
        let discussionID = discussion.id
        guard
            Self.isValidIdentity(
                discussionID
            ),
            tasks[discussionID] == nil
        else {
            return
        }
        if
            let phase =
                states[discussionID]?
                    .phase,
            phase == .pending
                || phase
                    == .deliveryUnknown
                || phase
                    == .checkingGitLab
                || phase
                    == .refreshingReadiness
                || phase
                    == .retryAvailable
        {
            return
        }
        guard
            let baseline =
                currentDiscussion(
                    discussionID
                ),
            let resolution =
                baseline.threadResolution
        else {
            return
        }
        guard apiAccess.canWrite else {
            recordRejectedStart(
                baseline: baseline,
                resolution: resolution,
                failure: .readOnly
            )
            return
        }
        guard isAccountCurrent() else {
            recordRejectedStart(
                baseline: baseline,
                resolution: resolution,
                failure: .inactiveAccount
            )
            return
        }

        await startMutation(
            baseline: baseline,
            resolution: resolution,
            desiredResolved:
                !resolution.isResolved
        )
    }

    func checkGitLab(
        discussionID: String
    ) async {
        guard
            !Task.isCancelled,
            tasks[discussionID] == nil,
            var state =
                states[discussionID],
            state.phase
                == .deliveryUnknown,
            isAccountCurrent()
        else {
            return
        }

        let generation =
            makeGeneration()
        state =
            TransientState(
                baseline: state.baseline,
                baselineResolution:
                    state.baselineResolution,
                desiredResolved:
                    state.desiredResolved,
                generation: generation,
                phase: .checkingGitLab,
                failure: nil
            )
        states[discussionID] = state

        let operation = Task {
            [weak self] in
            guard
                let self,
                !Task.isCancelled
            else {
                return
            }
            await self.performCheck(
                discussionID:
                    discussionID,
                generation: generation
            )
        }
        tasks[discussionID] =
            operation
        taskGenerations[discussionID] =
            generation
        await awaitOperation(
            operation,
            discussionID:
                discussionID,
            generation: generation
        )
    }

    func retry(
        discussionID: String
    ) async {
        guard
            !Task.isCancelled,
            tasks[discussionID] == nil,
            let state =
                states[discussionID],
            state.phase
                == .retryAvailable,
            apiAccess.canWrite,
            isAccountCurrent(),
            let current =
                currentDiscussion(
                    discussionID
                ),
            let resolution =
                current.threadResolution
        else {
            return
        }

        if
            resolution.isResolved
                == state.desiredResolved
        {
            states[discussionID] = nil
            await refreshReadiness()
            return
        }

        await startMutation(
            baseline: current,
            resolution: resolution,
            desiredResolved:
                state.desiredResolved
        )
    }

    func cancelAll() {
        nextGeneration &+= 1
        let activeTasks =
            Array(tasks.values)
        tasks.removeAll()
        taskGenerations.removeAll()
        states.removeAll()
        for task in activeTasks {
            task.cancel()
        }
    }

    private func startMutation(
        baseline: GitLabDiscussion,
        resolution:
            GitLabDiscussionThreadResolution,
        desiredResolved: Bool
    ) async {
        let discussionID =
            baseline.id
        let generation =
            makeGeneration()
        states[discussionID] =
            TransientState(
                baseline: baseline,
                baselineResolution:
                    resolution,
                desiredResolved:
                    desiredResolved,
                generation: generation,
                phase: .pending,
                failure: nil
            )

        let operation = Task {
            [weak self] in
            guard
                let self,
                !Task.isCancelled
            else {
                return
            }
            await self.performMutation(
                discussionID:
                    discussionID,
                generation: generation
            )
        }
        tasks[discussionID] =
            operation
        taskGenerations[discussionID] =
            generation
        await awaitOperation(
            operation,
            discussionID:
                discussionID,
            generation: generation
        )
    }

    private func performMutation(
        discussionID: String,
        generation: UInt64
    ) async {
        guard
            canPublish(
                discussionID:
                    discussionID,
                generation: generation
            ),
            !Task.isCancelled,
            let state =
                states[discussionID]
        else {
            clearIfCurrent(
                discussionID:
                    discussionID,
                generation: generation
            )
            return
        }

        do {
            let response =
                try await mutator
                    .setMergeRequestDiscussionResolution(
                        at: route,
                        discussionID:
                            discussionID,
                        resolved:
                            state.desiredResolved
                    )
            await handleMutationResponse(
                response,
                discussionID:
                    discussionID,
                generation: generation
            )
        } catch {
            guard
                canPublish(
                    discussionID:
                        discussionID,
                    generation: generation
                )
            else {
                return
            }
            recordMutationFailure(
                error,
                discussionID:
                    discussionID,
                generation: generation
            )
        }
    }

    private func handleMutationResponse(
        _ response: GitLabDiscussion,
        discussionID: String,
        generation: UInt64
    ) async {
        guard
            canPublish(
                discussionID:
                    discussionID,
                generation: generation
            ),
            let state =
                states[discussionID],
            response.id == discussionID,
            let responseResolution =
                response.threadResolution,
            responseResolution.isResolved
                == state.desiredResolved
        else {
            recordInvalidResponse(
                discussionID:
                    discussionID,
                generation: generation
            )
            return
        }

        if
            currentDiscussion(
                discussionID
            ) != state.baseline
        {
            await reconcileLatestDiscussion(
                discussionID:
                    discussionID,
                generation: generation
            )
            return
        }

        await completeAuthoritative(
            response,
            discussionID:
                discussionID,
            generation: generation
        )
    }

    private func reconcileLatestDiscussion(
        discussionID: String,
        generation: UInt64
    ) async {
        do {
            let latest =
                try await mutator
                    .loadMergeRequestDiscussion(
                        at: route,
                        discussionID:
                            discussionID
                    )
            guard
                latest.id
                    == discussionID,
                latest.threadResolution
                    != nil
            else {
                recordInvalidReconciliation(
                    discussionID:
                        discussionID,
                    generation: generation
                )
                return
            }
            await completeAuthoritative(
                latest,
                discussionID:
                    discussionID,
                generation: generation
            )
        } catch {
            guard
                canPublish(
                    discussionID:
                        discussionID,
                    generation: generation
                )
            else {
                return
            }
            recordReconciliationFailure(
                error,
                discussionID:
                    discussionID,
                generation: generation
            )
        }
    }

    private func performCheck(
        discussionID: String,
        generation: UInt64
    ) async {
        do {
            let discussion =
                try await mutator
                    .loadMergeRequestDiscussion(
                        at: route,
                        discussionID:
                            discussionID
                    )
            guard
                canPublish(
                    discussionID:
                        discussionID,
                    generation: generation
                ),
                discussion.id
                    == discussionID,
                let resolution =
                    discussion
                        .threadResolution,
                let state =
                    states[discussionID]
            else {
                recordInvalidReconciliation(
                    discussionID:
                        discussionID,
                    generation: generation
                )
                return
            }

            if
                resolution.isResolved
                    == state.desiredResolved
            {
                await completeAuthoritative(
                    discussion,
                    discussionID:
                        discussionID,
                    generation: generation
                )
            } else {
                _ = reconcile(discussion)
                guard
                    canPublish(
                        discussionID:
                            discussionID,
                        generation: generation
                    )
                else {
                    return
                }
                states[discussionID] =
                    TransientState(
                        baseline:
                            discussion,
                        baselineResolution:
                            resolution,
                        desiredResolved:
                            state
                            .desiredResolved,
                        generation:
                            generation,
                        phase:
                            .retryAvailable,
                        failure: nil
                    )
            }
        } catch {
            guard
                canPublish(
                    discussionID:
                        discussionID,
                    generation: generation
                )
            else {
                return
            }
            recordReconciliationFailure(
                error,
                discussionID:
                    discussionID,
                generation: generation
            )
        }
    }

    private func completeAuthoritative(
        _ discussion: GitLabDiscussion,
        discussionID: String,
        generation: UInt64
    ) async {
        guard
            canPublish(
                discussionID:
                    discussionID,
                generation: generation
            )
        else {
            return
        }
        _ = reconcile(discussion)
        guard
            let resolution =
                discussion.threadResolution
        else {
            recordInvalidReconciliation(
                discussionID:
                    discussionID,
                generation: generation
            )
            return
        }
        states[discussionID] =
            TransientState(
                baseline: discussion,
                baselineResolution:
                    resolution,
                desiredResolved:
                    resolution.isResolved,
                generation: generation,
                phase:
                    .refreshingReadiness,
                failure: nil
            )
        await refreshReadiness()
        clearIfCurrent(
            discussionID: discussionID,
            generation: generation
        )
    }

    private func recordMutationFailure(
        _ error:
            GitLabDiscussionMutationError,
        discussionID: String,
        generation: UInt64
    ) {
        guard
            var state =
                currentState(
                    discussionID:
                        discussionID,
                    generation: generation
                )
        else {
            return
        }
        let certainty =
            error.deliveryCertainty
        state.phase =
            certainty
                == .deliveryUnknown
                ? .deliveryUnknown
                : .rejected
        state.failure =
            .mutation(
                error,
                certainty: certainty
            )
        states[discussionID] = state
    }

    private func recordInvalidResponse(
        discussionID: String,
        generation: UInt64
    ) {
        recordMutationFailure(
            .request(
                .api(.invalidResponse)
            ),
            discussionID:
                discussionID,
            generation: generation
        )
    }

    private func recordInvalidReconciliation(
        discussionID: String,
        generation: UInt64
    ) {
        recordReconciliationFailure(
            .request(
                .api(.invalidResponse)
            ),
            discussionID:
                discussionID,
            generation: generation
        )
    }

    private func recordReconciliationFailure(
        _ error:
            GitLabDiscussionMutationError,
        discussionID: String,
        generation: UInt64
    ) {
        guard
            var state =
                currentState(
                    discussionID:
                        discussionID,
                    generation: generation
                )
        else {
            return
        }
        state.phase = .deliveryUnknown
        state.failure =
            .reconciliation(error)
        states[discussionID] = state
    }

    private func recordRejectedStart(
        baseline: GitLabDiscussion,
        resolution:
            GitLabDiscussionThreadResolution,
        failure:
            GitLabDiscussionResolutionFailure
    ) {
        let generation =
            makeGeneration()
        states[baseline.id] =
            TransientState(
                baseline: baseline,
                baselineResolution:
                    resolution,
                desiredResolved:
                    !resolution.isResolved,
                generation: generation,
                phase: .rejected,
                failure: failure
            )
    }

    private func awaitOperation(
        _ operation: Task<Void, Never>,
        discussionID: String,
        generation: UInt64
    ) async {
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        guard
            taskGenerations[
                discussionID
            ] == generation
        else {
            return
        }
        tasks[discussionID] = nil
        taskGenerations[discussionID] =
            nil
        guard isAccountCurrent() else {
            states[discussionID] = nil
            return
        }
        if
            Task.isCancelled,
            states[discussionID]?
                .phase == .pending
        {
            states[discussionID] = nil
        }
    }

    private func clearIfCurrent(
        discussionID: String,
        generation: UInt64
    ) {
        guard
            states[discussionID]?
                .generation == generation
        else {
            return
        }
        states[discussionID] = nil
    }

    private func currentState(
        discussionID: String,
        generation: UInt64
    ) -> TransientState? {
        guard
            let state =
                states[discussionID],
            state.generation == generation,
            isAccountCurrent()
        else {
            return nil
        }
        return state
    }

    private func canPublish(
        discussionID: String,
        generation: UInt64
    ) -> Bool {
        states[discussionID]?
            .generation == generation
            && isAccountCurrent()
    }

    private func makeGeneration()
        -> UInt64
    {
        nextGeneration &+= 1
        return nextGeneration
    }

    private static func status(
        resolution:
            GitLabDiscussionThreadResolution,
        phase:
            GitLabDiscussionResolutionPhase,
        desiredResolved: Bool?,
        failure:
            GitLabDiscussionResolutionFailure?
    ) -> GitLabDiscussionResolutionStatus {
        GitLabDiscussionResolutionStatus(
            isResolved:
                resolution.isResolved,
            phase: phase,
            desiredResolved:
                desiredResolved,
            resolvedBy:
                resolution.resolvedBy,
            resolvedAt:
                resolution.resolvedAt,
            failure: failure
        )
    }

    private static func isValidIdentity(
        _ discussionID: String
    ) -> Bool {
        !discussionID
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
    }
}
