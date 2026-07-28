import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion composer model")
struct GitLabDiscussionComposerModelTests {
    @Test("Restores the target-specific draft before editing")
    @MainActor
    func restoresDraft() async throws {
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let context = try ComposerTestContext()
        let key = context.draftKey(
            target: .reply(
                discussionID: "thread-a"
            )
        )
        try await store.store(
            GitLabDiscussionDraft(
                body: "Restored reply",
                revision: 7
            ),
            for: key
        )
        let model = context.makeModel(
            target: .reply(
                discussionID: "thread-a"
            ),
            draftStore: store
        )

        await model.restoreDraft()

        #expect(model.hasRestoredDraft)
        #expect(model.body == "Restored reply")
        #expect(model.draftRevision == 7)
    }

    @Test("Typing during restoration wins with a newer revision")
    @MainActor
    func typingDuringRestoreWins() async throws {
        let store =
            GatedRestoreDraftStore(
                draft: GitLabDiscussionDraft(
                    body: "Older restored body",
                    revision: 7
                )
            )
        let context = try ComposerTestContext()
        let model = context.makeModel(
            draftStore: store
        )

        let restoration = Task {
            await model.restoreDraft()
        }
        await store.waitUntilReadStarts()
        model.body = "Typed while restoring"
        await store.releaseRead()
        await restoration.value
        _ = await model.persistForDismissal()

        #expect(
            model.body
                == "Typed while restoring"
        )
        #expect(model.draftRevision == 8)
        #expect(
            await store.storedDraft
                == GitLabDiscussionDraft(
                    body:
                        "Typed while restoring",
                    revision: 8
                )
        )
    }

    @Test("Rejects an empty body without posting")
    @MainActor
    func rejectsEmptyBody() async throws {
        let mutator = RecordingComposerMutator()
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator
        )
        await model.restoreDraft()
        model.body = " \n "

        await model.send()

        #expect(
            model.failure == .emptyBody
        )
        #expect(await mutator.postCount == 0)
    }

    @Test("Rejects posting from a read-only account")
    @MainActor
    func rejectsReadOnlyAccount() async throws {
        let mutator = RecordingComposerMutator()
        let context = try ComposerTestContext()
        let model = context.makeModel(
            apiAccess: .readOnly,
            mutator: mutator
        )
        await model.restoreDraft()
        model.body = "Cannot post"

        await model.send()

        #expect(
            model.failure == .readOnly
        )
        #expect(await mutator.postCount == 0)
    }

    @Test("Flushes the exact draft before posting")
    @MainActor
    func flushesBeforePosting() async throws {
        let events = ComposerEventRecorder()
        let store =
            RecordingComposerDraftStore(
                events: events
            )
        let mutator =
            RecordingComposerMutator(
                events: events
            )
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator,
            draftStore: store
        )
        await model.restoreDraft()
        model.body = "Exact **Markdown** body"

        await model.send()

        #expect(
            events.values
                == [
                    "store:Exact **Markdown** body",
                    "post:Exact **Markdown** body",
                    "remove",
                ]
        )
    }

    @Test("Reconciles a server result before clearing its draft")
    @MainActor
    func reconcilesSuccessBeforeClearing()
        async throws
    {
        let events = ComposerEventRecorder()
        let store =
            RecordingComposerDraftStore(
                events: events
            )
        let created = makeTestDiscussion(
            id: "server-created"
        )
        let mutator =
            RecordingComposerMutator(
                discussionResult:
                    .success(created),
                events: events
            )
        let context = try ComposerTestContext()
        var received:
            GitLabDiscussionComposerResult?
        let model = context.makeModel(
            mutator: mutator,
            draftStore: store
        ) {
            received = $0
            events.record("reconcile")
        }
        await model.restoreDraft()
        model.body = "Post me"

        await model.send()

        #expect(
            received
                == .discussion(created)
        )
        #expect(model.didSucceed)
        #expect(model.failure == nil)
        #expect(
            await store.storedDraft == nil
        )
        #expect(
            events.values
                == [
                    "store:Post me",
                    "post:Post me",
                    "reconcile",
                    "remove",
                ]
        )
    }

    @Test("Posts a reply to the selected server discussion")
    @MainActor
    func postsReply() async throws {
        let note = makeTestDiscussionNote(
            id: 707,
            body: "Server reply"
        )
        let mutator =
            RecordingComposerMutator(
                noteResult: .success(note)
            )
        let context = try ComposerTestContext()
        var received:
            GitLabDiscussionComposerResult?
        let model = context.makeModel(
            target: .reply(
                discussionID: "thread-707"
            ),
            mutator: mutator
        ) {
            received = $0
        }
        await model.restoreDraft()
        model.body = "Reply body"

        await model.send()

        #expect(
            received
                == .reply(
                    note,
                    discussionID:
                        "thread-707"
                )
        )
        #expect(
            await mutator.replyIDs
                == ["thread-707"]
        )
    }

    @Test("Posts a positional discussion to the selected merge request")
    @MainActor
    func postsDiffDiscussion() async throws {
        let route = GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 11
        )
        let version = try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "base",
                startSHA: "start",
                headSHA: "head"
            )
        )
        let position = try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/Old.swift",
                newPath: "Sources/New.swift",
                oldLine: 20,
                newLine: 21
            )
        )
        let created = makeTestDiscussion(
            id: "line-thread"
        )
        let mutator =
            RecordingComposerMutator(
                discussionResult:
                    .success(created)
            )
        let context = try ComposerTestContext(
            resource: .mergeRequest(route)
        )
        var received:
            GitLabDiscussionComposerResult?
        let model = context.makeModel(
            target:
                .newDiffDiscussion(
                    position: position
                ),
            mutator: mutator
        ) {
            received = $0
        }
        await model.restoreDraft()
        model.body = "Review this exact line"

        await model.send()

        #expect(
            received == .discussion(created)
        )
        #expect(
            await mutator.diffRoutes == [route]
        )
        #expect(
            await mutator.diffPositions
                == [position]
        )
    }

    @Test("A read-only positional target never reaches the mutator")
    @MainActor
    func rejectsReadOnlyDiffDiscussion()
        async throws
    {
        let version = try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "base",
                startSHA: "start",
                headSHA: "head"
            )
        )
        let position = try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: nil,
                newLine: 21
            )
        )
        let mutator = RecordingComposerMutator()
        let context = try ComposerTestContext(
            resource:
                .mergeRequest(
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 11
                    )
                )
        )
        let model = context.makeModel(
            target:
                .newDiffDiscussion(
                    position: position
                ),
            apiAccess: .readOnly,
            mutator: mutator
        )
        await model.restoreDraft()
        model.body = "Do not send"

        await model.send()

        #expect(model.failure == .readOnly)
        #expect(await mutator.postCount == 0)
        #expect(
            await mutator.diffPositions.isEmpty
        )
    }

    @Test("A draft storage failure prevents the POST")
    @MainActor
    func storageFailurePreventsPost()
        async throws
    {
        let store =
            RecordingComposerDraftStore(
                failsStores: true
            )
        let mutator = RecordingComposerMutator()
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator,
            draftStore: store
        )
        await model.restoreDraft()
        model.body = "Keep this safe"

        await model.send()

        #expect(
            model.failure == .draftStorage
        )
        #expect(model.body == "Keep this safe")
        #expect(model.canSubmitFromToolbar)
        #expect(await mutator.postCount == 0)
    }

    @Test("A validation failure preserves the draft")
    @MainActor
    func preservesRejectedDraft() async throws {
        let error =
            GitLabSessionClientError.api(
                .validation(statusCode: 400)
            )
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let mutator =
            RecordingComposerMutator(
                discussionResult:
                    .failure(.request(error))
            )
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator,
            draftStore: store
        )
        await model.restoreDraft()
        model.body = "Rejected body"

        await model.send()

        #expect(
            model.failure
                == .mutation(
                    .request(error),
                    certainty: .rejected
                )
        )
        #expect(model.canSubmitFromToolbar)
        #expect(
            await store.draft(
                for: context.draftKey()
            )?.body == "Rejected body"
        )
    }

    @Test("Exposes authentication failures for the session")
    @MainActor
    func exposesAuthenticationFailure()
        async throws
    {
        let error =
            GitLabSessionClientError.api(
                .unauthenticated
            )
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator:
                RecordingComposerMutator(
                    discussionResult:
                        .failure(
                            .request(error)
                        )
                )
        )
        await model.restoreDraft()
        model.body = "Preserve through sign in"

        await model.send()

        #expect(
            model.authenticationFailure
                == error
        )
    }

    @Test(
        "Ambiguous failures are marked delivery unknown",
        arguments: [
            GitLabSessionClientError.api(
                .connectivity(.networkConnectionLost)
            ),
            .api(.transport),
            .api(.decoding),
            .api(
                .rateLimited(
                    retryAfterSeconds: 30
                )
            ),
            .api(.server(statusCode: 503)),
        ]
    )
    @MainActor
    func marksDeliveryUnknown(
        error: GitLabSessionClientError
    ) async throws {
        let mutator =
            RecordingComposerMutator(
                discussionResult:
                    .failure(.request(error))
            )
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator
        )
        await model.restoreDraft()
        model.body = "Uncertain body"

        await model.send()

        #expect(
            model.failure
                == .mutation(
                    .request(error),
                    certainty:
                        .deliveryUnknown
                )
        )
        #expect(!model.canSubmitFromToolbar)
        #expect(await mutator.postCount == 1)
    }

    @Test("Duplicate send attempts share one in-flight POST")
    @MainActor
    func preventsDuplicatePosts() async throws {
        let mutator =
            GatedComposerMutator()
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator
        )
        await model.restoreDraft()
        model.body = "Only once"

        let first = Task {
            await model.send()
        }
        await mutator.waitUntilStarted()
        await model.send()

        #expect(model.isSending)
        #expect(await mutator.postCount == 1)

        await mutator.release()
        await first.value

        #expect(!model.isSending)
        #expect(await mutator.postCount == 1)
    }

    @Test("Cancellation preserves the draft and does not retry")
    @MainActor
    func cancellationPreservesDraft()
        async throws
    {
        let mutator =
            GatedComposerMutator()
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator,
            draftStore: store
        )
        await model.restoreDraft()
        model.body = "Do not lose me"

        let send = Task {
            await model.send()
        }
        await mutator.waitUntilStarted()
        send.cancel()
        await send.value

        #expect(
            model.failure
                == .mutation(
                    .request(
                        .api(.cancelled)
                    ),
                    certainty:
                        .deliveryUnknown
                )
        )
        #expect(
            await store.draft(
                for: context.draftKey()
            )?.body == "Do not lose me"
        )
        #expect(await mutator.postCount == 1)
        await Task.yield()
        #expect(await mutator.postCount == 1)
    }

    @Test("An explicit retry makes exactly one additional POST")
    @MainActor
    func retriesOnlyExplicitly() async throws {
        let mutator =
            SequencedComposerMutator(
                results: [
                    .failure(
                        .request(
                            .api(
                                .server(
                                    statusCode: 503
                                )
                            )
                        )
                    ),
                    .success(
                        makeTestDiscussion(
                            id: "retry-success"
                        )
                    ),
                ]
            )
        let context = try ComposerTestContext()
        let model = context.makeModel(
            mutator: mutator
        )
        await model.restoreDraft()
        model.body = "Retry manually"

        await model.send()
        #expect(await mutator.postCount == 1)

        await model.send()

        #expect(await mutator.postCount == 2)
        #expect(model.didSucceed)
    }

    @Test("Dismissal flushes the latest draft revision")
    @MainActor
    func dismissalFlushesLatestDraft()
        async throws
    {
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let context = try ComposerTestContext()
        let model = context.makeModel(
            draftStore: store
        )
        await model.restoreDraft()
        model.body = "First"
        model.body = "Latest"

        let didPersist =
            await model.persistForDismissal()

        #expect(didPersist)
        #expect(
            await store.draft(
                for: context.draftKey()
            )
                == GitLabDiscussionDraft(
                    body: "Latest",
                    revision: 2
                )
        )
    }
}

private struct ComposerTestContext {
    let accountID: GitLabAccountID
    let resource: GitLabDiscussionResource

    init(
        resource:
            GitLabDiscussionResource =
                .issue(
                    GitLabIssueRoute(
                        projectID: 42,
                        issueIID: 9
                    )
                )
    ) throws {
        accountID = GitLabAccountID(
            host: try GitLabHost(
                "https://gitlab.example.com"
            ),
            userID: 7
        )
        self.resource = resource
    }

    @MainActor
    func makeModel(
        target:
            GitLabDiscussionComposerTarget =
                .newDiscussion,
        apiAccess:
            GitLabAPIAccess = .readWrite,
        mutator:
            any GitLabDiscussionMutating =
                RecordingComposerMutator(),
        draftStore:
            any GitLabDiscussionDraftStoring =
                InMemoryGitLabDiscussionDraftStore(),
        onSuccess:
            @escaping @MainActor (
                GitLabDiscussionComposerResult
            ) -> Void = { _ in }
    ) -> GitLabDiscussionComposerModel {
        GitLabDiscussionComposerModel(
            accountID: accountID,
            resource: resource,
            target: target,
            apiAccess: apiAccess,
            mutator: mutator,
            draftStore: draftStore,
            onSuccess: onSuccess
        )
    }

    func draftKey(
        target:
            GitLabDiscussionComposerTarget =
                .newDiscussion
    ) -> GitLabDiscussionDraftKey {
        GitLabDiscussionDraftKey(
            accountID: accountID,
            resource: resource,
            target: target
        )
    }
}

@MainActor
private final class ComposerEventRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

private actor RecordingComposerDraftStore:
    GitLabDiscussionDraftStoring
{
    private(set) var storedDraft:
        GitLabDiscussionDraft?
    private let failsStores: Bool
    private let events:
        ComposerEventRecorder?

    init(
        failsStores: Bool = false,
        events: ComposerEventRecorder? = nil
    ) {
        self.failsStores = failsStores
        self.events = events
    }

    func draft(
        for key: GitLabDiscussionDraftKey
    ) -> GitLabDiscussionDraft? {
        storedDraft
    }

    func store(
        _ draft: GitLabDiscussionDraft,
        for key: GitLabDiscussionDraftKey
    ) async throws(GitLabDiscussionDraftStoreError) {
        guard !failsStores else {
            throw .storage
        }
        storedDraft =
            draft.body.isEmpty ? nil : draft
        await events?.record(
            "store:\(draft.body)"
        )
    }

    func remove(
        for key: GitLabDiscussionDraftKey
    ) async {
        storedDraft = nil
        await events?.record("remove")
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {}
}

private actor GatedRestoreDraftStore:
    GitLabDiscussionDraftStoring
{
    private(set) var storedDraft:
        GitLabDiscussionDraft?
    private var readStarted = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var readContinuation:
        CheckedContinuation<Void, Never>?

    init(draft: GitLabDiscussionDraft) {
        storedDraft = draft
    }

    func draft(
        for key: GitLabDiscussionDraftKey
    ) async -> GitLabDiscussionDraft? {
        readStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            readContinuation = $0
        }
        return storedDraft
    }

    func store(
        _ draft: GitLabDiscussionDraft,
        for key: GitLabDiscussionDraftKey
    ) {
        guard
            storedDraft.map({
                $0.revision < draft.revision
            }) ?? true
        else {
            return
        }
        storedDraft =
            draft.body.isEmpty ? nil : draft
    }

    func remove(
        for key: GitLabDiscussionDraftKey
    ) {
        storedDraft = nil
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        storedDraft = nil
    }

    func waitUntilReadStarts() async {
        guard !readStarted else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func releaseRead() {
        readContinuation?.resume()
        readContinuation = nil
    }
}

private actor RecordingComposerMutator:
    GitLabDiscussionMutating
{
    private(set) var postCount = 0
    private(set) var replyIDs:
        [String] = []
    private(set) var diffRoutes:
        [GitLabMergeRequestRoute] = []
    private(set) var diffPositions:
        [GitLabDiffLinePosition] = []
    private let discussionResult:
        Result<
            GitLabDiscussion,
            GitLabDiscussionMutationError
        >
    private let noteResult:
        Result<
            GitLabDiscussionNote,
            GitLabDiscussionMutationError
        >
    private let events:
        ComposerEventRecorder?

    init(
        discussionResult:
            Result<
                GitLabDiscussion,
                GitLabDiscussionMutationError
            > = .success(
                makeTestDiscussion(
                    id: "created"
                )
            ),
        noteResult:
            Result<
                GitLabDiscussionNote,
                GitLabDiscussionMutationError
            > = .success(
                makeTestDiscussionNote(
                    id: 909
                )
            ),
        events: ComposerEventRecorder? = nil
    ) {
        self.discussionResult =
            discussionResult
        self.noteResult = noteResult
        self.events = events
    }

    func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        postCount += 1
        await events?.record(
            "post:\(body.body)"
        )
        return try discussionResult.get()
    }

    func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        postCount += 1
        diffRoutes.append(route)
        diffPositions.append(position)
        await events?.record(
            "post:\(body.body)"
        )
        return try discussionResult.get()
    }

    func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionNote
    {
        postCount += 1
        replyIDs.append(discussionID)
        return try noteResult.get()
    }
}

private actor GatedComposerMutator:
    GitLabDiscussionMutating
{
    private(set) var postCount = 0
    private var didStart = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var shouldRelease = false
    private var releaseContinuation:
        CheckedContinuation<Void, Never>?

    func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        postCount += 1
        didStart = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }

        await withTaskCancellationHandler {
            await withCheckedContinuation {
                continuation in
                if shouldRelease {
                    continuation.resume()
                } else {
                    releaseContinuation =
                        continuation
                }
            }
        } onCancel: {
            Task {
                await self.release()
            }
        }
        guard !Task.isCancelled else {
            throw .request(.api(.cancelled))
        }
        return makeTestDiscussion(
            id: "gated"
        )
    }

    func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        try await createDiscussion(
            for: .mergeRequest(route),
            body: body
        )
    }

    func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionNote
    {
        throw .request(
            .api(.invalidResponse)
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
        shouldRelease = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor SequencedComposerMutator:
    GitLabDiscussionMutating
{
    private(set) var postCount = 0
    private var results: [
        Result<
            GitLabDiscussion,
            GitLabDiscussionMutationError
        >
    ]

    init(
        results: [
            Result<
                GitLabDiscussion,
                GitLabDiscussionMutationError
            >
        ]
    ) {
        self.results = results
    }

    func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        postCount += 1
        guard !results.isEmpty else {
            throw .request(
                .api(.invalidResponse)
            )
        }
        return try results.removeFirst().get()
    }

    func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        try createDiscussion(
            for: .mergeRequest(route),
            body: body
        )
    }

    func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionNote
    {
        throw .request(
            .api(.invalidResponse)
        )
    }
}
