import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab resource edit service")
struct LiveGitLabResourceEditServiceTests {
    @Test("Loads issue and merge request freshness directly without cache APIs")
    func loadsLatestDirectly() async throws {
        let issue = makeTestIssue(
            id: 101,
            iid: 7,
            projectID: 42
        )
        let mergeRequest =
            makeTestMergeRequest(
                id: 202,
                iid: 8,
                projectID: 43
            )
        let client =
            RecordingResourceEditClient(
                issueResult: .success(issue),
                mergeRequestResult:
                    .success(mergeRequest)
            )
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        let loadedIssue =
            try await service.loadLatest(
                .issue(issue.route)
            )
        let loadedMergeRequest =
            try await service.loadLatest(
                .mergeRequest(
                    mergeRequest.route
                )
            )

        #expect(loadedIssue == .issue(issue))
        #expect(
            loadedMergeRequest
                == .mergeRequest(mergeRequest)
        )
        #expect(
            await client.sentRequests
                == [
                    recorded(
                        GitLabIssueEndpoints.issue(
                            at: issue.route
                        )
                    ),
                    recorded(
                        GitLabMergeRequestEndpoints
                            .mergeRequest(
                                at:
                                    mergeRequest.route
                            )
                    ),
                ]
        )
        #expect(
            await client.loadResponseCount == 0
        )
    }

    @Test("Issue invalidation waits for authoritative reconciliation")
    func updatesIssue() async throws {
        let issue = makeTestIssue(
            id: 101,
            iid: 7,
            projectID: 42,
            title: "Edited issue"
        )
        let changes =
            try GitLabResourceEditChanges(
                title: "Edited issue"
            )
        let client =
            RecordingResourceEditClient(
                issueResult: .success(issue)
            )
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        let result = try await service.update(
            .issue(issue.route),
            changes: changes
        )

        #expect(result == .issue(issue))
        #expect(
            await client.sentRequests
                == [
                    recorded(
                        try GitLabIssueEndpoints
                            .update(
                                at: issue.route,
                                changes: changes
                            )
                    ),
                ]
        )
        #expect(
            await client.invalidatedRequests
                .isEmpty
        )

        await service.invalidateAffectedReads(
            for: .issue(issue.route)
        )

        #expect(
            await client.invalidatedRequests
                == issueInvalidations(
                    route: issue.route
                )
        )
    }

    @Test("Merge request invalidation waits for authoritative reconciliation")
    func updatesMergeRequest() async throws {
        let mergeRequest =
            makeTestMergeRequest(
                id: 202,
                iid: 8,
                projectID: 43,
                description: "Edited body"
            )
        let changes =
            try GitLabResourceEditChanges(
                description: "Edited body"
            )
        let client =
            RecordingResourceEditClient(
                mergeRequestResult:
                    .success(mergeRequest)
            )
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        let result = try await service.update(
            .mergeRequest(
                mergeRequest.route
            ),
            changes: changes
        )

        #expect(
            result
                == .mergeRequest(mergeRequest)
        )
        #expect(
            await client.sentRequests
                == [
                    recorded(
                        try GitLabMergeRequestEndpoints
                            .update(
                                at:
                                    mergeRequest.route,
                                changes: changes
                            )
                    ),
                ]
        )
        #expect(
            await client.invalidatedRequests
                .isEmpty
        )

        await service.invalidateAffectedReads(
            for:
                .mergeRequest(
                    mergeRequest.route
                )
        )

        #expect(
            await client.invalidatedRequests
                == mergeRequestInvalidations(
                    route:
                        mergeRequest.route
                )
        )
    }

    @Test(
        "A failed or canceled update leaves every cached read intact",
        arguments: [
            GitLabSessionClientError
                .api(.forbidden),
            GitLabSessionClientError
                .api(.cancelled),
        ]
    )
    func leavesCacheAfterFailure(
        _ failure: GitLabSessionClientError
    ) async throws {
        let issue = makeTestIssue()
        let changes =
            try GitLabResourceEditChanges(
                title: "Edited issue"
            )
        let client =
            RecordingResourceEditClient(
                issueResult: .failure(failure)
            )
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        await #expect(throws: failure) {
            try await service.update(
                .issue(issue.route),
                changes: changes
            )
        }

        #expect(
            await client.sentRequests.count == 1
        )
        #expect(
            await client.invalidatedRequests
                .isEmpty
        )
    }

    @Test("Loads searchable paginated labels and effective members")
    func loadsMetadataPages() async throws {
        let label = GitLabProjectLabel(
            id: 1,
            name: "needs QA",
            color: "#FF0000",
            textColor: "#FFFFFF",
            labelDescription: nil,
            archived: false
        )
        let member = GitLabProjectMember(
            id: 7,
            username: "helper-bot",
            name: "Helper Bot",
            state: "active",
            avatarURL: nil,
            webURL: nil,
            accessLevel: 30
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/labels?page=2"
            )
        )
        let client =
            RecordingResourceEditClient(
                labels: [label],
                members: [member],
                nextPageURL: nextPageURL
            )
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        let labels =
            try await service.loadLabelsPage(
                projectID: 42,
                search: " needs QA ",
                after: nil
            )
        let members =
            try await service.loadMembersPage(
                projectID: 42,
                search: " helper ",
                after: nil
            )
        let nextLabels =
            try await service.loadLabelsPage(
                projectID: 42,
                search: "ignored",
                after: nextPageURL
            )

        #expect(labels.items == [label])
        #expect(members.items == [member])
        #expect(nextLabels.items == [label])
        #expect(
            labels.nextPageURL == nextPageURL
        )
        #expect(
            await client.pageRequests
                == [
                    "initial:projects/42/labels"
                        + "?with_counts=false"
                        + "&include_ancestor_groups=true"
                        + "&per_page=20"
                        + "&search=needs QA",
                    "initial:projects/42/members/all"
                        + "?per_page=20"
                        + "&query=helper",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
    }

    @Test("Updates issue and merge request metadata without invalidating early")
    func updatesMetadata() async throws {
        let issue = makeTestIssue()
        let mergeRequest =
            makeTestMergeRequest(
                id: 202,
                iid: 8,
                projectID: 43
            )
        let client =
            RecordingResourceEditClient(
                issueResult: .success(issue),
                mergeRequestResult:
                    .success(mergeRequest)
            )
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        let issueResult =
            try await service.updateMetadata(
                .issue(issue.route),
                changes:
                    GitLabResourceMetadataChanges(
                        stateEvent: .close
                    )
            )
        let mergeRequestResult =
            try await service.updateMetadata(
                .mergeRequest(
                    mergeRequest.route
                ),
                changes:
                    GitLabResourceMetadataChanges(
                        reviewerIDs: [7]
                    )
            )

        #expect(issueResult == .issue(issue))
        #expect(
            mergeRequestResult
                == .mergeRequest(mergeRequest)
        )
        #expect(
            await client.sentRequests
                == [
                    recorded(
                        try GitLabIssueEndpoints
                            .updateMetadata(
                                at: issue.route,
                                changes:
                                    GitLabResourceMetadataChanges(
                                        stateEvent:
                                            .close
                                    )
                            )
                    ),
                    recorded(
                        try GitLabMergeRequestEndpoints
                            .updateMetadata(
                                at:
                                    mergeRequest.route,
                                changes:
                                    GitLabResourceMetadataChanges(
                                        reviewerIDs:
                                            [7]
                                    )
                            )
                    ),
                ]
        )
        #expect(
            await client.invalidatedRequests
                .isEmpty
        )
    }

    @Test("Project label invalidation is exact and explicit")
    func invalidatesProjectLabels() async {
        let client =
            RecordingResourceEditClient()
        let service =
            LiveGitLabResourceEditService(
                client: client
            )

        await service.invalidateProjectLabels(
            projectID: 42
        )

        #expect(
            await client.invalidatedRequests
                == [
                    recorded(
                        GitLabIssueCreationEndpoints
                            .labels(
                                projectID: 42
                            )
                    ),
                ]
        )
    }
}

private nonisolated struct RecordedResourceEditRequest:
    Equatable,
    Sendable
{
    let method: GitLabHTTPMethod
    let path: String
    let query: String
}

private nonisolated func recorded<Response>(
    _ request: GitLabAPIRequest<Response>
) -> RecordedResourceEditRequest {
    RecordedResourceEditRequest(
        method: request.method,
        path:
            request.pathComponents
                .joined(separator: "/"),
        query:
            request.queryItems
                .map {
                    "\($0.name)=\($0.value ?? "")"
                }
                .joined(separator: "&")
    )
}

private nonisolated func issueInvalidations(
    route: GitLabIssueRoute
) -> [RecordedResourceEditRequest] {
    [
        recorded(
            GitLabIssueEndpoints.issue(
                at: route
            )
        ),
    ]
        + GitLabIssueListMode.allCases
        .map {
            recorded(
                GitLabIssueEndpoints
                    .issues(for: $0)
            )
        }
        + [
        recorded(
            HomeDashboardEndpoints
                .assignedIssues
        ),
        recorded(
            HomeDashboardEndpoints
                .createdIssues
        ),
    ]
        + GitLabProjectIssueState.allCases
        .map {
            recorded(
                GitLabIssueEndpoints
                    .projectIssues(
                        projectID:
                            route.projectID,
                        state: $0
                    )
            )
        }
        + todoInvalidations()
}

private nonisolated func mergeRequestInvalidations(
    route: GitLabMergeRequestRoute
) -> [RecordedResourceEditRequest] {
    [
        recorded(
            GitLabMergeRequestEndpoints
                .mergeRequest(at: route)
        ),
    ]
        + GitLabMergeRequestListMode
        .allCases
        .map {
            recorded(
                GitLabMergeRequestEndpoints
                    .mergeRequests(for: $0)
            )
        }
        + [
        recorded(
            HomeDashboardEndpoints
                .assignedMergeRequests
        ),
        recorded(
            HomeDashboardEndpoints
                .createdMergeRequests
        ),
        recorded(
            HomeDashboardEndpoints
                .reviewRequests
        ),
    ]
        + GitLabProjectMergeRequestState
        .allCases
        .map {
            recorded(
                GitLabMergeRequestEndpoints
                    .projectMergeRequests(
                        projectID:
                            route.projectID,
                        state: $0
                    )
            )
        }
        + todoInvalidations()
}

private nonisolated func todoInvalidations()
    -> [RecordedResourceEditRequest]
{
    GitLabTodoState.allCases.flatMap { state in
        GitLabTodoTargetFilter.allCases.map {
            recorded(
                GitLabTodoEndpoints.todos(
                    state: state,
                    targetFilter: $0
                )
            )
        }
    }
}

private actor RecordingResourceEditClient:
    GitLabPaginatedSessionRequestSending
{
    private let issueResult:
        Result<
            GitLabIssue,
            GitLabSessionClientError
        >
    private let mergeRequestResult:
        Result<
            GitLabMergeRequest,
            GitLabSessionClientError
        >
    private let labels: [GitLabProjectLabel]
    private let members: [GitLabProjectMember]
    private let nextPageURL: URL?

    private(set) var sentRequests:
        [RecordedResourceEditRequest] = []
    private(set) var pageRequests:
        [String] = []
    private(set) var invalidatedRequests:
        [RecordedResourceEditRequest] = []
    private(set) var loadResponseCount = 0

    init(
        issueResult:
            Result<
                GitLabIssue,
                GitLabSessionClientError
            > = .failure(
                .api(.invalidResponse)
            ),
        mergeRequestResult:
            Result<
                GitLabMergeRequest,
                GitLabSessionClientError
            > = .failure(
                .api(.invalidResponse)
            ),
        labels: [GitLabProjectLabel] = [],
        members: [GitLabProjectMember] = [],
        nextPageURL: URL? = nil
    ) {
        self.issueResult = issueResult
        self.mergeRequestResult =
            mergeRequestResult
        self.labels = labels
        self.members = members
        self.nextPageURL = nextPageURL
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sentRequests.append(
            recorded(endpoint)
        )
        if Response.self == GitLabIssue.self {
            guard
                let response =
                    try result(issueResult)
                        as? Response
            else {
                throw .api(.invalidResponse)
            }
            return response
        }
        if
            Response.self
                == GitLabMergeRequest.self
        {
            guard
                let response =
                    try result(
                        mergeRequestResult
                    ) as? Response
            else {
                throw .api(.invalidResponse)
            }
            return response
        }
        throw .api(.invalidResponse)
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        switch page {
        case let .initial(endpoint):
            let query =
                endpoint.queryItems
                .map {
                    "\($0.name)=\($0.value ?? "")"
                }
                .joined(separator: "&")
            pageRequests.append(
                "initial:"
                    + endpoint.pathComponents
                    .joined(separator: "/")
                    + (query.isEmpty
                        ? ""
                        : "?\(query)")
            )
        case let .next(url):
            pageRequests.append(
                "next:\(url.absoluteString)"
            )
        }

        let value: Any
        if
            Response.self
                == [GitLabProjectLabel].self
        {
            value = labels
        } else if
            Response.self
                == [GitLabProjectMember].self
        {
            value = members
        } else {
            throw .api(.invalidResponse)
        }
        guard
            let response = value as? Response
        else {
            throw .api(.invalidResponse)
        }
        return GitLabAPIResponse(
            value: response,
            metadata: GitLabResponseMetadata(
                nextPageURL: nextPageURL
            )
        )
    }

    func loadResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        cachePolicy:
            GitLabResponseCachePolicy,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(
        GitLabSessionClientError
    ) {
        loadResponseCount += 1
        throw .api(.invalidResponse)
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) {
        invalidatedRequests.append(
            recorded(endpoint)
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
