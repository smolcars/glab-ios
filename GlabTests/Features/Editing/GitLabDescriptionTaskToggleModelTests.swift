import Foundation
import Testing
@testable import Glab

@Suite("GitLab description task toggle model")
struct GitLabDescriptionTaskToggleModelTests {
    @Test("Toggles an issue through the P3-02 description transaction")
    @MainActor
    func issueSuccess() async throws {
        let context = try TaskToggleTestContext()
        let updatedIssue = makeTestIssue(
            id: context.issue.id,
            iid: context.issue.iid,
            projectID: context.issue.projectID,
            title: context.issue.title,
            description: "- [x] Ship",
            updatedAt:
                context.issue.updatedAt
                    .addingTimeInterval(10)
        )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(context.issue)
                    )
                ],
                updateResults: [
                    .success(
                        .issue(updatedIssue)
                    )
                ]
            )
        var successfulResult:
            GitLabResourceEditResult?
        let model = context.makeModel(
            service: service,
            onSuccess: {
                successfulResult = $0
            }
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        let update = try #require(
            await service.updates.first
        )
        #expect(await service.loadCount == 1)
        #expect(await service.updateCount == 1)
        #expect(
            await service.invalidatedTargets
                == [context.snapshot.target]
        )
        #expect(update.target == context.snapshot.target)
        #expect(update.changes.title == nil)
        #expect(
            update.changes.description
                == "- [x] Ship"
        )
        #expect(
            successfulResult
                == .issue(updatedIssue)
        )
        #expect(
            model.phase == .idle
        )
        #expect(model.failure == nil)
        #expect(model.activeTaskSourceID == nil)
    }

    @Test("Toggles a merge request without changing its title")
    @MainActor
    func mergeRequestSuccess() async throws {
        let context = try TaskToggleTestContext()
        let mergeRequest =
            makeTestMergeRequest(
                id: 502,
                iid: 19,
                projectID: 84,
                title: "Preserve this title",
                description: "- [x] Done"
            )
        let snapshot =
            GitLabResourceEditSnapshot(
                mergeRequest: mergeRequest
            )
        let task = try await indexedTask(
            in: snapshot.rawDescription
        )
        let updated =
            makeTestMergeRequest(
                id: mergeRequest.id,
                iid: mergeRequest.iid,
                projectID:
                    mergeRequest.projectID,
                title: mergeRequest.title,
                description: "- [ ] Done",
                updatedAt:
                    mergeRequest.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .mergeRequest(
                            mergeRequest
                        )
                    )
                ],
                updateResults: [
                    .success(
                        .mergeRequest(updated)
                    )
                ]
            )
        let model = context.makeModel(
            service: service
        )

        await model.toggle(
            task,
            in: snapshot
        )

        let changes = try #require(
            await service.updates.first?
                .changes
        )
        #expect(changes.title == nil)
        #expect(changes.description == "- [ ] Done")
        #expect(await service.updateCount == 1)
    }

    @Test("Read-only and inapplicable tasks never request GitLab")
    @MainActor
    func nonmutatingGates() async throws {
        let context = try TaskToggleTestContext()
        let readOnlyService =
            TaskToggleRecordingService()
        let readOnly = context.makeModel(
            apiAccess: .readOnly,
            service: readOnlyService
        )

        await readOnly.toggle(
            context.task,
            in: context.snapshot
        )

        #expect(
            readOnly.failure == .readOnly
        )
        #expect(
            await readOnlyService.loadCount == 0
        )
        #expect(
            await readOnlyService.updateCount == 0
        )

        let source = "- [~] Not applicable"
        let inapplicableTask =
            try await indexedTask(in: source)
        let inapplicableService =
            TaskToggleRecordingService()
        let inapplicable =
            context.makeModel(
                service:
                    inapplicableService
            )

        await inapplicable.toggle(
            inapplicableTask,
            in:
                context.snapshot(
                    description: source
                )
        )

        #expect(
            inapplicable.failure
                == .inapplicable
        )
        #expect(
            await inapplicableService
                .loadCount == 0
        )
        #expect(
            await inapplicableService
                .updateCount == 0
        )
    }

    @Test("A pre-existing edit draft is preserved and blocks a toggle")
    @MainActor
    func existingDraft() async throws {
        let context = try TaskToggleTestContext()
        let draft =
            GitLabResourceEditDraft(
                baseline: context.snapshot,
                title: context.snapshot.title,
                description:
                    "- [ ] Ship\nDraft note",
                revision: 7
            )
        let store =
            InMemoryGitLabResourceEditDraftStore()
        let key = GitLabResourceEditDraftKey(
            accountID: context.accountID,
            target: context.snapshot.target
        )
        try await store.store(
            draft,
            for: key
        )
        let service =
            TaskToggleRecordingService()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        #expect(
            model.failure
                == .existingDraft(
                    requiresDeliveryCheck:
                        false
                )
        )
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
        #expect(
            await store.draft(for: key)
                == draft
        )
    }

    @Test("A stale server description rolls back and refreshes without PUT")
    @MainActor
    func staleDescription() async throws {
        let context = try TaskToggleTestContext()
        let changedIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: context.issue.title,
                description:
                    "- [ ] Ship\nServer change",
                updatedAt:
                    context.issue.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(changedIssue)
                    )
                ]
            )
        var refreshCount = 0
        let store =
            InMemoryGitLabResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store,
            onStale: {
                refreshCount += 1
            }
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        #expect(
            model.failure
                == .staleDescription
        )
        #expect(model.phase == .idle)
        #expect(model.activeTaskSourceID == nil)
        #expect(refreshCount == 1)
        #expect(await service.loadCount == 1)
        #expect(await service.updateCount == 0)
        #expect(
            await store.draft(
                for:
                    GitLabResourceEditDraftKey(
                        accountID:
                            context.accountID,
                        target:
                            context.snapshot
                                .target
                    )
            ) == nil
        )
    }

    @Test("A definite rejection rolls back and removes its own draft")
    @MainActor
    func definiteRejection() async throws {
        let context = try TaskToggleTestContext()
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(context.issue)
                    )
                ],
                updateResults: [
                    .failure(
                        .api(.forbidden)
                    )
                ]
            )
        let store =
            InMemoryGitLabResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        #expect(
            model.failure
                == .editor(
                    .mutation(
                        .api(.forbidden),
                        certainty: .rejected
                    )
                )
        )
        #expect(model.phase == .idle)
        #expect(model.activeTaskSourceID == nil)
        #expect(await service.updateCount == 1)
        #expect(
            await store.draft(
                for:
                    GitLabResourceEditDraftKey(
                        accountID:
                            context.accountID,
                        target:
                            context.snapshot
                                .target
                    )
            ) == nil
        )
    }

    @Test("Unknown delivery remains durable until GitLab proves success")
    @MainActor
    func unknownDelivery() async throws {
        let context = try TaskToggleTestContext()
        let updatedIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: context.issue.title,
                description: "- [x] Ship",
                updatedAt:
                    context.issue.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(context.issue)
                    ),
                    .success(
                        .issue(updatedIssue)
                    ),
                ],
                updateResults: [
                    .failure(
                        .api(
                            .server(
                                statusCode: 500
                            )
                        )
                    )
                ]
            )
        let store =
            InMemoryGitLabResourceEditDraftStore()
        var successfulResult:
            GitLabResourceEditResult?
        let model = context.makeModel(
            service: service,
            draftStore: store,
            onSuccess: {
                successfulResult = $0
            }
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        let key = GitLabResourceEditDraftKey(
            accountID: context.accountID,
            target: context.snapshot.target
        )
        #expect(
            model.phase
                == .deliveryUnknown
        )
        #expect(
            model.activeTaskSourceID
                == context.task.sourceID
        )
        #expect(
            model.displayedState(
                for: context.task
            ) == .complete
        )
        #expect(
            await store.draft(for: key)?
                .requiresDeliveryCheck
                == true
        )

        await model.checkGitLab()

        #expect(model.phase == .idle)
        #expect(model.failure == nil)
        #expect(model.activeTaskSourceID == nil)
        #expect(
            successfulResult
                == .issue(updatedIssue)
        )
        #expect(
            await service.loadCount == 2
        )
        #expect(
            await service.updateCount == 1
        )
        #expect(
            await service.invalidatedTargets
                == [context.snapshot.target]
        )
        #expect(await store.draft(for: key) == nil)
    }

    @Test("A title-only server change rebases the task update")
    @MainActor
    func titleOnlyRebase() async throws {
        let context = try TaskToggleTestContext()
        let renamedIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: "Renamed on GitLab",
                description:
                    context.snapshot.rawDescription,
                updatedAt:
                    context.issue.updatedAt
                        .addingTimeInterval(10)
            )
        let updatedIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: renamedIssue.title,
                description: "- [x] Ship",
                updatedAt:
                    renamedIssue.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(renamedIssue)
                    )
                ],
                updateResults: [
                    .success(
                        .issue(updatedIssue)
                    )
                ]
            )
        let model = context.makeModel(
            service: service
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        let changes = try #require(
            await service.updates.first?
                .changes
        )
        #expect(changes.title == nil)
        #expect(
            changes.description
                == "- [x] Ship"
        )
        #expect(model.failure == nil)
    }

    @Test("A stale source fails locally and refreshes without transport")
    @MainActor
    func staleSource() async throws {
        let context = try TaskToggleTestContext()
        let service =
            TaskToggleRecordingService()
        var refreshCount = 0
        let model = context.makeModel(
            service: service,
            onStale: {
                refreshCount += 1
            }
        )
        let staleSnapshot =
            context.snapshot(
                description:
                    "- [ ] Ship\nChanged locally"
            )

        await model.toggle(
            context.task,
            in: staleSnapshot
        )

        #expect(
            model.failure
                == .staleDescription
        )
        #expect(refreshCount == 1)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("Source validation precedes optimism and rapid taps make one write")
    @MainActor
    func rapidTaps() async throws {
        let context = try TaskToggleTestContext()
        let updatedIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: context.issue.title,
                description: "- [x] Ship",
                updatedAt:
                    context.issue.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(context.issue)
                    )
                ],
                updateResults: [
                    .success(
                        .issue(updatedIssue)
                    )
                ]
            )
        let gate = TaskToggleRewriteGate()
        let model = context.makeModel(
            service: service,
            rewrite: {
                source,
                task,
                state in
                try await gate.rewrite(
                    source,
                    task: task,
                    to: state
                )
            }
        )

        let first = Task {
            await model.toggle(
                context.task,
                in: context.snapshot
            )
        }
        await gate.waitUntilStarted()

        #expect(model.phase == .rewriting)
        #expect(
            model.displayedState(
                for: context.task
            ) == .incomplete
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)

        await gate.release()
        await first.value

        #expect(await service.loadCount == 1)
        #expect(await service.updateCount == 1)
        #expect(model.failure == nil)
    }

    @Test("Draft storage failure sends no request")
    @MainActor
    func draftStorageFailure() async throws {
        let context = try TaskToggleTestContext()
        let service =
            TaskToggleRecordingService()
        let model = context.makeModel(
            service: service,
            draftStore:
                FailingTaskToggleDraftStore()
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        #expect(
            model.failure
                == .editor(.draftStorage)
        )
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("A delivery check proving no change requires an explicit retry")
    @MainActor
    func unknownDeliveryRetry() async throws {
        let context = try TaskToggleTestContext()
        let updatedIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: context.issue.title,
                description: "- [x] Ship",
                updatedAt:
                    context.issue.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(context.issue)
                    ),
                    .success(
                        .issue(context.issue)
                    ),
                    .success(
                        .issue(context.issue)
                    ),
                ],
                updateResults: [
                    .failure(
                        .api(
                            .server(
                                statusCode: 500
                            )
                        )
                    ),
                    .success(
                        .issue(updatedIssue)
                    ),
                ]
            )
        let model = context.makeModel(
            service: service
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )
        await model.checkGitLab()

        #expect(
            model.phase
                == .retryAvailable
        )
        #expect(await service.updateCount == 1)

        await model.retry()

        #expect(model.phase == .idle)
        #expect(model.failure == nil)
        #expect(await service.loadCount == 3)
        #expect(await service.updateCount == 2)
    }

    @Test("A third server value stays protected for editor recovery")
    @MainActor
    func unknownDeliveryConflict() async throws {
        let context = try TaskToggleTestContext()
        let conflictingIssue =
            makeTestIssue(
                id: context.issue.id,
                iid: context.issue.iid,
                projectID: context.issue.projectID,
                title: context.issue.title,
                description:
                    "- [ ] Ship\nThird value",
                updatedAt:
                    context.issue.updatedAt
                        .addingTimeInterval(10)
            )
        let service =
            TaskToggleRecordingService(
                latestResults: [
                    .success(
                        .issue(context.issue)
                    ),
                    .success(
                        .issue(conflictingIssue)
                    ),
                ],
                updateResults: [
                    .failure(
                        .api(
                            .server(
                                statusCode: 500
                            )
                        )
                    )
                ]
            )
        var refreshCount = 0
        let model = context.makeModel(
            service: service,
            onStale: {
                refreshCount += 1
            }
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )
        await model.checkGitLab()

        #expect(
            model.phase
                == .deliveryUnknown
        )
        #expect(refreshCount == 1)
        let editor = try #require(
            model.takeRecoveryEditor()
        )
        #expect(editor.requiresDeliveryCheck)
        #expect(model.phase == .idle)
        #expect(await service.updateCount == 1)
    }

    @Test("Cancellation during source validation publishes nothing")
    @MainActor
    func cancellationDuringRewrite() async throws {
        let context = try TaskToggleTestContext()
        let gate = TaskToggleRewriteGate()
        let service =
            TaskToggleRecordingService()
        let model = context.makeModel(
            service: service,
            rewrite: {
                source,
                task,
                state in
                try await gate.rewrite(
                    source,
                    task: task,
                    to: state
                )
            }
        )

        let operation = Task {
            await model.toggle(
                context.task,
                in: context.snapshot
            )
        }
        await gate.waitUntilStarted()

        model.cancel()
        await gate.release()
        await operation.value

        #expect(model.phase == .idle)
        #expect(model.failure == nil)
        #expect(model.activeTaskSourceID == nil)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("An account switch rejects late validation without stale UI state")
    @MainActor
    func accountSwitchDuringRewrite() async throws {
        let context = try TaskToggleTestContext()
        let gate = TaskToggleRewriteGate()
        let service =
            TaskToggleRecordingService()
        let accountState =
            TaskToggleAccountState()
        let model = context.makeModel(
            service: service,
            isAccountCurrent: {
                accountState.isCurrent
            },
            rewrite: {
                source,
                task,
                state in
                try await gate.rewrite(
                    source,
                    task: task,
                    to: state
                )
            }
        )

        let operation = Task {
            await model.toggle(
                context.task,
                in: context.snapshot
            )
        }
        await gate.waitUntilStarted()

        accountState.isCurrent = false
        await gate.release()
        await operation.value

        #expect(model.phase == .idle)
        #expect(model.failure == nil)
        #expect(model.activeTaskSourceID == nil)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("A restored unknown-delivery draft blocks a second write")
    @MainActor
    func restoredUnknownDelivery() async throws {
        let context = try TaskToggleTestContext()
        let key = GitLabResourceEditDraftKey(
            accountID: context.accountID,
            target: context.snapshot.target
        )
        let draft =
            GitLabResourceEditDraft(
                baseline: context.snapshot,
                title: context.snapshot.title,
                description: "- [x] Ship",
                revision: 4,
                requiresDeliveryCheck: true
            )
        let store =
            InMemoryGitLabResourceEditDraftStore()
        try await store.store(
            draft,
            for: key
        )
        let service =
            TaskToggleRecordingService()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )

        await model.toggle(
            context.task,
            in: context.snapshot
        )

        #expect(
            model.failure
                == .existingDraft(
                    requiresDeliveryCheck:
                        true
                )
        )
        #expect(await store.draft(for: key) == draft)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    private func indexedTask(
        in source: String
    ) async throws -> GitLabMarkdownIndexedTask {
        try #require(
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
                .first
        )
    }
}

private struct TaskToggleRecordedUpdate:
    Equatable,
    Sendable
{
    let target: GitLabResourceEditTarget
    let changes: GitLabResourceEditChanges
}

private actor TaskToggleRecordingService:
    GitLabResourceEditing
{
    private var latestResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]
    private var updateResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]

    private(set) var loadedTargets:
        [GitLabResourceEditTarget] = []
    private(set) var updates:
        [TaskToggleRecordedUpdate] = []
    private(set) var invalidatedTargets:
        [GitLabResourceEditTarget] = []

    init(
        latestResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ] = [],
        updateResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ] = []
    ) {
        self.latestResults = latestResults
        self.updateResults = updateResults
    }

    var loadCount: Int {
        loadedTargets.count
    }

    var updateCount: Int {
        updates.count
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        loadedTargets.append(target)
        guard !latestResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try value(
            from: latestResults.removeFirst()
        )
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        updates.append(
            TaskToggleRecordedUpdate(
                target: target,
                changes: changes
            )
        )
        guard !updateResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try value(
            from: updateResults.removeFirst()
        )
    }

    func invalidateAffectedReads(
        for target: GitLabResourceEditTarget
    ) {
        invalidatedTargets.append(target)
    }

    private func value<Value>(
        from result:
            Result<
                Value,
                GitLabSessionClientError
            >
    ) throws(GitLabSessionClientError) -> Value {
        switch result {
        case let .success(value):
            value
        case let .failure(error):
            throw error
        }
    }
}

private struct TaskToggleTestContext {
    let accountID: GitLabAccountID
    let issue: GitLabIssue
    let snapshot: GitLabResourceEditSnapshot
    let task: GitLabMarkdownIndexedTask

    init() throws {
        accountID = GitLabAccountID(
            host:
                try GitLabHost(
                    "https://gitlab.example.com"
                ),
            userID: 9
        )
        issue = makeTestIssue(
            title: "Task list",
            description: "- [ ] Ship"
        )
        snapshot =
            GitLabResourceEditSnapshot(
                issue: issue
            )
        task =
            GitLabMarkdownIndexedTask(
                sourceID:
                    GitLabMarkdownTaskSourceID(
                        sourceDigest:
                            GitLabMarkdownSourceDigest
                                .digest(
                                    for:
                                        snapshot
                                            .rawDescription
                                ),
                        markerUTF8Offset: 2
                    ),
                state: .incomplete
            )
    }

    func snapshot(
        description: String
    ) -> GitLabResourceEditSnapshot {
        GitLabResourceEditSnapshot(
            target: snapshot.target,
            resourceID:
                snapshot.resourceID,
            title: snapshot.title,
            description: description,
            updatedAt: snapshot.updatedAt
        )
    }

    @MainActor
    func makeModel(
        apiAccess:
            GitLabAPIAccess = .readWrite,
        service:
            any GitLabResourceEditing =
                TaskToggleRecordingService(),
        draftStore:
            any GitLabResourceEditDraftStoring =
                InMemoryGitLabResourceEditDraftStore(),
        isAccountCurrent:
            @escaping @MainActor () -> Bool = {
                true
            },
        onSuccess:
            @escaping @MainActor (
                GitLabResourceEditResult
            ) -> Void = { _ in },
        onStale:
            @escaping @MainActor () async
                -> Void = {},
        rewrite:
            @escaping
            GitLabDescriptionTaskToggleModel
            .Rewrite = {
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
    ) -> GitLabDescriptionTaskToggleModel {
        GitLabDescriptionTaskToggleModel(
            accountID: accountID,
            apiAccess: apiAccess,
            service: service,
            draftStore: draftStore,
            isAccountCurrent:
                isAccountCurrent,
            onSuccess: onSuccess,
            onStale: onStale,
            rewrite: rewrite
        )
    }
}

private actor TaskToggleRewriteGate {
    private var didStart = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation:
        CheckedContinuation<Void, Never>?

    func rewrite(
        _ source: String,
        task: GitLabMarkdownIndexedTask,
        to state: GitLabMarkdownTaskState
    ) async throws -> String {
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            releaseContinuation = $0
        }
        try Task.checkCancellation()
        return try await
            GitLabMarkdownTaskSourceRewriter
            .rewrite(
                source,
                task: task,
                to: state
            )
    }

    func waitUntilStarted() async {
        guard !didStart else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor FailingTaskToggleDraftStore:
    GitLabResourceEditDraftStoring
{
    func draft(
        for key: GitLabResourceEditDraftKey
    ) -> GitLabResourceEditDraft? {
        nil
    }

    func store(
        _ draft: GitLabResourceEditDraft,
        for key: GitLabResourceEditDraftKey
    ) throws(
        GitLabResourceEditDraftStoreError
    ) {
        throw .storage
    }

    func remove(
        for key: GitLabResourceEditDraftKey
    ) {}

    func removeAll(
        for accountID: GitLabAccountID
    ) {}
}

@MainActor
private final class TaskToggleAccountState {
    var isCurrent = true
}
