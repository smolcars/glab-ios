import Foundation
import Observation

nonisolated enum
    GitLabDescriptionTaskTogglePhase:
    Equatable,
    Sendable
{
    case idle
    case rewriting
    case restoringDraft
    case saving
    case deliveryUnknown
    case checkingGitLab
    case retryAvailable
}

nonisolated enum
    GitLabDescriptionTaskToggleFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case readOnly
    case inapplicable
    case staleDescription
    case existingDraft(
        requiresDeliveryCheck: Bool
    )
    case rewrite
    case editor(GitLabResourceEditorFailure)

    var description: String {
        "GitLabDescriptionTaskToggleFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .editor(failure) = self
        else {
            return nil
        }
        return failure.authenticationFailure
    }
}

@MainActor
@Observable
final class GitLabDescriptionTaskToggleModel {
    typealias Rewrite =
        @Sendable (
            String,
            GitLabMarkdownIndexedTask,
            GitLabMarkdownTaskState
        ) async throws -> String

    private(set) var phase =
        GitLabDescriptionTaskTogglePhase.idle
    private(set) var failure:
        GitLabDescriptionTaskToggleFailure?
    private(set) var activeTaskSourceID:
        GitLabMarkdownTaskSourceID?
    private(set) var intendedState:
        GitLabMarkdownTaskState?

    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let accountID: GitLabAccountID
    @ObservationIgnored
    private let service:
        any GitLabResourceEditing
    @ObservationIgnored
    private let draftStore:
        any GitLabResourceEditDraftStoring
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onSuccess:
        @MainActor (
            GitLabResourceEditResult
        ) -> Void
    @ObservationIgnored
    private let onStale:
        @MainActor () async -> Void
    @ObservationIgnored
    private let rewrite: Rewrite
    @ObservationIgnored
    private var editorModel:
        GitLabResourceEditorModel?
    @ObservationIgnored
    private var operationTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var operationGeneration: UInt64 = 0

    init(
        accountID: GitLabAccountID,
        apiAccess: GitLabAPIAccess,
        service: any GitLabResourceEditing,
        draftStore:
            any GitLabResourceEditDraftStoring,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onSuccess:
            @escaping @MainActor (
                GitLabResourceEditResult
            ) -> Void,
        onStale:
            @escaping @MainActor () async
                -> Void,
        rewrite:
            @escaping Rewrite = {
                source,
                task,
                state in
                try await
                    GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source,
                        task: task,
                        to: state
                    )
            }
    ) {
        self.accountID = accountID
        self.apiAccess = apiAccess
        self.service = service
        self.draftStore = draftStore
        self.isAccountCurrent =
            isAccountCurrent
        self.onSuccess = onSuccess
        self.onStale = onStale
        self.rewrite = rewrite
    }

    deinit {
        operationTask?.cancel()
    }

    var isBusy: Bool {
        switch phase {
        case .rewriting,
             .restoringDraft,
             .saving,
             .checkingGitLab:
            true
        case .idle,
             .deliveryUnknown,
             .retryAvailable:
            false
        }
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    func displayedState(
        for task: GitLabMarkdownIndexedTask
    ) -> GitLabMarkdownTaskState {
        guard
            activeTaskSourceID
                == task.sourceID,
            let intendedState,
            phase != .idle
        else {
            return task.state
        }
        return intendedState
    }

    func toggle(
        _ task: GitLabMarkdownIndexedTask,
        in snapshot:
            GitLabResourceEditSnapshot
    ) async {
        guard
            phase == .idle,
            operationTask == nil
        else {
            return
        }
        failure = nil
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard task.state != .inapplicable else {
            failure = .inapplicable
            return
        }

        let desiredState:
            GitLabMarkdownTaskState =
                task.state == .complete
                ? .incomplete
                : .complete
        operationGeneration &+= 1
        let generation = operationGeneration
        activeTaskSourceID = task.sourceID
        intendedState = desiredState
        phase = .rewriting

        let operation = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performToggle(
                task,
                desiredState: desiredState,
                snapshot: snapshot,
                generation: generation
            )
        }
        operationTask = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        finishOperation(
            generation: generation
        )
    }

    func checkGitLab() async {
        guard
            phase == .deliveryUnknown,
            operationTask == nil,
            let editorModel,
            editorModel.canCheckGitLab
        else {
            return
        }

        let generation = operationGeneration
        phase = .checkingGitLab
        failure = nil
        let operation = Task { [weak self] in
            await editorModel.checkGitLab()
            guard let self else {
                return
            }
            await self.resolveReconciliation(
                editorModel,
                generation: generation
            )
        }
        operationTask = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        finishOperation(
            generation: generation
        )
    }

    func retry() async {
        guard
            phase == .retryAvailable,
            operationTask == nil,
            let editorModel,
            editorModel.canSave
        else {
            return
        }

        let generation = operationGeneration
        phase = .saving
        failure = nil
        let operation = Task { [weak self] in
            await editorModel.save()
            guard let self else {
                return
            }
            await self.resolveSave(
                editorModel,
                generation: generation
            )
        }
        operationTask = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
        }
        finishOperation(
            generation: generation
        )
    }

    func cancel() {
        operationGeneration &+= 1
        operationTask?.cancel()
        operationTask = nil
        editorModel?.cancelActiveOperation()
        editorModel = nil
        phase = .idle
        failure = nil
        activeTaskSourceID = nil
        intendedState = nil
    }

    func takeRecoveryEditor()
        -> GitLabResourceEditorModel?
    {
        guard operationTask == nil else {
            return nil
        }
        let result = editorModel
        editorModel = nil
        operationGeneration &+= 1
        phase = .idle
        failure = nil
        activeTaskSourceID = nil
        intendedState = nil
        return result
    }

    private func performToggle(
        _ task: GitLabMarkdownIndexedTask,
        desiredState:
            GitLabMarkdownTaskState,
        snapshot:
            GitLabResourceEditSnapshot,
        generation: UInt64
    ) async {
        let rewrittenDescription: String
        do {
            rewrittenDescription =
                try await rewrite(
                    snapshot.rawDescription,
                    task,
                    desiredState
                )
        } catch is CancellationError {
            resetAfterCancellation(
                generation: generation
            )
            return
        } catch let error
            as GitLabMarkdownTaskRewriteError
        {
            switch error {
            case .staleSource, .invalidTask:
                await failAsStale(
                    generation: generation
                )
            case .inapplicable:
                reset(
                    failure: .inapplicable,
                    generation: generation
                )
            case .noChange:
                reset(
                    failure: .rewrite,
                    generation: generation
                )
            }
            return
        } catch {
            reset(
                failure: .rewrite,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        guard !Task.isCancelled else {
            resetAfterCancellation(
                generation: generation
            )
            return
        }

        phase = .restoringDraft
        let editor =
            GitLabResourceEditorModel(
                accountID: accountID,
                baseline: snapshot,
                apiAccess: apiAccess,
                service: service,
                draftStore: draftStore,
                isAccountCurrent:
                    isAccountCurrent,
                onSuccess: {
                    [weak self] result in
                    guard
                        let self,
                        self.canPublish(
                            generation
                        )
                    else {
                        return
                    }
                    self.onSuccess(result)
                }
            )
        editorModel = editor
        await editor.restoreDraft()

        guard canPublish(generation) else {
            return
        }
        guard !Task.isCancelled else {
            editorModel = nil
            resetAfterCancellation(
                generation: generation
            )
            return
        }
        guard
            !editor.isDirty,
            !editor.requiresDeliveryCheck
        else {
            let requiresDeliveryCheck =
                editor.requiresDeliveryCheck
            editorModel = nil
            reset(
                failure:
                    .existingDraft(
                        requiresDeliveryCheck:
                            requiresDeliveryCheck
                    ),
                generation: generation
            )
            return
        }

        editor.rawDescription =
            rewrittenDescription
        phase = .saving
        await editor.save()
        guard canPublish(generation) else {
            return
        }
        await resolveSave(
            editor,
            generation: generation
        )
    }

    private func resolveSave(
        _ editor:
            GitLabResourceEditorModel,
        generation: UInt64
    ) async {
        guard canPublish(generation) else {
            return
        }
        if editor.didSucceed {
            reset(
                failure: nil,
                generation: generation
            )
            return
        }
        if editor.requiresDeliveryCheck {
            phase = .deliveryUnknown
            failure = editor.failure.map {
                .editor($0)
            }
            return
        }

        let editorFailure = editor.failure
        let isStale: Bool
        if case .conflict = editorFailure {
            isStale = true
        } else {
            isStale = false
        }
        _ = await editor.discardDraft()
        guard canPublish(generation) else {
            return
        }

        if isStale {
            await failAsStale(
                generation: generation
            )
        } else {
            reset(
                failure:
                    editorFailure.map {
                        .editor($0)
                    },
                generation: generation
            )
        }
    }

    private func resolveReconciliation(
        _ editor:
            GitLabResourceEditorModel,
        generation: UInt64
    ) async {
        guard canPublish(generation) else {
            return
        }
        if editor.didSucceed {
            reset(
                failure: nil,
                generation: generation
            )
            return
        }
        if editor.requiresDeliveryCheck {
            phase = .deliveryUnknown
            failure = editor.failure.map {
                .editor($0)
            }
            if case .conflict = editor.failure {
                await onStale()
            }
            return
        }
        if editor.isDirty {
            phase = .retryAvailable
            failure = nil
            return
        }

        reset(
            failure:
                editor.failure.map {
                    .editor($0)
                },
            generation: generation
        )
    }

    private func failAsStale(
        generation: UInt64
    ) async {
        reset(
            failure: .staleDescription,
            generation: generation
        )
        guard canPublish(generation) else {
            return
        }
        await onStale()
    }

    private func resetAfterCancellation(
        generation: UInt64
    ) {
        reset(
            failure: nil,
            generation: generation
        )
    }

    private func reset(
        failure:
            GitLabDescriptionTaskToggleFailure?,
        generation: UInt64
    ) {
        guard canPublish(generation) else {
            return
        }
        editorModel = nil
        phase = .idle
        self.failure = failure
        activeTaskSourceID = nil
        intendedState = nil
    }

    private func canPublish(
        _ generation: UInt64
    ) -> Bool {
        operationGeneration == generation
            && isAccountCurrent()
    }

    private func finishOperation(
        generation: UInt64
    ) {
        guard
            operationGeneration == generation
        else {
            return
        }
        operationTask = nil
    }
}
