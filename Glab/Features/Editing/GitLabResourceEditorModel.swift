import Foundation
import Observation

nonisolated enum GitLabResourceEditField:
    Equatable,
    Hashable,
    Sendable
{
    case title
    case description
    case resourceIdentity
}

nonisolated struct GitLabResourceEditConflict:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let fields: Set<GitLabResourceEditField>
    let latest: GitLabResourceEditSnapshot

    var description: String {
        "GitLabResourceEditConflict(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabResourceEditorOperation:
    Equatable,
    Sendable
{
    case saving
    case checkingGitLab
}

nonisolated enum GitLabResourceEditorFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case validation(
        GitLabResourceEditValidationError
    )
    case readOnly
    case draftStorage
    case freshness(GitLabSessionClientError)
    case conflict(GitLabResourceEditConflict)
    case mutation(
        GitLabSessionClientError,
        certainty:
            GitLabMutationDeliveryCertainty
    )
    case reconciliation(
        GitLabSessionClientError
    )

    var description: String {
        "GitLabResourceEditorFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var deliveryCertainty:
        GitLabMutationDeliveryCertainty?
    {
        guard
            case let .mutation(
                _,
                certainty
            ) = self
        else {
            return nil
        }
        return certainty
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        switch self {
        case let .freshness(error),
             let .mutation(error, _),
             let .reconciliation(error):
            error.requiresReauthentication
                ? error
                : nil
        case .validation,
             .readOnly,
             .draftStorage,
             .conflict:
            nil
        }
    }
}

@MainActor
@Observable
final class GitLabResourceEditorModel {
    var title: String {
        didSet {
            titleDidChange(from: oldValue)
        }
    }

    var rawDescription: String {
        didSet {
            descriptionDidChange(
                from: oldValue
            )
        }
    }

    private(set) var baseline:
        GitLabResourceEditSnapshot
    private(set) var hasRestoredDraft = false
    private(set) var draftRevision = 0
    private(set) var operation:
        GitLabResourceEditorOperation?
    private(set) var failure:
        GitLabResourceEditorFailure?
    private(set) var didSucceed = false

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
    private var persistenceTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var activeOperationTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var operationGeneration: UInt64 = 0
    @ObservationIgnored
    private var isApplyingValues = false
    @ObservationIgnored
    private var isRestoringDraft = false
    @ObservationIgnored
    private var pendingMutation:
        PendingMutation?

    init(
        accountID: GitLabAccountID,
        baseline: GitLabResourceEditSnapshot,
        apiAccess: GitLabAPIAccess,
        service: any GitLabResourceEditing,
        draftStore:
            any GitLabResourceEditDraftStoring,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onSuccess:
            @escaping @MainActor (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.accountID = accountID
        self.baseline = baseline
        title = baseline.title
        rawDescription =
            baseline.rawDescription
        self.apiAccess = apiAccess
        self.service = service
        self.draftStore = draftStore
        self.isAccountCurrent =
            isAccountCurrent
        self.onSuccess = onSuccess
    }

    deinit {
        persistenceTask?.cancel()
        activeOperationTask?.cancel()
    }

    var isDirty: Bool {
        title != baseline.title
            || rawDescription
                != baseline.rawDescription
    }

    var canSave: Bool {
        hasRestoredDraft
            && apiAccess.canWrite
            && operation == nil
            && isDirty
            && pendingMutation == nil
            && !hasBlockingFailure
    }

    var canCheckGitLab: Bool {
        hasRestoredDraft
            && operation == nil
            && pendingMutation != nil
    }

    var canDiscardDraft: Bool {
        hasRestoredDraft
            && operation == nil
            && pendingMutation == nil
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    func restoreDraft() async {
        guard
            !hasRestoredDraft,
            !isRestoringDraft
        else {
            return
        }
        isRestoringDraft = true
        let startingRevision = draftRevision
        let draft = await draftStore.draft(
            for: draftKey
        )
        isRestoringDraft = false

        guard isAccountCurrent() else {
            return
        }

        let hadLocalEdits =
            draftRevision != startingRevision
                || isDirty
        if
            !hadLocalEdits,
            let draft,
            draft.baseline.target
                == baseline.target,
            draft.baseline.resourceID
                == baseline.resourceID
        {
            if
                draft.title == baseline.title,
                draft.currentDescription
                    == baseline.rawDescription
            {
                await draftStore.remove(
                    for: draftKey
                )
            } else {
                apply(
                    baseline: draft.baseline,
                    title: draft.title,
                    description:
                        draft.currentDescription
                )
                draftRevision =
                    draft.revision
            }
        } else if draft != nil, !hadLocalEdits {
            await draftStore.remove(
                for: draftKey
            )
        }

        hasRestoredDraft = true
        if hadLocalEdits {
            draftRevision = max(
                draftRevision,
                (draft?.revision ?? -1) + 1
            )
            schedulePersistence()
        }
    }

    func save() async {
        guard
            hasRestoredDraft,
            activeOperationTask == nil,
            pendingMutation == nil,
            !hasBlockingFailure
        else {
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }

        let initialChanges:
            GitLabResourceEditChanges
        do {
            initialChanges =
                try changes(
                    relativeTo: baseline
                )
        } catch {
            failure = .validation(error)
            if error == .noChanges {
                await draftStore.remove(
                    for: draftKey
                )
            }
            return
        }

        let generation = beginOperation(
            .saving
        )
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performSave(
                initialChanges:
                    initialChanges,
                generation: generation
            )
        }
        activeOperationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        finishOperation(
            generation: generation
        )
    }

    func checkGitLab() async {
        guard
            hasRestoredDraft,
            activeOperationTask == nil,
            pendingMutation != nil
        else {
            return
        }

        let generation = beginOperation(
            .checkingGitLab
        )
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.performDeliveryCheck(
                generation: generation
            )
        }
        activeOperationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        finishOperation(
            generation: generation
        )
    }

    func cancelActiveOperation() {
        let cancelledOperation = operation
        operationGeneration &+= 1
        activeOperationTask?.cancel()
        activeOperationTask = nil
        operation = nil
        guard pendingMutation != nil else {
            return
        }
        switch cancelledOperation {
        case .saving:
            failure = .mutation(
                .api(.cancelled),
                certainty: .deliveryUnknown
            )
        case .checkingGitLab:
            failure = .reconciliation(
                .api(.cancelled)
            )
        case nil:
            break
        }
    }

    @discardableResult
    func persistForDismissal() async -> Bool {
        guard operation == nil else {
            return false
        }
        guard isDirty else {
            persistenceTask?.cancel()
            persistenceTask = nil
            await draftStore.remove(
                for: draftKey
            )
            return true
        }
        return await persistCurrentDraft()
    }

    @discardableResult
    func discardDraft() async -> Bool {
        guard canDiscardDraft else {
            return false
        }

        persistenceTask?.cancel()
        persistenceTask = nil
        apply(
            baseline: baseline,
            title: baseline.title,
            description:
                baseline.rawDescription
        )
        failure = nil
        await draftStore.remove(
            for: draftKey
        )
        return true
    }

    private func performSave(
        initialChanges:
            GitLabResourceEditChanges,
        generation: UInt64
    ) async {
        guard await persistCurrentDraft() else {
            return
        }
        guard operationIsCurrent(generation) else {
            return
        }

        let latestResult:
            GitLabResourceEditResult
        do {
            latestResult = try await service
                .loadLatest(baseline.target)
        } catch {
            guard operationIsCurrent(generation) else {
                return
            }
            failure = .freshness(error)
            return
        }
        guard operationIsCurrent(generation) else {
            return
        }

        let latest = latestResult.snapshot
        guard
            latest.target == baseline.target,
            latest.resourceID == baseline.resourceID
        else {
            failure = .conflict(
                GitLabResourceEditConflict(
                    fields: [.resourceIdentity],
                    latest: latest
                )
            )
            return
        }

        let conflictFields = conflicts(
            latest: latest,
            changes: initialChanges,
            baseline: baseline
        )
        guard conflictFields.isEmpty else {
            failure = .conflict(
                GitLabResourceEditConflict(
                    fields: conflictFields,
                    latest: latest
                )
            )
            return
        }

        let intendedTitle = title
        let intendedDescription =
            rawDescription
        let oldBaseline = baseline
        rebase(
            onto: latest,
            preserving: initialChanges,
            intendedTitle: intendedTitle,
            intendedDescription:
                intendedDescription
        )
        if baseline != oldBaseline {
            draftRevision += 1
            guard await persistCurrentDraft() else {
                return
            }
            guard operationIsCurrent(generation) else {
                return
            }
        }

        let rebasedChanges:
            GitLabResourceEditChanges
        do {
            rebasedChanges = try changes(
                relativeTo: baseline
            )
        } catch .noChanges {
            await completeSuccess(
                latestResult,
                generation: generation
            )
            return
        } catch {
            failure = .validation(error)
            return
        }

        pendingMutation = PendingMutation(
            baseline: baseline,
            changes: rebasedChanges
        )
        do {
            let result = try await service.update(
                baseline.target,
                changes: rebasedChanges
            )
            guard operationIsCurrent(generation) else {
                return
            }
            guard
                result.snapshot.target
                    == baseline.target,
                result.snapshot.resourceID
                    == baseline.resourceID
            else {
                failure = .mutation(
                    .api(.invalidResponse),
                    certainty:
                        .deliveryUnknown
                )
                return
            }
            await completeSuccess(
                result,
                generation: generation
            )
        } catch {
            guard operationIsCurrent(generation) else {
                return
            }
            let certainty =
                error.mutationDeliveryCertainty
            if certainty == .rejected {
                pendingMutation = nil
            }
            failure = .mutation(
                error,
                certainty: certainty
            )
        }
    }

    private func performDeliveryCheck(
        generation: UInt64
    ) async {
        guard let pendingMutation else {
            return
        }

        let result:
            GitLabResourceEditResult
        do {
            result = try await service.loadLatest(
                pendingMutation
                    .baseline.target
            )
        } catch {
            guard operationIsCurrent(generation) else {
                return
            }
            failure = .reconciliation(error)
            return
        }
        guard operationIsCurrent(generation) else {
            return
        }

        let latest = result.snapshot
        guard
            latest.target
                == pendingMutation
                .baseline.target,
            latest.resourceID
                == pendingMutation
                .baseline.resourceID
        else {
            failure = .conflict(
                GitLabResourceEditConflict(
                    fields: [.resourceIdentity],
                    latest: latest
                )
            )
            return
        }

        let changedFields =
            pendingMutation.changes.fields
        let intendedFields =
            matchingFields(
                in: latest,
                against:
                    pendingMutation.changes
            )
        if intendedFields == changedFields {
            await completeSuccess(
                result,
                generation: generation
            )
            return
        }

        let baselineFields =
            matchingFields(
                in: latest,
                against:
                    pendingMutation.baseline,
                fields: changedFields
            )
        if baselineFields == changedFields {
            let intendedTitle = title
            let intendedDescription =
                rawDescription
            rebase(
                onto: latest,
                preserving:
                    pendingMutation.changes,
                intendedTitle: intendedTitle,
                intendedDescription:
                    intendedDescription
            )
            draftRevision += 1
            guard await persistCurrentDraft() else {
                return
            }
            self.pendingMutation = nil
            failure = nil
            return
        }

        let conflicting =
            changedFields.subtracting(
                intendedFields
                    .intersection(
                        baselineFields
                    )
            )
        failure = .conflict(
            GitLabResourceEditConflict(
                fields: conflicting.isEmpty
                    ? changedFields
                    : conflicting,
                latest: latest
            )
        )
    }

    private func completeSuccess(
        _ result: GitLabResourceEditResult,
        generation: UInt64
    ) async {
        guard operationIsCurrent(generation) else {
            return
        }
        let snapshot = result.snapshot
        pendingMutation = nil
        apply(
            baseline: snapshot,
            title: snapshot.title,
            description:
                snapshot.rawDescription
        )
        failure = nil
        onSuccess(result)
        await draftStore.remove(
            for: draftKey
        )
        persistenceTask?.cancel()
        persistenceTask = nil
        didSucceed = true
    }

    private func titleDidChange(
        from oldValue: String
    ) {
        guard
            !isApplyingValues,
            title != oldValue
        else {
            return
        }
        userValueDidChange()
    }

    private func descriptionDidChange(
        from oldValue: String
    ) {
        guard
            !isApplyingValues,
            rawDescription != oldValue
        else {
            return
        }
        userValueDidChange()
    }

    private func userValueDidChange() {
        draftRevision += 1
        didSucceed = false
        switch failure {
        case .validation,
             .freshness,
             .draftStorage,
             .mutation(_, .rejected):
            failure = nil
        case .readOnly,
             .conflict,
             .mutation(_, .deliveryUnknown),
             .reconciliation,
             nil:
            break
        }
        if hasRestoredDraft {
            schedulePersistence()
        }
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        let draft = currentDraft
        let draftStore = draftStore
        let draftKey = draftKey

        persistenceTask = Task { [weak self] in
            do {
                try await Task.sleep(
                    for: .milliseconds(350)
                )
                try Task.checkCancellation()
                try await draftStore.store(
                    draft,
                    for: draftKey
                )
                guard !Task.isCancelled else {
                    return
                }
                if self?.failure
                    == .draftStorage
                {
                    self?.failure = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.failure = .draftStorage
            }
        }
    }

    private func persistCurrentDraft() async -> Bool {
        persistenceTask?.cancel()
        persistenceTask = nil

        do {
            try await draftStore.store(
                currentDraft,
                for: draftKey
            )
            if failure == .draftStorage {
                failure = nil
            }
            return true
        } catch {
            failure = .draftStorage
            return false
        }
    }

    private func changes(
        relativeTo snapshot:
            GitLabResourceEditSnapshot
    ) throws(
        GitLabResourceEditValidationError
    ) -> GitLabResourceEditChanges {
        try GitLabResourceEditChanges(
            title:
                title == snapshot.title
                ? nil
                : title,
            description:
                rawDescription
                    == snapshot.rawDescription
                ? nil
                : rawDescription
        )
    }

    private func conflicts(
        latest: GitLabResourceEditSnapshot,
        changes: GitLabResourceEditChanges,
        baseline: GitLabResourceEditSnapshot
    ) -> Set<GitLabResourceEditField> {
        var fields:
            Set<GitLabResourceEditField> = []
        if
            changes.title != nil,
            latest.title != baseline.title
        {
            fields.insert(.title)
        }
        if
            changes.description != nil,
            latest.rawDescription
                != baseline.rawDescription
        {
            fields.insert(.description)
        }
        return fields
    }

    private func rebase(
        onto latest:
            GitLabResourceEditSnapshot,
        preserving changes:
            GitLabResourceEditChanges,
        intendedTitle: String,
        intendedDescription: String
    ) {
        apply(
            baseline: latest,
            title:
                changes.title == nil
                ? latest.title
                : intendedTitle,
            description:
                changes.description == nil
                ? latest.rawDescription
                : intendedDescription
        )
    }

    private func matchingFields(
        in latest:
            GitLabResourceEditSnapshot,
        against changes:
            GitLabResourceEditChanges
    ) -> Set<GitLabResourceEditField> {
        var fields:
            Set<GitLabResourceEditField> = []
        if
            let title = changes.title,
            latest.title == title
        {
            fields.insert(.title)
        }
        if
            let description =
                changes.description,
            latest.rawDescription
                == description
        {
            fields.insert(.description)
        }
        return fields
    }

    private func matchingFields(
        in latest:
            GitLabResourceEditSnapshot,
        against baseline:
            GitLabResourceEditSnapshot,
        fields:
            Set<GitLabResourceEditField>
    ) -> Set<GitLabResourceEditField> {
        var matching:
            Set<GitLabResourceEditField> = []
        if
            fields.contains(.title),
            latest.title == baseline.title
        {
            matching.insert(.title)
        }
        if
            fields.contains(.description),
            latest.rawDescription
                == baseline.rawDescription
        {
            matching.insert(.description)
        }
        return matching
    }

    private func apply(
        baseline: GitLabResourceEditSnapshot,
        title: String,
        description: String
    ) {
        isApplyingValues = true
        self.baseline = baseline
        self.title = title
        rawDescription = description
        isApplyingValues = false
    }

    private func beginOperation(
        _ operation:
            GitLabResourceEditorOperation
    ) -> UInt64 {
        operationGeneration &+= 1
        self.operation = operation
        failure = nil
        didSucceed = false
        return operationGeneration
    }

    private func finishOperation(
        generation: UInt64
    ) {
        guard operationGeneration == generation else {
            return
        }
        activeOperationTask = nil
        operation = nil
    }

    private func operationIsCurrent(
        _ generation: UInt64
    ) -> Bool {
        operationGeneration == generation
            && isAccountCurrent()
            && !Task.isCancelled
    }

    private var hasBlockingFailure: Bool {
        switch failure {
        case .validation,
             .conflict,
             .draftStorage,
             .mutation(_, .deliveryUnknown),
             .reconciliation:
            true
        case .readOnly,
             .freshness,
             .mutation(_, .rejected),
             nil:
            false
        }
    }

    private var draftKey:
        GitLabResourceEditDraftKey
    {
        GitLabResourceEditDraftKey(
            accountID: accountID,
            target: baseline.target
        )
    }

    private var currentDraft:
        GitLabResourceEditDraft
    {
        GitLabResourceEditDraft(
            baseline: baseline,
            title: title,
            description: rawDescription,
            revision: draftRevision
        )
    }
}

private nonisolated struct PendingMutation:
    Sendable
{
    let baseline:
        GitLabResourceEditSnapshot
    let changes:
        GitLabResourceEditChanges
}

private extension GitLabResourceEditChanges {
    var fields: Set<GitLabResourceEditField> {
        var fields:
            Set<GitLabResourceEditField> = []
        if title != nil {
            fields.insert(.title)
        }
        if description != nil {
            fields.insert(.description)
        }
        return fields
    }
}
