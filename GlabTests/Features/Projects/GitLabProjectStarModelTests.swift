import Testing
@testable import Glab

@MainActor
@Suite("GitLab project star model")
struct GitLabProjectStarModelTests {
    @Test("Loads the current user's star state once")
    func loadsCurrentStarStateOnce() async throws {
        let context = try StarModelContext(
            statusResults: [.success(true)]
        )

        await context.model.loadIfNeeded(
            project: makeTestProject()
        )
        await context.model.loadIfNeeded(
            project: makeTestProject()
        )

        #expect(
            context.model.state
                == .ready(isStarred: true)
        )
        #expect(
            await context.service.statusRequests
                == [
                    ProjectStarStatusRequest(
                        projectID: 42,
                        userID: 17
                    )
                ]
        )
    }

    @Test("Publishes the authoritative project after starring")
    func starsProject() async throws {
        let updatedProject = makeTestProject(
            starCount: 18
        )
        let context = try StarModelContext(
            statusResults: [.success(false)],
            mutationResults: [
                .success(updatedProject)
            ]
        )
        await context.model.loadIfNeeded(
            project: makeTestProject()
        )

        let change = await context.model.toggle(
            project: makeTestProject()
        )

        #expect(
            context.model.state
                == .ready(isStarred: true)
        )
        #expect(change?.project == updatedProject)
        #expect(change?.isStarred == true)
        #expect(
            await context.service.mutationRequests
                == [
                    ProjectStarMutationRequest(
                        isStarred: true,
                        projectID: 42
                    )
                ]
        )
    }

    @Test("Blocks writes for a read-only account")
    func blocksReadOnlyMutation() async throws {
        let context = try StarModelContext(
            apiAccess: .readOnly,
            statusResults: [.success(false)]
        )
        await context.model.loadIfNeeded(
            project: makeTestProject()
        )

        let change = await context.model.toggle(
            project: makeTestProject()
        )

        #expect(change == nil)
        #expect(context.model.failure == .readOnly)
        #expect(
            await context.service
                .mutationRequests.isEmpty
        )
    }

    @Test("Preserves state after a rejected mutation")
    func preservesStateAfterRejectedMutation() async throws {
        let error = GitLabSessionClientError
            .api(.forbidden)
        let context = try StarModelContext(
            statusResults: [.success(false)],
            mutationResults: [.failure(error)]
        )
        await context.model.loadIfNeeded(
            project: makeTestProject()
        )

        let change = await context.model.toggle(
            project: makeTestProject()
        )

        #expect(change == nil)
        #expect(
            context.model.state
                == .ready(isStarred: false)
        )
        #expect(
            context.model.failure
                == .mutation(error, .rejected)
        )
        #expect(
            await context.service.statusRequests.count
                == 1
        )
    }

    @Test("Rechecks state after uncertain mutation delivery")
    func rechecksAfterUncertainDelivery() async throws {
        let error = GitLabSessionClientError
            .api(.connectivity(.timedOut))
        let context = try StarModelContext(
            statusResults: [
                .success(false),
                .success(true),
            ],
            mutationResults: [.failure(error)]
        )
        await context.model.loadIfNeeded(
            project: makeTestProject()
        )

        let change = await context.model.toggle(
            project: makeTestProject()
        )

        #expect(change == nil)
        #expect(
            context.model.state
                == .ready(isStarred: true)
        )
        #expect(
            context.model.failure
                == .mutation(
                    error,
                    .deliveryUnknown
                )
        )
        #expect(
            await context.service.statusRequests.count
                == 2
        )
    }
}

@MainActor
private struct StarModelContext {
    let service: RecordingProjectStarringService
    let account = ProjectStarCurrentAccountBox()
    let model: GitLabProjectStarModel

    init(
        apiAccess: GitLabAPIAccess = .readWrite,
        statusResults: [
            Result<
                Bool,
                GitLabSessionClientError
            >
        ],
        mutationResults: [
            Result<
                GitLabProject,
                GitLabSessionClientError
            >
        ] = []
    ) throws {
        let service = RecordingProjectStarringService(
            statusResults: statusResults,
            mutationResults: mutationResults
        )
        self.service = service
        let account = self.account
        model = GitLabProjectStarModel(
            accountID: GitLabAccountID(
                host: try GitLabHost(
                    "gitlab.example.com"
                ),
                userID: 17
            ),
            apiAccess: apiAccess,
            service: service,
            isAccountCurrent: {
                account.isCurrent
            }
        )
    }
}

@MainActor
private final class ProjectStarCurrentAccountBox {
    var isCurrent = true
}

private actor RecordingProjectStarringService:
    GitLabProjectStarringServing
{
    private var statusResults: [
        Result<
            Bool,
            GitLabSessionClientError
        >
    ]
    private var mutationResults: [
        Result<
            GitLabProject,
            GitLabSessionClientError
        >
    ]
    private(set) var statusRequests: [
        ProjectStarStatusRequest
    ] = []
    private(set) var mutationRequests: [
        ProjectStarMutationRequest
    ] = []

    init(
        statusResults: [
            Result<
                Bool,
                GitLabSessionClientError
            >
        ],
        mutationResults: [
            Result<
                GitLabProject,
                GitLabSessionClientError
            >
        ]
    ) {
        self.statusResults = statusResults
        self.mutationResults = mutationResults
    }

    func isStarred(
        _ project: GitLabProject,
        byUserID userID: Int
    ) async throws(GitLabSessionClientError) -> Bool {
        statusRequests.append(
            ProjectStarStatusRequest(
                projectID: project.id,
                userID: userID
            )
        )
        guard !statusResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try statusResults.removeFirst().get()
    }

    func setStarred(
        _ isStarred: Bool,
        for project: GitLabProject
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
    {
        mutationRequests.append(
            ProjectStarMutationRequest(
                isStarred: isStarred,
                projectID: project.id
            )
        )
        guard !mutationResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try mutationResults
            .removeFirst()
            .get()
    }
}

private struct ProjectStarStatusRequest:
    Equatable,
    Sendable
{
    let projectID: Int
    let userID: Int
}

private struct ProjectStarMutationRequest:
    Equatable,
    Sendable
{
    let isStarred: Bool
    let projectID: Int
}
