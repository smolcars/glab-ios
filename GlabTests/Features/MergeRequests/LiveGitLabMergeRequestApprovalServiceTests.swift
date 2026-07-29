import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab merge request approval service")
struct LiveGitLabMergeRequestApprovalServiceTests {
    @Test("Loads and cache-revalidates detailed approval rules")
    func loadsDetailedRules() async throws {
        let client =
            RecordingApprovalManagementClient(
                eventSources: [
                    .cache(.stale),
                    .network,
                ]
            )
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )
        let recorder = ApprovalDetailsEventRecorder()

        let direct =
            try await service
                .loadApprovalDetails(at: route)
        try await service.loadApprovalDetails(
            at: route,
            refreshBehavior: .ifStale
        ) {
            await recorder.append($0)
        }

        #expect(
            direct
                == .available(
                    client.details
                )
        )
        #expect(
            await recorder.events.map(\.value)
                == [
                    .available(client.details),
                    .available(client.details),
                ]
        )
        #expect(
            await recorder.events.map(\.source)
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
    }

    @Test(
        "Maps unavailable detailed approval capability",
        arguments: [
            GitLabSessionClientError.api(
                .forbidden
            ),
            .api(.notFound),
        ]
    )
    func mapsUnavailableDetails(
        error: GitLabSessionClientError
    ) async throws {
        let client =
            RecordingApprovalManagementClient(
                errors: [
                    detailsKey: error
                ]
            )
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )
        let recorder = ApprovalDetailsEventRecorder()

        let direct =
            try await service
                .loadApprovalDetails(at: route)
        try await service.loadApprovalDetails(
            at: route,
            refreshBehavior: .always
        ) {
            await recorder.append($0)
        }

        #expect(direct == .unavailable)
        #expect(
            await recorder.events.map(\.value)
                == [.unavailable]
        )
        #expect(
            await recorder.events.map(\.source)
                == [.network]
        )
    }

    @Test(
        "Preserves actionable detailed approval failures",
        arguments: [
            GitLabSessionClientError.api(
                .unauthenticated
            ),
            .api(.server(statusCode: 503)),
            .api(.decoding),
        ]
    )
    func preservesDetailsFailure(
        error: GitLabSessionClientError
    ) async {
        let service =
            LiveGitLabMergeRequestApprovalService(
                client:
                    RecordingApprovalManagementClient(
                        errors: [
                            detailsKey: error
                        ]
                    )
            )

        await #expect(throws: error) {
            try await service
                .loadApprovalDetails(at: route)
        }
    }

    @Test("Loads uncached mutation preflight resources")
    func loadsPreflightResources() async throws {
        let client =
            RecordingApprovalManagementClient()
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )

        let mergeRequest =
            try await service
                .loadLatestMergeRequest(at: route)
        let summary =
            try await service
                .loadApprovalSummary(at: route)
        let rule =
            try await service.loadApprovalRule(
                at: route,
                ruleID: 41
            )

        #expect(mergeRequest.id == client.mergeRequest.id)
        #expect(summary == client.summary)
        #expect(rule == client.rule)
        #expect(
            await client.sentKeys
                == [
                    detailKey,
                    approvalsKey,
                    ruleKey,
                ]
        )
    }

    @Test("Paginates project members with server search")
    func loadsMembers() async throws {
        let client =
            RecordingApprovalManagementClient()
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )

        let first = try await service.loadMembersPage(
            projectID: 42,
            search: "Ada Lovelace",
            after: nil
        )
        let second = try await service.loadMembersPage(
            projectID: 42,
            search: nil,
            after: first.nextPageURL
        )

        #expect(
            first.items.map(\.id) == [7]
        )
        #expect(first.nextPageURL != nil)
        #expect(
            second.items.map(\.id) == [7]
        )
        #expect(
            await client.memberQueries.first
                == [
                    "per_page": "20",
                    "query": "Ada Lovelace",
                ]
        )
        #expect(await client.nextPageCount == 1)
    }

    @Test("Approves once and invalidates only approval reads")
    func approvesAndInvalidates() async throws {
        let client =
            RecordingApprovalManagementClient()
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )

        let response = try await service.approve(
            at: route,
            sha: "fresh-head-sha"
        )

        #expect(response == client.summary)
        #expect(
            await client.sentKeys
                == [approveKey]
        )
        #expect(
            await client.invalidatedKeys
                == approvalInvalidationKeys
        )
    }

    @Test("Unapproves once and invalidates only approval reads")
    func unapprovesAndInvalidates() async throws {
        let client =
            RecordingApprovalManagementClient()
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )

        let response =
            try await service.unapprove(
                at: route
            )

        #expect(response == client.summary)
        #expect(
            await client.sentKeys
                == [unapproveKey]
        )
        #expect(
            await client.invalidatedKeys
                == approvalInvalidationKeys
        )
    }

    @Test("Updates a rule and invalidates the exact rule too")
    func updatesRuleAndInvalidates() async throws {
        let client =
            RecordingApprovalManagementClient()
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )
        let replacement =
            GitLabMergeRequestApprovalRuleReplacement(
                name: "Security",
                approvalsRequired: 2,
                userIDs: [7, 8],
                groupIDs: [19]
            )

        let response =
            try await service.updateApprovalRule(
                at: route,
                ruleID: 41,
                replacement: replacement
            )

        #expect(response == client.rule)
        #expect(
            await client.sentKeys
                == [updateRuleKey]
        )
        #expect(
            await client.invalidatedKeys
                == approvalInvalidationKeys
                + [ruleKey]
        )
    }

    @Test(
        "Invalidates uncertain mutations without invalidating rejected ones",
        arguments: [
            (
                GitLabSessionClientError.api(
                    .server(statusCode: 503)
                ),
                true
            ),
            (
                .api(.forbidden),
                false
            ),
        ]
    )
    func invalidatesByDeliveryCertainty(
        error: GitLabSessionClientError,
        shouldInvalidate: Bool
    ) async {
        let client =
            RecordingApprovalManagementClient(
                errors: [
                    approveKey: error
                ]
            )
        let service =
            LiveGitLabMergeRequestApprovalService(
                client: client
            )

        await #expect(throws: error) {
            try await service.approve(
                at: route,
                sha: "fresh-head-sha"
            )
        }

        #expect(
            await client.invalidatedKeys
                == (
                    shouldInvalidate
                        ? approvalInvalidationKeys
                        : []
                )
        )
    }

    private var route:
        GitLabMergeRequestRoute
    {
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 7
        )
    }

    private var routePath: String {
        "projects/42/merge_requests/7"
    }

    private var detailKey: String {
        "GET:\(routePath)"
    }

    private var approvalsKey: String {
        "GET:\(routePath)/approvals"
    }

    private var detailsKey: String {
        "GET:\(routePath)/approval_state"
    }

    private var ruleKey: String {
        "GET:\(routePath)/approval_rules/41"
    }

    private var approveKey: String {
        "POST:\(routePath)/approve"
    }

    private var unapproveKey: String {
        "POST:\(routePath)/unapprove"
    }

    private var updateRuleKey: String {
        "PUT:\(routePath)/approval_rules/41"
    }

    private var approvalInvalidationKeys:
        [String]
    {
        [
            detailKey,
            approvalsKey,
            detailsKey,
        ]
    }
}

private actor ApprovalDetailsEventRecorder {
    private(set) var events: [
        GitLabAPIResponseEvent<
            GitLabMergeRequestApprovalDetailsAvailability
        >
    ] = []

    func append(
        _ event:
            GitLabAPIResponseEvent<
                GitLabMergeRequestApprovalDetailsAvailability
            >
    ) {
        events.append(event)
    }
}

private actor RecordingApprovalManagementClient:
    GitLabPaginatedSessionRequestSending
{
    nonisolated let mergeRequest =
        makeTestMergeRequest(
            sha: "fresh-head-sha",
            diffRefs:
                GitLabMergeRequestDiffRefs(
                    baseSHA: "base",
                    startSHA: "start",
                    headSHA: "fresh-head-sha"
                )
        )
    nonisolated let summary =
        GitLabMergeRequestApprovalSummary(
            approved: false,
            approvalsRequired: 2,
            approvalsLeft: 1,
            approvedBy: []
        )
    nonisolated let details =
        GitLabMergeRequestApprovalDetails(
            approvalRulesOverwritten: false,
            rules: []
        )
    nonisolated let rule =
        GitLabMergeRequestApprovalRule(
            id: 41,
            name: "Security",
            ruleType: "regular",
            eligibleApprovers: [],
            approvalsRequired: 2,
            users: [],
            groups: [],
            containsHiddenGroups: false,
            approvedBy: [],
            approved: false,
            overridden: false
        )

    private let errors:
        [String: GitLabSessionClientError]
    private let eventSources:
        [GitLabAPIResponseSource]
    private(set) var sentKeys: [String] = []
    private(set) var invalidatedKeys: [String] = []
    private(set) var cachePolicies:
        [GitLabResponseCachePolicy] = []
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []
    private(set) var memberQueries:
        [[String: String]] = []
    private(set) var nextPageCount = 0

    init(
        errors:
            [String: GitLabSessionClientError] = [:],
        eventSources:
            [GitLabAPIResponseSource] = [.network]
    ) {
        self.errors = errors
        self.eventSources = eventSources
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        let key = Self.key(endpoint)
        sentKeys.append(key)
        if let error = errors[key] {
            throw error
        }

        let value: any Sendable
        switch (
            endpoint.method,
            endpoint.pathComponents.last
        ) {
        case (.get, "7"):
            value = mergeRequest
        case (.get, "approvals"),
             (.post, "approve"),
             (.post, "unapprove"):
            value = summary
        case (.get, "approval_state"):
            value = details
        case (.get, "41"),
             (.put, "41"):
            value = rule
        default:
            throw .api(.invalidResponse)
        }
        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }
        return response
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
        cachePolicies.append(cachePolicy)
        refreshBehaviors.append(
            refreshBehavior
        )
        let value: Response =
            try await send(endpoint)
        for source in eventSources {
            await onResponse(
                GitLabAPIResponseEvent(
                    value: value,
                    metadata:
                        GitLabResponseMetadata(),
                    source: source
                )
            )
        }
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async {
        invalidatedKeys.append(
            Self.key(endpoint)
        )
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        let member =
            GitLabProjectMember(
                id: 7,
                username: "ada",
                name: "Ada Lovelace",
                state: "active",
                avatarURL: nil,
                webURL: nil,
                accessLevel: 30
            )
        let value = [member]
        let metadata:
            GitLabResponseMetadata

        switch page {
        case let .initial(endpoint):
            sentKeys.append(
                Self.key(endpoint)
            )
            memberQueries.append(
                Dictionary(
                    uniqueKeysWithValues:
                        endpoint.queryItems
                        .compactMap {
                            item in
                            item.value.map {
                                (
                                    item.name,
                                    $0
                                )
                            }
                        }
                )
            )
            metadata =
                GitLabResponseMetadata(
                    nextPageURL:
                        URL(
                            string:
                                "https://gitlab.example.com/api/v4/projects/42/members/all?page=2"
                        )
                )
        case .next:
            nextPageCount += 1
            metadata =
                GitLabResponseMetadata()
        }

        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }
        return GitLabAPIResponse(
            value: response,
            metadata: metadata
        )
    }

    private static func key<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) -> String {
        endpoint.method.rawValue
            + ":"
            + endpoint.pathComponents
                .joined(separator: "/")
    }
}
