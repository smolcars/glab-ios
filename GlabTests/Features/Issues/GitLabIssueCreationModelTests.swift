import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue creation model")
struct GitLabIssueCreationModelTests {
    @Test("Restores every exact draft field before creation is enabled")
    @MainActor
    func restoresDraft() async throws {
        let draft = makeDraft(revision: 7)
        let store =
            RecordingIssueCreationDraftStore(
                draft: draft
            )
        let context = try CreationModelContext(
            draftStore: store
        )

        await context.model.restoreDraft()

        #expect(context.model.hasRestoredDraft)
        #expect(
            context.model.selectedProject
                == draft.selectedProject
        )
        #expect(
            context.model.title
                == draft.title
        )
        #expect(
            context.model.rawDescription
                == draft.rawDescription
        )
        #expect(
            context.model.selectedLabelNames
                == draft.labelNames
        )
        #expect(
            context.model.selectedAssigneeIDs
                == draft.assigneeIDs
        )
        #expect(context.model.confidential)
        #expect(
            context.model.dueDate
                == draft.dueDate
        )
        #expect(context.model.draftRevision == 7)
        #expect(context.model.canCreate)
        #expect(
            await context.service
                .resolvedProjectIDs == [42]
        )
    }

    @Test("Inaccessible restored project is cleared without losing issue content")
    @MainActor
    func clearsInaccessibleRestoredProject()
        async throws
    {
        let draft = makeDraft(revision: 7)
        let store =
            RecordingIssueCreationDraftStore(
                draft: draft
            )
        let service =
            RecordingIssueCreationService(
                projectResult:
                    .failure(.api(.notFound))
            )
        let context = try CreationModelContext(
            service: service,
            draftStore: store
        )

        await context.model.restoreDraft()
        _ = await context.model
            .persistForDismissal()

        #expect(
            context.model.selectedProject == nil
        )
        #expect(
            context.model.selectedLabelNames
                .isEmpty
        )
        #expect(
            context.model.selectedAssigneeIDs
                .isEmpty
        )
        #expect(
            context.model.title == draft.title
        )
        #expect(
            context.model.rawDescription
                == draft.rawDescription
        )
        #expect(
            context.model.failure
                == .restoredProjectUnavailable
        )
        let persisted = await store.storedDraft
        #expect(
            persisted?.selectedProject == nil
        )
        #expect(
            persisted?.title == draft.title
        )
    }

    @Test("Transient restore verification keeps the project and blocks creation")
    @MainActor
    func keepsProjectAfterTransientVerificationFailure()
        async throws
    {
        let draft = makeDraft(revision: 7)
        let failure =
            GitLabSessionClientError
                .api(.server(statusCode: 503))
        let context = try CreationModelContext(
            service:
                RecordingIssueCreationService(
                    projectResult:
                        .failure(failure)
                ),
            draftStore:
                RecordingIssueCreationDraftStore(
                    draft: draft
                )
        )

        await context.model.restoreDraft()

        #expect(
            context.model.selectedProject
                == draft.selectedProject
        )
        #expect(
            !context.model
                .isSelectedProjectVerified
        )
        #expect(!context.model.canCreate)
        #expect(
            context.model.failure
                == .projectVerification(failure)
        )

        await context.model
            .loadSelectedProjectMetadata()

        #expect(
            await context.service
                .labelProjectIDs.isEmpty
        )
        #expect(
            await context.service
                .memberProjectIDs.isEmpty
        )

        context.model.title = "Keep editing"

        #expect(
            context.model.failure
                == .projectVerification(failure)
        )

        context.model.selectProject(
            makeTestProject(id: 43)
        )

        #expect(context.model.failure == nil)
        #expect(
            context.model
                .isSelectedProjectVerified
        )
    }

    @Test("Inactive page tail does not stop assignable member pagination")
    @MainActor
    func paginatesPastInactiveMemberTail()
        async throws
    {
        let active = makeMember(id: 7)
        let blocked = makeMember(
            id: 8,
            username: "blocked-user",
            state: "blocked"
        )
        let next = makeMember(
            id: 9,
            username: "next-user"
        )
        let context = try CreationModelContext(
            service:
                RecordingIssueCreationService(
                    members: [
                        active,
                        blocked,
                    ],
                    memberNext: [next]
                )
        )
        await context.model.restoreDraft()
        context.model.selectProject(
            makeTestProject()
        )
        await context.model
            .loadSelectedProjectMetadata()

        #expect(
            context.model
                .displayedAssignableMembers
                .map(\.id) == [7]
        )

        await context.model
            .loadNextAssignableMembersPageIfNeeded(
                after: active
            )

        #expect(
            context.model
                .displayedAssignableMembers
                .map(\.id) == [7, 9]
        )
    }

    @Test("All-inactive member page advances until an assignee is visible")
    @MainActor
    func paginatesPastAllInactiveMemberPage()
        async throws
    {
        let next = makeMember(
            id: 9,
            username: "next-user"
        )
        let context = try CreationModelContext(
            service:
                RecordingIssueCreationService(
                    members: [
                        makeMember(
                            id: 8,
                            username:
                                "blocked-user",
                            state: "blocked"
                        ),
                    ],
                    memberNext: [next]
                )
        )
        await context.model.restoreDraft()
        context.model.selectProject(
            makeTestProject()
        )
        await context.model
            .loadSelectedProjectMetadata()

        #expect(
            context.model
                .displayedAssignableMembers
                .isEmpty
        )

        await context.model
            .loadUntilAssignableMemberVisibleIfNeeded()

        #expect(
            context.model
                .displayedAssignableMembers
                .map(\.id) == [9]
        )
    }

    @Test("Changing projects preserves content and clears scoped choices")
    @MainActor
    func changesProjectSafely() async throws {
        let context = try CreationModelContext()
        await context.model.restoreDraft()
        context.model.title = "Keep title"
        context.model.rawDescription =
            "# Keep Markdown"
        context.model.confidential = true
        context.model.dueDate =
            GitLabIssueDueDate(
                year: 2026,
                month: 8,
                day: 12
            )
        let first = makeTestProject(id: 41)
        context.model.selectProject(first)
        context.model.toggleLabel(
            makeLabel(name: "bug")
        )
        context.model.toggleAssignee(
            makeMember(id: 7)
        )

        let second = makeTestProject(
            id: 42,
            name: "Second",
            nameWithNamespace:
                "Mobile / Second",
            pathWithNamespace:
                "mobile/second"
        )
        context.model.selectProject(second)

        #expect(context.model.title == "Keep title")
        #expect(
            context.model.rawDescription
                == "# Keep Markdown"
        )
        #expect(context.model.confidential)
        #expect(context.model.dueDate != nil)
        #expect(
            context.model.selectedProject?.id
                == second.id
        )
        #expect(
            context.model.selectedLabelNames
                .isEmpty
        )
        #expect(
            context.model.selectedAssigneeIDs
                .isEmpty
        )
    }

    @Test("Loads and paginates labels and members independently")
    @MainActor
    func loadsMetadata() async throws {
        let labelOne = makeLabel(
            id: 1,
            name: "bug"
        )
        let labelTwo = makeLabel(
            id: 2,
            name: "mobile"
        )
        let memberOne = makeMember(id: 7)
        let memberTwo = makeMember(
            id: 8,
            username: "helper-bot"
        )
        let service =
            RecordingIssueCreationService(
                labels: [labelOne],
                labelNext: [labelTwo],
                members: [memberOne],
                memberNext: [memberTwo]
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        context.model.selectProject(
            makeTestProject()
        )

        await context.model
            .loadSelectedProjectMetadata()
        let labels = try #require(
            context.model.labelsModel
        )
        let members = try #require(
            context.model.membersModel
        )
        await labels.loadNextPageIfNeeded(
            after: labelOne
        )
        await members.loadNextPageIfNeeded(
            after: memberOne
        )

        #expect(
            labels.items
                == [labelOne, labelTwo]
        )
        #expect(
            members.items
                == [memberOne, memberTwo]
        )
        #expect(
            await service.labelProjectIDs
                == [42, 42]
        )
        #expect(
            await service.memberProjectIDs
                == [42, 42]
        )
    }

    @Test("Debounced project search sends only the latest query")
    @MainActor
    func debouncesProjectSearch() async throws {
        let service =
            RecordingIssueCreationService(
                projects: [makeTestProject()]
            )
        let context = try CreationModelContext(
            service: service,
            searchDebounce:
                .milliseconds(10)
        )
        await context.model.restoreDraft()

        context.model.projectSearchText =
            "first"
        context.model.projectSearchText =
            " wallet "
        try await Task.sleep(
            for: .milliseconds(80)
        )

        #expect(
            await service.projectSearches
                == ["wallet"]
        )
        #expect(
            context.model.projectsModel
                .items.map(\.id) == [42]
        )
    }

    @Test("Read-only access never sends or marks a creation")
    @MainActor
    func readOnlyNeverCreates() async throws {
        let service =
            RecordingIssueCreationService()
        let context = try CreationModelContext(
            apiAccess: .readOnly,
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        await context.model.submit()

        #expect(
            context.model.failure == .readOnly
        )
        #expect(await service.createCount == 0)
        #expect(
            !(await context.draftStore
                .storedDraft?
                .pendingSubmissionFingerprint
                != nil)
        )
    }

    @Test("A draft storage failure blocks the mutation")
    @MainActor
    func storageFailureBlocksCreation()
        async throws
    {
        let service =
            RecordingIssueCreationService()
        let store =
            RecordingIssueCreationDraftStore(
                failsStores: true
            )
        let context = try CreationModelContext(
            service: service,
            draftStore: store
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        await context.model.submit()

        #expect(
            context.model.failure
                == .draftStorage
        )
        #expect(await service.createCount == 0)
    }

    @Test("Concurrent submit calls send exactly one request")
    @MainActor
    func duplicateTapSendsOnce() async throws {
        let service =
            RecordingIssueCreationService(
                createResults: [
                    .success(makeTestIssue()),
                ],
                holdsCreate: true
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        let first = Task {
            await context.model.submit()
        }
        await service.waitUntilCreateStarts()
        let second = Task {
            await context.model.submit()
        }
        await Task.yield()

        #expect(await service.createCount == 1)
        await service.releaseCreate()
        await first.value
        await second.value
        #expect(await service.createCount == 1)
    }

    @Test("A definite rejection keeps the form and clears the pending marker")
    @MainActor
    func rejectionRemainsEditable() async throws {
        let service =
            RecordingIssueCreationService(
                createResults: [
                    .failure(
                        .api(.validation(
                            statusCode: 400
                        ))
                    ),
                ]
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        await context.model.submit()

        #expect(
            context.model.failure
                == .mutation(
                    .api(.validation(
                        statusCode: 400
                    )),
                    certainty: .rejected
                )
        )
        #expect(!context.model.requiresDeliveryCheck)
        #expect(context.model.title == "New issue")
        #expect(
            await context.draftStore
                .storedDraft?
                .pendingSubmissionFingerprint
                == nil
        )
    }

    @Test("Unknown delivery blocks another request until explicit acknowledgement")
    @MainActor
    func unknownDeliveryBlocksRetry()
        async throws
    {
        let service =
            RecordingIssueCreationService(
                createResults: [
                    .failure(
                        .api(.server(statusCode: 500))
                    ),
                    .success(makeTestIssue()),
                ]
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        await context.model.submit()
        await context.model.submit()

        #expect(await service.createCount == 1)
        #expect(
            context.model.requiresDeliveryCheck
        )
        #expect(
            await context.draftStore
                .storedDraft?
                .pendingSubmissionFingerprint?
                .count == 64
        )

        let acknowledged =
            await context.model
            .acknowledgeDeliveryCheck()
        await context.model.submit()

        #expect(acknowledged)
        #expect(await service.createCount == 2)
        #expect(context.success.issue != nil)
    }

    @Test("A mismatched response is treated as unknown delivery")
    @MainActor
    func mismatchedResponseNeverRoutes()
        async throws
    {
        let service =
            RecordingIssueCreationService(
                createResults: [
                    .success(
                        makeTestIssue(
                            projectID: 999
                        )
                    ),
                ]
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        await context.model.submit()

        #expect(
            context.model.failure
                == .invalidAuthoritativeResponse
        )
        #expect(
            context.model.requiresDeliveryCheck
        )
        #expect(context.success.issue == nil)
        #expect(
            await service.invalidationCount
                == 1
        )
    }

    @Test("Authoritative success invalidates, clears the draft, and returns exact issue")
    @MainActor
    func authoritativeSuccess() async throws {
        let issue = makeTestIssue(
            id: 808,
            iid: 18,
            projectID: 42,
            title: "Returned by GitLab"
        )
        let service =
            RecordingIssueCreationService(
                createResults: [
                    .success(issue),
                ]
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        await context.model.submit()
        let didFlushAfterSuccess =
            await context.model
                .persistForDismissal()

        #expect(context.model.didSucceed)
        #expect(didFlushAfterSuccess)
        #expect(context.success.issue == issue)
        #expect(
            await service.invalidationCount
                == 1
        )
        #expect(
            await context.draftStore
                .storedDraft == nil
        )
    }

    @Test("An account change rejects a late create result")
    @MainActor
    func rejectsLateAccountResult() async throws {
        let service =
            RecordingIssueCreationService(
                createResults: [
                    .success(makeTestIssue()),
                ],
                holdsCreate: true
            )
        let context = try CreationModelContext(
            service: service
        )
        await context.model.restoreDraft()
        fillMinimumForm(context.model)

        let submission = Task {
            await context.model.submit()
        }
        await service.waitUntilCreateStarts()
        context.account.isCurrent = false
        await service.releaseCreate()
        await submission.value

        #expect(context.success.issue == nil)
        #expect(!context.model.didSucceed)
        #expect(
            context.model.requiresDeliveryCheck
        )
        #expect(
            await context.draftStore
                .storedDraft != nil
        )
    }
}

@MainActor
private struct CreationModelContext {
    let service: RecordingIssueCreationService
    let draftStore:
        RecordingIssueCreationDraftStore
    let account = CurrentAccountBox()
    let success = CreationSuccessBox()
    let model: GitLabIssueCreationModel

    init(
        apiAccess: GitLabAPIAccess =
            .readWrite,
        service:
            RecordingIssueCreationService =
                RecordingIssueCreationService(),
        draftStore:
            RecordingIssueCreationDraftStore =
                RecordingIssueCreationDraftStore(),
        searchDebounce: Duration =
            .milliseconds(250)
    ) throws {
        self.service = service
        self.draftStore = draftStore
        let accountID = GitLabAccountID(
            host:
                try GitLabHost(
                    "https://gitlab.example.com"
                ),
            userID: 7
        )
        let account = self.account
        let success = self.success
        model = GitLabIssueCreationModel(
            accountID: accountID,
            apiAccess: apiAccess,
            service: service,
            draftStore: draftStore,
            searchDebounce:
                searchDebounce,
            isAccountCurrent: {
                account.isCurrent
            },
            onSuccess: {
                success.issue = $0
            }
        )
    }
}

@MainActor
private final class CurrentAccountBox {
    var isCurrent = true
}

@MainActor
private final class CreationSuccessBox {
    var issue: GitLabIssue?
}

private actor RecordingIssueCreationDraftStore:
    GitLabIssueCreationDraftStoring
{
    private(set) var storedDraft:
        GitLabIssueCreationDraft?
    private let failsStores: Bool

    init(
        draft: GitLabIssueCreationDraft? = nil,
        failsStores: Bool = false
    ) {
        storedDraft = draft
        self.failsStores = failsStores
    }

    func draft(
        for key: GitLabIssueCreationDraftKey
    ) -> GitLabIssueCreationDraft? {
        storedDraft
    }

    func store(
        _ draft: GitLabIssueCreationDraft,
        for key: GitLabIssueCreationDraftKey
    ) throws(
        GitLabIssueCreationDraftStoreError
    ) {
        guard !failsStores else {
            throw .storage
        }
        storedDraft =
            draft.isPristine ? nil : draft
    }

    func remove(
        for key: GitLabIssueCreationDraftKey
    ) {
        storedDraft = nil
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        storedDraft = nil
    }
}

private actor RecordingIssueCreationService:
    GitLabIssueCreationServing
{
    private let projectResult:
        Result<
            GitLabProject,
            GitLabSessionClientError
        >
    private let projects: [GitLabProject]
    private let labels: [GitLabProjectLabel]
    private let labelNext:
        [GitLabProjectLabel]
    private let members: [GitLabProjectMember]
    private let memberNext:
        [GitLabProjectMember]
    private var createResults: [
        Result<
            GitLabIssue,
            GitLabSessionClientError
        >
    ]
    private let holdsCreate: Bool
    private var createContinuation:
        CheckedContinuation<Void, Never>?
    private var createStartWaiters: [
        CheckedContinuation<Void, Never>
    ] = []

    private(set) var projectSearches:
        [String?] = []
    private(set) var resolvedProjectIDs:
        [Int] = []
    private(set) var labelProjectIDs:
        [Int] = []
    private(set) var memberProjectIDs:
        [Int] = []
    private(set) var createCount = 0
    private(set) var invalidationCount = 0

    init(
        projectResult:
            Result<
                GitLabProject,
                GitLabSessionClientError
            > = .success(makeTestProject()),
        projects: [GitLabProject] = [
            makeTestProject(),
        ],
        labels: [GitLabProjectLabel] = [],
        labelNext:
            [GitLabProjectLabel] = [],
        members: [GitLabProjectMember] = [],
        memberNext:
            [GitLabProjectMember] = [],
        createResults: [
            Result<
                GitLabIssue,
                GitLabSessionClientError
            >
        ] = [
            .success(makeTestIssue()),
        ],
        holdsCreate: Bool = false
    ) {
        self.projectResult = projectResult
        self.projects = projects
        self.labels = labels
        self.labelNext = labelNext
        self.members = members
        self.memberNext = memberNext
        self.createResults = createResults
        self.holdsCreate = holdsCreate
    }

    func loadProject(
        projectID: Int
    ) throws(GitLabSessionClientError)
        -> GitLabProject
    {
        resolvedProjectIDs.append(projectID)
        return try projectResult.get()
    }

    func loadProjectsPage(
        search: String?,
        after nextPageURL: URL?
    ) -> GitLabResourcePage<GitLabProject> {
        projectSearches.append(search)
        return GitLabResourcePage(
            items: projects,
            nextPageURL: nil
        )
    }

    func loadProjectsFirstPage(
        search: String?,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProject
                >
            ) async -> Void
    ) async {
        projectSearches.append(search)
        await onPage(
            GitLabResourcePageEvent(
                page:
                    GitLabResourcePage(
                        items: projects,
                        nextPageURL: nil
                    ),
                source: .network
            )
        )
    }

    func loadLabelsPage(
        projectID: Int,
        after nextPageURL: URL?
    ) -> GitLabResourcePage<
        GitLabProjectLabel
    > {
        labelProjectIDs.append(projectID)
        return GitLabResourcePage(
            items:
                nextPageURL == nil
                ? labels
                : labelNext,
            nextPageURL:
                nextPageURL == nil
                    && !labelNext.isEmpty
                ? Self.labelNextPageURL
                : nil
        )
    }

    func loadLabelsFirstPage(
        projectID: Int,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProjectLabel
                >
            ) async -> Void
    ) async {
        labelProjectIDs.append(projectID)
        await onPage(
            GitLabResourcePageEvent(
                page:
                    GitLabResourcePage(
                        items: labels,
                        nextPageURL:
                            labelNext.isEmpty
                            ? nil
                            : Self
                                .labelNextPageURL
                    ),
                source: .network
            )
        )
    }

    func loadMembersPage(
        projectID: Int,
        after nextPageURL: URL?
    ) -> GitLabResourcePage<
        GitLabProjectMember
    > {
        memberProjectIDs.append(projectID)
        return GitLabResourcePage(
            items:
                nextPageURL == nil
                ? members
                : memberNext,
            nextPageURL:
                nextPageURL == nil
                    && !memberNext.isEmpty
                ? Self.memberNextPageURL
                : nil
        )
    }

    func loadMembersFirstPage(
        projectID: Int,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabProjectMember
                >
            ) async -> Void
    ) async {
        memberProjectIDs.append(projectID)
        await onPage(
            GitLabResourcePageEvent(
                page:
                    GitLabResourcePage(
                        items: members,
                        nextPageURL:
                            memberNext.isEmpty
                            ? nil
                            : Self
                                .memberNextPageURL
                    ),
                source: .network
            )
        )
    }

    func createIssue(
        _ input: GitLabIssueCreationInput
    ) async throws(GitLabSessionClientError)
        -> GitLabIssue
    {
        createCount += 1
        let waiters = createStartWaiters
        createStartWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        if holdsCreate {
            await withCheckedContinuation {
                createContinuation = $0
            }
        }
        guard !createResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try createResults
            .removeFirst()
            .get()
    }

    func invalidateAffectedReads() {
        invalidationCount += 1
    }

    func waitUntilCreateStarts() async {
        guard createCount == 0 else {
            return
        }
        await withCheckedContinuation {
            createStartWaiters.append($0)
        }
    }

    func releaseCreate() {
        createContinuation?.resume()
        createContinuation = nil
    }

    private static let labelNextPageURL =
        URL(
            string:
                "https://gitlab.example.com/api/v4/"
                + "projects/42/labels?page=2"
        )!
    private static let memberNextPageURL =
        URL(
            string:
                "https://gitlab.example.com/api/v4/"
                + "projects/42/members/all?page=2"
        )!
}

@MainActor
private func fillMinimumForm(
    _ model: GitLabIssueCreationModel
) {
    model.selectProject(makeTestProject())
    model.title = "New issue"
}

private nonisolated func makeDraft(
    revision: Int
) -> GitLabIssueCreationDraft {
    GitLabIssueCreationDraft(
        selectedProject:
            GitLabIssueCreationProjectSelection(
                project: makeTestProject()
            ),
        title: "  Exact title  ",
        description:
            "# Exact Markdown\r\n\r\n- [ ] task",
        labelNames: ["bug", "mobile"],
        assigneeIDs: [7, 8],
        confidential: true,
        dueDate:
            GitLabIssueDueDate(
                year: 2026,
                month: 8,
                day: 12
            ),
        revision: revision
    )
}

private nonisolated func makeLabel(
    id: Int = 1,
    name: String
) -> GitLabProjectLabel {
    GitLabProjectLabel(
        id: id,
        name: name,
        color: "#FF7900",
        textColor: "#FFFFFF",
        labelDescription: nil,
        archived: false
    )
}

private nonisolated func makeMember(
    id: Int,
    username: String = "octocat",
    state: String = "active"
) -> GitLabProjectMember {
    GitLabProjectMember(
        id: id,
        username: username,
        name: username,
        state: state,
        avatarURL: nil,
        webURL: nil,
        accessLevel: 30
    )
}
