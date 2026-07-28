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

    @Test("Updates an issue once and invalidates every exact affected read")
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
                == issueInvalidations(
                    route: issue.route
                )
        )
    }

    @Test("Updates a merge request once and invalidates every exact affected read")
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
        recorded(
            GitLabIssueEndpoints.assignedIssues
        ),
        recorded(
            HomeDashboardEndpoints
                .assignedIssues
        ),
    ] + todoInvalidations()
}

private nonisolated func mergeRequestInvalidations(
    route: GitLabMergeRequestRoute
) -> [RecordedResourceEditRequest] {
    [
        recorded(
            GitLabMergeRequestEndpoints
                .mergeRequest(at: route)
        ),
        recorded(
            GitLabMergeRequestEndpoints
                .mergeRequests(for: .assigned)
        ),
        recorded(
            GitLabMergeRequestEndpoints
                .mergeRequests(
                    for: .reviewRequested
                )
        ),
        recorded(
            HomeDashboardEndpoints
                .assignedMergeRequests
        ),
        recorded(
            HomeDashboardEndpoints
                .reviewRequests
        ),
    ] + todoInvalidations()
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
    GitLabSessionRequestSending
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

    private(set) var sentRequests:
        [RecordedResourceEditRequest] = []
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
            )
    ) {
        self.issueResult = issueResult
        self.mergeRequestResult =
            mergeRequestResult
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
            return try result(issueResult)
                as! Response
        }
        if
            Response.self
                == GitLabMergeRequest.self
        {
            return try result(
                mergeRequestResult
            ) as! Response
        }
        throw .api(.invalidResponse)
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
