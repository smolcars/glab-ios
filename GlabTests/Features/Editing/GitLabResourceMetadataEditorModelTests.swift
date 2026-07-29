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
                    .success(.issue(updated))
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
                    )
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

    private(set) var updates:
        [GitLabResourceMetadataChanges] = []
    private(set) var updateCount = 0
    private(set) var invalidationCount = 0

    init(
        latestResults:
            [GitLabResourceEditResult] = [],
        updateResult:
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            > = .failure(
                .api(.invalidResponse)
            )
    ) {
        self.latestResults = latestResults
        self.updateResult = updateResult
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
