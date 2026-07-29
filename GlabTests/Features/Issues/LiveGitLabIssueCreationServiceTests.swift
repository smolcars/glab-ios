import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab issue creation service")
struct LiveGitLabIssueCreationServiceTests {
    @Test("Loads and caches project-scoped creation metadata")
    func loadsCreationMetadata() async throws {
        let project = makeTestProject()
        let label = makeLabel()
        let member = makeMember()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/labels?page=2"
            )
        )
        let client = RecordingCreationClient(
            project: project,
            label: label,
            member: member,
            issueResult:
                .success(makeTestIssue()),
            nextPageURL: nextPageURL
        )
        let service =
            LiveGitLabIssueCreationService(
                client: client
            )

        let resolvedProject =
            try await service.loadProject(
                projectID: 42
            )
        let projectPage =
            try await service.loadProjectsPage(
                search: "wallet",
                after: nil
            )
        let projectNext =
            try await service.loadProjectsPage(
                search: "ignored",
                after: nextPageURL
            )
        let labelPage =
            try await service.loadLabelsPage(
                projectID: 42,
                after: nil
            )
        let memberPage =
            try await service.loadMembersPage(
                projectID: 42,
                after: nil
            )
        let projectEvents =
            CreationPageEventCollector<
                GitLabProject
            >()
        let labelEvents =
            CreationPageEventCollector<
                GitLabProjectLabel
            >()
        let memberEvents =
            CreationPageEventCollector<
                GitLabProjectMember
            >()

        try await service
            .loadProjectsFirstPage(
                search: "wallet",
                refreshBehavior: .ifStale
            ) {
                await projectEvents.append($0)
            }
        try await service
            .loadLabelsFirstPage(
                projectID: 42,
                refreshBehavior: .ifStale
            ) {
                await labelEvents.append($0)
            }
        try await service
            .loadMembersFirstPage(
                projectID: 42,
                refreshBehavior: .ifStale
            ) {
                await memberEvents.append($0)
            }

        #expect(resolvedProject == project)
        #expect(projectPage.items == [project])
        #expect(projectNext.items == [project])
        #expect(labelPage.items == [label])
        #expect(memberPage.items == [member])
        #expect(
            projectPage.nextPageURL
                == nextPageURL
        )
        #expect(
            await projectEvents.events
                .map(\.items) == [[project]]
        )
        #expect(
            await labelEvents.events
                .map(\.items) == [[label]]
        )
        #expect(
            await memberEvents.events
                .map(\.items) == [[member]]
        )
        #expect(
            await client.cachePolicies
                == [
                    .projects,
                    .projects,
                    .projects,
                ]
        )
        #expect(
            await client.refreshBehaviors
                == [
                    .ifStale,
                    .ifStale,
                    .ifStale,
                ]
        )
        #expect(
            await client.pageRequests
                == [
                    "initial:projects",
                    "next:\(nextPageURL.absoluteString)",
                    "initial:projects/42/labels",
                    "initial:projects/42/members/all",
                    "initial:projects",
                    "initial:projects/42/labels",
                    "initial:projects/42/members/all",
                ]
        )
        #expect(
            await client.sentRequests
                == [
                    record(
                        GitLabProjectEndpoints
                            .project(
                                pathWithNamespace:
                                    "42"
                            )
                    ),
                ]
        )
    }

    @Test("Creates once and invalidates only after confirmed success")
    func createsAndInvalidates() async throws {
        let issue = makeTestIssue()
        let client = RecordingCreationClient(
            issueResult: .success(issue)
        )
        let service =
            LiveGitLabIssueCreationService(
                client: client
            )
        let input = try GitLabIssueCreationInput(
            projectID: issue.projectID,
            title: issue.title
        )

        let created = try await service
            .createIssue(input)

        #expect(created == issue)
        #expect(await client.sendCount == 1)
        #expect(
            await client.invalidatedRequests
                .isEmpty
        )

        await service.invalidateAffectedReads(
            projectID: 42
        )

        #expect(
            await client.invalidatedRequests
                == expectedInvalidations
        )
    }

    @Test(
        "Invalidates possible stale reads only when failed delivery is unknown",
        arguments: [
            (
                GitLabSessionClientError
                    .api(.forbidden),
                false
            ),
            (
                GitLabSessionClientError
                    .api(.rateLimited(
                        retryAfterSeconds: 30
                    )),
                true
            ),
            (
                GitLabSessionClientError
                    .api(.cancelled),
                true
            ),
        ]
    )
    func invalidatesUnknownDelivery(
        _ failure: GitLabSessionClientError,
        shouldInvalidate: Bool
    ) async throws {
        let client = RecordingCreationClient(
            issueResult: .failure(failure)
        )
        let service =
            LiveGitLabIssueCreationService(
                client: client
            )
        let input = try GitLabIssueCreationInput(
            projectID: 42,
            title: "Issue"
        )

        await #expect(throws: failure) {
            try await service.createIssue(input)
        }

        #expect(await client.sendCount == 1)
        #expect(
            await client.invalidatedRequests
                == (
                    shouldInvalidate
                    ? expectedInvalidations
                    : []
                )
        )
    }

    private var expectedInvalidations:
        [RecordedCreationRequest]
    {
        [
            record(
                GitLabIssueEndpoints
                    .assignedIssues
            ),
            record(
                GitLabIssueEndpoints
                    .issues(for: .created)
            ),
            record(
                HomeDashboardEndpoints
                    .assignedIssues
            ),
            record(
                HomeDashboardEndpoints
                    .createdIssues
            ),
            record(
                GitLabProjectEndpoints
                    .projects(for: .recent)
            ),
            record(
                HomeDashboardEndpoints
                    .recentProjects
            ),
            record(
                GitLabIssueEndpoints
                    .projectIssues(
                        projectID: 42,
                        state: .opened
                    )
            ),
        ]
    }

    private func makeLabel()
        -> GitLabProjectLabel
    {
        GitLabProjectLabel(
            id: 1,
            name: "bug",
            color: "#FF0000",
            textColor: "#FFFFFF",
            labelDescription: nil,
            archived: false
        )
    }

    private func makeMember()
        -> GitLabProjectMember
    {
        GitLabProjectMember(
            id: 7,
            username: "octocat",
            name: "The Octocat",
            state: "active",
            avatarURL: nil,
            webURL: nil,
            accessLevel: 30
        )
    }
}

private nonisolated struct RecordedCreationRequest:
    Equatable,
    Sendable
{
    let method: GitLabHTTPMethod
    let path: String
}

private nonisolated func record<Response>(
    _ request: GitLabAPIRequest<Response>
) -> RecordedCreationRequest {
    RecordedCreationRequest(
        method: request.method,
        path:
            request.pathComponents
                .joined(separator: "/")
    )
}

private actor RecordingCreationClient:
    GitLabPaginatedSessionRequestSending
{
    let project: GitLabProject
    let label: GitLabProjectLabel
    let member: GitLabProjectMember
    let issueResult:
        Result<
            GitLabIssue,
            GitLabSessionClientError
        >
    let nextPageURL: URL?

    private(set) var pageRequests: [String] = []
    private(set) var cachePolicies:
        [GitLabResponseCachePolicy] = []
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []
    private(set) var invalidatedRequests:
        [RecordedCreationRequest] = []
    private(set) var sentRequests:
        [RecordedCreationRequest] = []
    private(set) var sendCount = 0

    init(
        project: GitLabProject = makeTestProject(),
        label: GitLabProjectLabel =
            GitLabProjectLabel(
                id: 1,
                name: "bug",
                color: "#FF0000",
                textColor: "#FFFFFF",
                labelDescription: nil,
                archived: false
            ),
        member: GitLabProjectMember =
            GitLabProjectMember(
                id: 7,
                username: "octocat",
                name: "The Octocat",
                state: "active",
                avatarURL: nil,
                webURL: nil,
                accessLevel: 30
            ),
        issueResult:
            Result<
                GitLabIssue,
                GitLabSessionClientError
            >,
        nextPageURL: URL? = nil
    ) {
        self.project = project
        self.label = label
        self.member = member
        self.issueResult = issueResult
        self.nextPageURL = nextPageURL
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sendCount += 1
        sentRequests.append(record(endpoint))
        let value: Any
        if Response.self == GitLabIssue.self {
            value = try result(issueResult)
        } else if Response.self
            == GitLabProject.self
        {
            value = project
        } else {
            throw .api(.invalidResponse)
        }
        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }
        return response
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        switch page {
        case let .initial(endpoint):
            pageRequests.append(
                "initial:"
                    + endpoint.pathComponents
                    .joined(separator: "/")
            )
        case let .next(url):
            pageRequests.append(
                "next:\(url.absoluteString)"
            )
        }

        let value: Any
        if Response.self == [GitLabProject].self {
            value = [project]
        } else if
            Response.self
                == [GitLabProjectLabel].self
        {
            value = [label]
        } else if
            Response.self
                == [GitLabProjectMember].self
        {
            value = [member]
        } else {
            throw .api(.invalidResponse)
        }
        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }

        return GitLabAPIResponse(
            value: response,
            metadata: GitLabResponseMetadata(
                nextPageURL: nextPageURL
            )
        )
    }

    func loadPage<Response>(
        _ page: GitLabAPIPageRequest<Response>,
        cachePolicy:
            GitLabResponseCachePolicy,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        cachePolicies.append(cachePolicy)
        refreshBehaviors.append(
            refreshBehavior
        )
        let response = try await sendPage(page)
        await onResponse(
            GitLabAPIResponseEvent(
                value: response.value,
                metadata: response.metadata,
                source: .cache(.stale)
            )
        )
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) {
        invalidatedRequests.append(
            record(endpoint)
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

private actor CreationPageEventCollector<
    Item: Sendable
> {
    private(set) var events:
        [GitLabResourcePage<Item>] = []

    func append(
        _ event: GitLabResourcePageEvent<Item>
    ) {
        events.append(event.page)
    }
}
