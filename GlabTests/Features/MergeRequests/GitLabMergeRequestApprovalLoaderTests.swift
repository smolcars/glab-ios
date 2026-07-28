import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request approval loader")
struct GitLabMergeRequestApprovalLoaderTests {
    @Test("Loads and cache-revalidates approval status")
    func loadsApprovals() async throws {
        let summary = makeApprovalSummary()
        let client = RecordingApprovalClient(
            result: .success(summary),
            eventSources: [
                .cache(.stale),
                .network,
            ]
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )
        let recorder = ApprovalEventRecorder()

        let direct =
            try await loader
                .loadMergeRequestApproval(
                    at: route
                )
        try await loader
            .loadMergeRequestApproval(
                at: route,
                refreshBehavior: .ifStale
            ) {
                await recorder.append($0)
            }

        #expect(direct == .available(summary))
        #expect(
            await recorder.values.map(\.value)
                == [
                    .available(summary),
                    .available(summary),
                ]
        )
        #expect(
            await recorder.values.map(\.source)
                == [
                    .cache(.stale),
                    .network,
                ]
        )
        #expect(
            await client.cachePolicies
                == [.mergeRequestReadiness]
        )
        #expect(
            await client.refreshBehaviors
                == [.ifStale]
        )
        #expect(
            await client.paths
                == [
                    approvalPath,
                    approvalPath,
                ]
        )
    }

    @Test(
        "Maps unavailable approval capabilities without failing MR detail",
        arguments: [
            GitLabSessionClientError.api(
                .forbidden
            ),
            GitLabSessionClientError.api(
                .notFound
            ),
        ]
    )
    func mapsUnavailableCapability(
        failure: GitLabSessionClientError
    ) async throws {
        let client = RecordingApprovalClient(
            result: .failure(failure)
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )
        let recorder = ApprovalEventRecorder()

        let direct =
            try await loader
                .loadMergeRequestApproval(
                    at: route
                )
        try await loader
            .loadMergeRequestApproval(
                at: route,
                refreshBehavior: .always
            ) {
                await recorder.append($0)
            }

        #expect(direct == .unavailable)
        #expect(
            await recorder.values.map(\.value)
                == [.unavailable]
        )
        #expect(
            await recorder.values.map(\.source)
                == [.network]
        )
    }

    @Test(
        "Preserves actionable approval failures",
        arguments: [
            GitLabSessionClientError.api(
                .unauthenticated
            ),
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            ),
            GitLabSessionClientError.api(
                .decoding
            ),
        ]
    )
    func preservesFailure(
        failure: GitLabSessionClientError
    ) async {
        let client = RecordingApprovalClient(
            result: .failure(failure)
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )

        await #expect(throws: failure) {
            try await loader
                .loadMergeRequestApproval(
                    at: route
                )
        }
    }

    private var route:
        GitLabMergeRequestRoute
    {
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 7
        )
    }

    private var approvalPath: [String] {
        [
            "projects",
            "42",
            "merge_requests",
            "7",
            "approvals",
        ]
    }

    private func makeApprovalSummary()
        -> GitLabMergeRequestApprovalSummary
    {
        GitLabMergeRequestApprovalSummary(
            approved: true,
            approvalsRequired: 2,
            approvalsLeft: 0,
            approvedBy: []
        )
    }
}

@Suite("GitLab merge request approval model")
@MainActor
struct GitLabMergeRequestApprovalModelTests {
    @Test("Retains cached approval data when refresh fails")
    func retainsApprovalAfterRefreshFailure()
        async
    {
        let summary =
            GitLabMergeRequestApprovalSummary(
                approved: true,
                approvalsRequired: 1,
                approvalsLeft: 0,
                approvedBy: []
            )
        let loader = StubApprovalLoader(
            results: [
                .success(.available(summary)),
                .failure(
                    .api(
                        .server(statusCode: 503)
                    )
                ),
            ]
        )
        let model =
            GitLabMergeRequestApprovalModel(
                route:
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                loader: loader
            )

        await model.loadIfNeeded()
        await model.retry()

        #expect(
            model.state
                == .loaded(
                    .available(summary)
                )
        )
        #expect(
            model.refreshError
                == .api(
                    .server(statusCode: 503)
                )
        )
        #expect(
            await loader.refreshBehaviors
                == [.ifStale, .always]
        )
    }

    @Test("Exposes approval authentication failures")
    func exposesAuthenticationFailure() async {
        let loader = StubApprovalLoader(
            results: [
                .failure(
                    .api(.unauthenticated)
                ),
            ]
        )
        let model =
            GitLabMergeRequestApprovalModel(
                route:
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                loader: loader
            )

        await model.loadIfNeeded()

        #expect(
            model.authenticationFailure
                == .api(.unauthenticated)
        )
    }
}

private actor RecordingApprovalClient:
    GitLabPaginatedSessionRequestSending
{
    let result:
        Result<
            GitLabMergeRequestApprovalSummary,
            GitLabSessionClientError
        >
    let eventSources:
        [GitLabAPIResponseSource]
    private(set) var paths:
        [[String]] = []
    private(set) var cachePolicies:
        [GitLabResponseCachePolicy] = []
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []

    init(
        result:
            Result<
                GitLabMergeRequestApprovalSummary,
                GitLabSessionClientError
            >,
        eventSources:
            [GitLabAPIResponseSource] =
                [.network]
    ) {
        self.result = result
        self.eventSources = eventSources
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        paths.append(endpoint.pathComponents)
        return try result.get() as! Response
    }

    func loadResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>,
        cachePolicy: GitLabResponseCachePolicy,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<Response>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        paths.append(endpoint.pathComponents)
        cachePolicies.append(cachePolicy)
        refreshBehaviors.append(
            refreshBehavior
        )
        let summary = try result.get()
        for source in eventSources {
            await onResponse(
                GitLabAPIResponseEvent(
                    value: summary as! Response,
                    metadata:
                        GitLabResponseMetadata(),
                    source: source
                )
            )
        }
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        throw .api(.invalidResponse)
    }
}

private actor StubApprovalLoader:
    GitLabMergeRequestApprovalLoading
{
    private var results: [
        Result<
            GitLabMergeRequestApprovalAvailability,
            GitLabSessionClientError
        >
    ]
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []

    init(
        results: [
            Result<
                GitLabMergeRequestApprovalAvailability,
                GitLabSessionClientError
            >
        ]
    ) {
        self.results = results
    }

    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalAvailability
    {
        guard !results.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try results.removeFirst().get()
    }

    func loadMergeRequestApproval(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        refreshBehaviors.append(
            refreshBehavior
        )
        let value =
            try await loadMergeRequestApproval(
                at: route
            )
        await onResponse(
            GitLabAPIResponseEvent(
                value: value,
                metadata:
                    GitLabResponseMetadata(),
                source: .network
            )
        )
    }
}

private actor ApprovalEventRecorder {
    private(set) var values: [
        GitLabAPIResponseEvent<
            GitLabMergeRequestApprovalAvailability
        >
    ] = []

    func append(
        _ event:
            GitLabAPIResponseEvent<
                GitLabMergeRequestApprovalAvailability
            >
    ) {
        values.append(event)
    }
}
