import Foundation

nonisolated protocol
    GitLabMergeRequestApprovalServing:
    Sendable
{
    func loadLatestMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest

    func loadApprovalSummary(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary

    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalDetailsAvailability

    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalDetailsAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule

    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >

    func approve(
        at route: GitLabMergeRequestRoute,
        sha: String
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary

    func unapprove(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary

    func updateApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int,
        replacement:
            GitLabMergeRequestApprovalRuleReplacement
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
}

nonisolated struct
    LiveGitLabMergeRequestApprovalService:
    GitLabMergeRequestApprovalServing,
    Sendable
{
    private let client:
        any GitLabPaginatedSessionRequestSending

    init(
        client:
            any GitLabPaginatedSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadLatestMergeRequest(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        try await client.send(
            GitLabMergeRequestEndpoints
                .mergeRequest(at: route)
        )
    }

    @concurrent
    func loadApprovalSummary(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        try await client.send(
            GitLabMergeRequestEndpoints
                .approvals(at: route)
        )
    }

    @concurrent
    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalDetailsAvailability
    {
        do {
            return .available(
                try await client.send(
                    GitLabMergeRequestEndpoints
                        .approvalDetails(
                            at: route
                        )
                )
            )
        } catch .api(.forbidden),
                .api(.notFound)
        {
            return .unavailable
        } catch {
            throw error
        }
    }

    @concurrent
    func loadApprovalDetails(
        at route: GitLabMergeRequestRoute,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<
                    GitLabMergeRequestApprovalDetailsAvailability
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        do {
            try await client.loadResponse(
                GitLabMergeRequestEndpoints
                    .approvalDetails(at: route),
                cachePolicy:
                    .mergeRequestReadiness,
                refreshBehavior:
                    refreshBehavior
            ) { event in
                await onResponse(
                    GitLabAPIResponseEvent(
                        value:
                            .available(
                                event.value
                            ),
                        metadata:
                            event.metadata,
                        source: event.source,
                        cacheStoredAt:
                            event.cacheStoredAt
                    )
                )
            }
        } catch .api(.forbidden),
                .api(.notFound)
        {
            await onResponse(
                GitLabAPIResponseEvent(
                    value: .unavailable,
                    metadata:
                        GitLabResponseMetadata(),
                    source: .network
                )
            )
        } catch {
            throw error
        }
    }

    @concurrent
    func loadApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
    {
        try await client.send(
            GitLabMergeRequestEndpoints
                .approvalRule(
                    at: route,
                    ruleID: ruleID
                )
        )
    }

    @concurrent
    func loadMembersPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabProjectMember
        >
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabProjectMember]
            > =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(
                        GitLabIssueCreationEndpoints
                            .members(
                                projectID:
                                    projectID,
                                search: search
                            )
                    )
                }
        let response = try await client
            .sendPage(request)
        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    @concurrent
    func approve(
        at route: GitLabMergeRequestRoute,
        sha: String
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        let endpoint:
            GitLabAPIRequest<
                GitLabMergeRequestApprovalSummary
            >
        do {
            endpoint =
                try GitLabMergeRequestEndpoints
                    .approve(
                        at: route,
                        sha: sha
                    )
        } catch {
            throw .api(.invalidResponse)
        }

        return try await sendMutation(
            endpoint,
            route: route
        )
    }

    @concurrent
    func unapprove(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalSummary
    {
        try await sendMutation(
            GitLabMergeRequestEndpoints
                .unapprove(at: route),
            route: route
        )
    }

    @concurrent
    func updateApprovalRule(
        at route: GitLabMergeRequestRoute,
        ruleID: Int,
        replacement:
            GitLabMergeRequestApprovalRuleReplacement
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestApprovalRule
    {
        let endpoint:
            GitLabAPIRequest<
                GitLabMergeRequestApprovalRule
            >
        do {
            endpoint =
                try GitLabMergeRequestEndpoints
                    .updateApprovalRule(
                        at: route,
                        ruleID: ruleID,
                        replacement:
                            replacement
                    )
        } catch {
            throw .api(.invalidResponse)
        }

        return try await sendMutation(
            endpoint,
            route: route,
            ruleID: ruleID
        )
    }
}

private nonisolated extension
    LiveGitLabMergeRequestApprovalService
{
    @concurrent
    func sendMutation<Response>(
        _ endpoint:
            GitLabAPIRequest<Response>,
        route:
            GitLabMergeRequestRoute,
        ruleID: Int? = nil
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        do {
            let response =
                try await client.send(
                    endpoint
                )
            await invalidateApprovalReads(
                at: route,
                ruleID: ruleID
            )
            return response
        } catch {
            if
                error.mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                await invalidateApprovalReads(
                    at: route,
                    ruleID: ruleID
                )
            }
            throw error
        }
    }

    @concurrent
    func invalidateApprovalReads(
        at route:
            GitLabMergeRequestRoute,
        ruleID: Int?
    ) async {
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .mergeRequest(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .approvals(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .approvalDetails(at: route)
        )
        if let ruleID {
            await client
                .invalidateCachedResponse(
                    GitLabMergeRequestEndpoints
                        .approvalRule(
                            at: route,
                            ruleID: ruleID
                        )
                )
        }
    }
}
