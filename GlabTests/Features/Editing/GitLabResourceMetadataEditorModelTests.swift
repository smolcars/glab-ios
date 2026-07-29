import Foundation
import Testing
@testable import Glab

@Suite("GitLab resource metadata editor model")
struct GitLabResourceMetadataEditorModelTests {
    @Test("Rebases issue people while preserving additive label intent")
    @MainActor
    func rebasesIssueChanges() async throws {
        let baseline = makeTestIssue(
            labels: ["bug"],
            assignees: [
                makeTestIssueUser(id: 2),
            ]
        )
        let latest = makeTestIssue(
            labels: ["bug", "server"],
            assignees: [
                makeTestIssueUser(id: 2),
                makeTestIssueUser(id: 4),
            ]
        )
        let updated = makeTestIssue(
            labels: ["server", "mobile"],
            assignees: [
                makeTestIssueUser(id: 4),
                makeTestIssueUser(id: 3),
            ]
        )
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .issue(latest),
                ],
                updateResult:
                    .success(.issue(updated)),
                labelPageResults: [
                    .success(page()),
                ],
                memberPageResults: [
                    .success(
                        page(
                            [
                                member(id: 2),
                                member(id: 3),
                            ]
                        )
                    ),
                ]
            )
        var success:
            GitLabResourceEditResult?
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(baseline),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: {
                    success = $0
                }
            )

        await model.loadOptions()
        model.toggleLabel(
            label(name: "bug")
        )
        model.addLabel(named: "mobile")
        model.toggleAssignee(
            member(id: 2)
        )
        model.toggleAssignee(
            member(id: 3)
        )

        await model.save()

        let changes = try #require(
            await service.updates.first
        )
        #expect(
            changes.labels
                == .delta(
                    add: ["mobile"],
                    remove: ["bug"]
                )
        )
        #expect(
            changes.assigneeIDs == [4, 3]
        )
        #expect(changes.reviewerIDs == nil)
        #expect(success == .issue(updated))
        #expect(model.didSucceed)
        #expect(await service.invalidationCount == 1)
    }

    @Test("Rebases merge request reviewers without touching approvals")
    @MainActor
    func rebasesMergeRequestReviewers() async throws {
        let baseline =
            makeTestMergeRequest(
                reviewers: [
                    makeTestAPIUser(id: 10),
                ]
            )
        let latest =
            makeTestMergeRequest(
                reviewers: [
                    makeTestAPIUser(id: 10),
                    makeTestAPIUser(id: 12),
                ]
            )
        let updated =
            makeTestMergeRequest(
                reviewers: [
                    makeTestAPIUser(id: 12),
                    makeTestAPIUser(id: 11),
                ]
            )
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .mergeRequest(latest),
                ],
                updateResult:
                    .success(
                        .mergeRequest(updated)
                    ),
                labelPageResults: [
                    .success(page()),
                ],
                memberPageResults: [
                    .success(
                        page(
                            [
                                member(id: 10),
                                member(id: 11),
                            ]
                        )
                    ),
                ]
            )
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline:
                    .mergeRequest(baseline),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )

        await model.loadOptions()
        model.toggleReviewer(member(id: 10))
        model.toggleReviewer(member(id: 11))
        await model.save()

        let changes = try #require(
            await service.updates.first
        )
        #expect(changes.reviewerIDs == [12, 11])
        #expect(changes.assigneeIDs == nil)
    }

    @Test("Delivery unknown never retries and explicit check reconciles success")
    @MainActor
    func checksUnknownDelivery() async throws {
        let baseline = makeTestIssue()
        let updated = makeTestIssue(
            state: "closed"
        )
        let failure =
            GitLabSessionClientError
                .api(
                    .rateLimited(
                        retryAfterSeconds: 30
                    )
                )
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .issue(baseline),
                    .issue(updated),
                ],
                updateResult:
                    .failure(failure)
            )
        var success:
            GitLabResourceEditResult?
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(baseline),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: {
                    success = $0
                }
            )

        await model.changeState(.close)

        #expect(model.requiresDeliveryCheck)
        #expect(await service.updateCount == 1)
        #expect(await service.invalidationCount == 0)

        await model.checkGitLab()

        #expect(await service.updateCount == 1)
        #expect(!model.requiresDeliveryCheck)
        #expect(success == .issue(updated))
        #expect(await service.invalidationCount == 1)
    }

    @Test("API cancellation during a write requires an explicit check")
    @MainActor
    func treatsWriteCancellationAsUnknown() async {
        let issue = makeTestIssue()
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .issue(issue),
                ],
                updateResult:
                    .failure(
                        .api(.cancelled)
                    )
            )
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(issue),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )

        await model.changeState(.close)

        #expect(model.requiresDeliveryCheck)
        #expect(await service.updateCount == 1)
    }

    @Test("Merged and unknown merge requests expose no state action")
    @MainActor
    func hidesUnsupportedStateActions() {
        for state in ["merged", "locked", "unknown"] {
            let model =
                GitLabResourceMetadataEditorModel(
                    accountID:
                        makeAccountID(),
                    baseline:
                        .mergeRequest(
                            makeTestMergeRequest(
                                state: state
                            )
                        ),
                    apiAccess: .readWrite,
                    service:
                        RecordingMetadataEditingService(),
                    isAccountCurrent: {
                        true
                    },
                    onSuccess: { _ in }
                )

            #expect(
                model.availableStateEvent
                    == nil
            )
        }
    }

    @Test("Initial picker failures preserve the successful resource")
    @MainActor
    func preservesPartialPickerSuccess() async {
        let issue = makeTestIssue(
            assignees: [
                makeTestIssueUser(id: 2),
            ]
        )
        let service =
            RecordingMetadataEditingService(
                labelPageResults: [
                    .success(
                        page([
                            label(name: "bug"),
                        ])
                    ),
                ],
                memberPageResults: [
                    .failure(
                        .api(.server(statusCode: 500))
                    ),
                ]
            )
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(issue),
                apiAccess: .readWrite,
                service: service,
                searchDebounce: .zero,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )

        await model.loadOptions()

        #expect(model.labels.map(\.name) == ["bug"])
        #expect(model.members.map(\.id) == [2])
        #expect(model.labelOptionsError == nil)
        #expect(
            model.memberOptionsError
                == .api(
                    .server(statusCode: 500)
                )
        )
    }

    @Test("A current user absent from active membership is remove-only")
    @MainActor
    func keepsUnverifiedSeedRemoveOnly() async throws {
        let issue = makeTestIssue(
            assignees: [
                makeTestIssueUser(id: 2),
            ]
        )
        let service =
            RecordingMetadataEditingService(
                labelPageResults: [
                    .success(page()),
                ],
                memberPageResults: [
                    .success(
                        page([
                            member(id: 3),
                        ])
                    ),
                ]
            )
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(issue),
                apiAccess: .readWrite,
                service: service,
                searchDebounce: .zero,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )
        await model.loadOptions()
        let seed = try #require(
            model.members.first {
                $0.id == 2
            }
        )

        model.toggleAssignee(seed)
        model.toggleAssignee(seed)

        #expect(
            model.selectedAssigneeIDs.isEmpty
        )
    }

    @Test("An already-applied state reconciles without invalidating mutation caches")
    @MainActor
    func reconcilesStateNoOp() async {
        let baseline = makeTestIssue()
        let latest = makeTestIssue(
            state: "closed"
        )
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .issue(latest),
                ]
            )
        var received:
            GitLabResourceEditResult?
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(baseline),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: {
                    received = $0
                }
            )

        await model.changeState(.close)

        #expect(model.didSucceed)
        #expect(received == .issue(latest))
        #expect(await service.updateCount == 0)
        #expect(
            await service.invalidationCount
                == 0
        )
    }

    @Test("A fresh incompatible merge request state never sends a PUT")
    @MainActor
    func rejectsFreshIncompatibleState() async {
        let baseline =
            makeTestMergeRequest()
        let latest =
            makeTestMergeRequest(
                state: "merged"
            )
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .mergeRequest(latest),
                ]
            )
        var received:
            GitLabResourceEditResult?
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline:
                    .mergeRequest(baseline),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: {
                    received = $0
                }
            )

        await model.changeState(.close)

        #expect(await service.updateCount == 0)
        #expect(received == .mergeRequest(latest))
        #expect(model.failure == .notApplied)
        #expect(!model.didSucceed)
    }

    @Test("Confirmed new-label success invalidates only the project label metadata additionally")
    @MainActor
    func invalidatesConfirmedNewLabel() async {
        let baseline = makeTestIssue()
        let updated = makeTestIssue(
            labels: ["mobile"]
        )
        let service =
            RecordingMetadataEditingService(
                latestResults: [
                    .issue(baseline),
                ],
                updateResult:
                    .success(.issue(updated))
            )
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline: .issue(baseline),
                apiAccess: .readWrite,
                service: service,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )

        model.addLabel(named: "mobile")
        await model.save()

        #expect(await service.updateCount == 1)
        #expect(
            await service.invalidationCount
                == 1
        )
        #expect(
            await service
                .projectLabelInvalidationCount
                == 1
        )
    }

    @Test("Cancellation or account switching during preflight prevents PUT")
    @MainActor
    func rejectsSupersededPreflight() async {
        for cancelsTask in [true, false] {
            let baseline = makeTestIssue()
            let service =
                GatedMetadataEditingService(
                    latest: .issue(
                        baseline
                    ),
                    updated: .issue(
                        makeTestIssue(
                            labels: ["mobile"]
                        )
                    )
                )
            let account =
                MetadataAccountState()
            let model =
                GitLabResourceMetadataEditorModel(
                    accountID:
                        makeAccountID(),
                    baseline:
                        .issue(baseline),
                    apiAccess: .readWrite,
                    service: service,
                    isAccountCurrent: {
                        account.isCurrent
                    },
                    onSuccess: { _ in }
                )
            model.addLabel(named: "mobile")

            let save = Task {
                await model.save()
            }
            await service.waitUntilLatestStarts()
            if cancelsTask {
                save.cancel()
            } else {
                account.isCurrent = false
            }
            await service.releaseLatest()
            await save.value

            #expect(
                await service.updateCount
                    == 0
            )
        }
    }

    @Test("A late search response cannot replace the latest label query")
    @MainActor
    func rejectsStaleLabelSearch() async {
        let service =
            OutOfOrderLabelSearchService()
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline:
                    .issue(makeTestIssue()),
                apiAccess: .readWrite,
                service: service,
                searchDebounce: .zero,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )

        model.labelSearchText = "first"
        await service.waitUntilFirstStarts()
        model.labelSearchText = "second"
        await service.waitUntilSecondStarts()
        await waitUntil {
            model.labels.map(\.name)
                == ["second"]
        }
        await service.releaseFirst()
        await Task.yield()

        #expect(
            model.labels.map(\.name)
                == ["second"]
        )
        #expect(model.labelOptionsError == nil)
    }

    @Test("Repeated last-row appearance loads one metadata page")
    @MainActor
    func suppressesDuplicateLabelPage() async throws {
        let nextURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects/42/labels?page=2"
            )
        )
        let service =
            GatedLabelPageService(
                nextURL: nextURL
            )
        let model =
            GitLabResourceMetadataEditorModel(
                accountID: makeAccountID(),
                baseline:
                    .issue(makeTestIssue()),
                apiAccess: .readWrite,
                service: service,
                searchDebounce: .zero,
                isAccountCurrent: { true },
                onSuccess: { _ in }
            )
        await model.loadOptions()

        let first = Task {
            await model.loadNextLabelsPage()
        }
        await service.waitUntilNextStarts()
        let second = Task {
            await model.loadNextLabelsPage()
        }
        await Task.yield()
        await service.releaseNext()
        await first.value
        await second.value

        #expect(
            await service.nextLoadCount == 1
        )
        #expect(
            model.labels.map(\.name)
                == ["first", "second"]
        )
    }
}

private actor RecordingMetadataEditingService:
    GitLabResourceEditing
{
    private var latestResults:
        [GitLabResourceEditResult]
    private let updateResult:
        Result<
            GitLabResourceEditResult,
            GitLabSessionClientError
        >
    private var labelPageResults:
        [
            Result<
                GitLabResourcePage<
                    GitLabProjectLabel
                >,
                GitLabSessionClientError
            >
        ]
    private var memberPageResults:
        [
            Result<
                GitLabResourcePage<
                    GitLabProjectMember
                >,
                GitLabSessionClientError
            >
        ]

    private(set) var updates:
        [GitLabResourceMetadataChanges] = []
    private(set) var updateCount = 0
    private(set) var invalidationCount = 0
    private(set) var
        projectLabelInvalidationCount = 0

    init(
        latestResults:
            [GitLabResourceEditResult] = [],
        updateResult:
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            > = .failure(
                .api(.invalidResponse)
            ),
        labelPageResults:
            [
                Result<
                    GitLabResourcePage<
                        GitLabProjectLabel
                    >,
                    GitLabSessionClientError
                >
            ] = [],
        memberPageResults:
            [
                Result<
                    GitLabResourcePage<
                        GitLabProjectMember
                    >,
                    GitLabSessionClientError
                >
            ] = []
    ) {
        self.latestResults = latestResults
        self.updateResult = updateResult
        self.labelPageResults =
            labelPageResults
        self.memberPageResults =
            memberPageResults
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        guard !latestResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return latestResults.removeFirst()
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
    }

    func updateMetadata(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceMetadataChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        updateCount += 1
        updates.append(changes)
        switch updateResult {
        case let .success(result):
            return result
        case let .failure(error):
            throw error
        }
    }

    func invalidateAffectedReads(
        for target: GitLabResourceEditTarget
    ) async {
        invalidationCount += 1
    }

    func invalidateProjectLabels(
        projectID: Int
    ) {
        projectLabelInvalidationCount += 1
    }

    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >
    {
        guard !labelPageResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try result(
            labelPageResults.removeFirst()
        )
    }

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        guard !memberPageResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try result(
            memberPageResults.removeFirst()
        )
    }

    private func result<Value>(
        _ result:
            Result<
                Value,
                GitLabSessionClientError
            >
    ) throws(GitLabSessionClientError)
        -> Value
    {
        switch result {
        case let .success(value):
            value
        case let .failure(error):
            throw error
        }
    }
}

@MainActor
private final class MetadataAccountState {
    var isCurrent = true
}

private actor GatedMetadataEditingService:
    GitLabResourceEditing
{
    private let latest:
        GitLabResourceEditResult
    private let updated:
        GitLabResourceEditResult
    private var latestStarted = false
    private var latestStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var latestContinuation:
        CheckedContinuation<Void, Never>?

    private(set) var updateCount = 0

    init(
        latest: GitLabResourceEditResult,
        updated: GitLabResourceEditResult
    ) {
        self.latest = latest
        self.updated = updated
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async -> GitLabResourceEditResult {
        latestStarted = true
        let waiters = latestStartWaiters
        latestStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            latestContinuation = $0
        }
        return latest
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async -> GitLabResourceEditResult {
        updated
    }

    func updateMetadata(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceMetadataChanges
    ) async -> GitLabResourceEditResult {
        updateCount += 1
        return updated
    }

    func invalidateAffectedReads(
        for target: GitLabResourceEditTarget
    ) async {}

    func waitUntilLatestStarts() async {
        guard !latestStarted else {
            return
        }
        await withCheckedContinuation {
            latestStartWaiters.append($0)
        }
    }

    func releaseLatest() {
        latestContinuation?.resume()
        latestContinuation = nil
    }
}

private actor OutOfOrderLabelSearchService:
    GitLabResourceEditing
{
    private var firstStarted = false
    private var secondStarted = false
    private var firstStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var secondStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var firstContinuation:
        CheckedContinuation<Void, Never>?

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
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
        for target: GitLabResourceEditTarget
    ) async {}

    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectLabel
        >
    {
        switch search {
        case "first":
            firstStarted = true
            let waiters = firstStartWaiters
            firstStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation {
                firstContinuation = $0
            }
            return page([
                label(name: "first"),
            ])
        case "second":
            secondStarted = true
            let waiters = secondStartWaiters
            secondStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            return page([
                label(name: "second"),
            ])
        default:
            throw .api(.invalidResponse)
        }
    }

    func waitUntilFirstStarts() async {
        guard !firstStarted else {
            return
        }
        await withCheckedContinuation {
            firstStartWaiters.append($0)
        }
    }

    func waitUntilSecondStarts() async {
        guard !secondStarted else {
            return
        }
        await withCheckedContinuation {
            secondStartWaiters.append($0)
        }
    }

    func releaseFirst() {
        firstContinuation?.resume()
        firstContinuation = nil
    }
}

private actor GatedLabelPageService:
    GitLabResourceEditing
{
    private let nextURL: URL
    private var nextStarted = false
    private var nextStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var nextContinuation:
        CheckedContinuation<Void, Never>?

    private(set) var nextLoadCount = 0

    init(nextURL: URL) {
        self.nextURL = nextURL
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        throw .api(.invalidResponse)
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
        for target: GitLabResourceEditTarget
    ) async {}

    func loadLabelsPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async -> GitLabResourcePage<
        GitLabProjectLabel
    > {
        guard nextPageURL != nil else {
            return page(
                [label(name: "first")],
                nextPageURL: nextURL
            )
        }
        nextLoadCount += 1
        nextStarted = true
        let waiters = nextStartWaiters
        nextStartWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            nextContinuation = $0
        }
        return page([
            label(name: "second"),
        ])
    }

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async -> GitLabResourcePage<
        GitLabProjectMember
    > {
        page()
    }

    func waitUntilNextStarts() async {
        guard !nextStarted else {
            return
        }
        await withCheckedContinuation {
            nextStartWaiters.append($0)
        }
    }

    func releaseNext() {
        nextContinuation?.resume()
        nextContinuation = nil
    }
}

@MainActor
private func waitUntil(
    _ condition: () -> Bool
) async {
    for _ in 0..<100 {
        if condition() {
            return
        }
        await Task.yield()
    }
}

private nonisolated func label(
    name: String
) -> GitLabProjectLabel {
    GitLabProjectLabel(
        id: name.hashValue,
        name: name,
        color: "#FF0000",
        textColor: "#FFFFFF",
        labelDescription: nil,
        archived: false
    )
}

private nonisolated func member(
    id: Int
) -> GitLabProjectMember {
    GitLabProjectMember(
        id: id,
        username: "user-\(id)",
        name: "User \(id)",
        state: "active",
        avatarURL: nil,
        webURL: nil,
        accessLevel: 30
    )
}

private nonisolated func page<Item>(
    _ items: [Item] = [],
    nextPageURL: URL? = nil
) -> GitLabResourcePage<Item> {
    GitLabResourcePage(
        items: items,
        nextPageURL: nextPageURL
    )
}

private nonisolated func makeAccountID()
    -> GitLabAccountID
{
    guard
        let host = try? GitLabHost(
            "gitlab.example.com"
        )
    else {
        preconditionFailure(
            "Test GitLab host must be valid."
        )
    }
    return GitLabAccountID(
        host: host,
        userID: 1
    )
}
