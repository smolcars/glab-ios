import Foundation

nonisolated struct
    GitLabMergeRequestMergePreflight:
    Equatable,
    Sendable
{
    let mergeRequest: GitLabMergeRequest
    let approvalSummary:
        GitLabMergeRequestApprovalSummary
}

nonisolated protocol
    GitLabMergeRequestMergeServing:
    Sendable
{
    func preflight(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestMergePreflight

    func merge(
        at route: GitLabMergeRequestRoute,
        sha: String,
        action:
            GitLabMergeRequestMergeAction
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
}

nonisolated struct
    LiveGitLabMergeRequestMergeService:
    GitLabMergeRequestMergeServing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending
    private let readInvalidator:
        GitLabResourceReadInvalidator

    init(
        client:
            any GitLabSessionRequestSending
    ) {
        self.client = client
        readInvalidator =
            GitLabResourceReadInvalidator(
                client: client
            )
    }

    @concurrent
    func preflight(
        at route: GitLabMergeRequestRoute
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequestMergePreflight
    {
        let mergeRequest =
            try await client.send(
                GitLabMergeRequestEndpoints
                    .mergeRequest(at: route)
            )
        guard mergeRequest.route == route else {
            throw .api(.invalidResponse)
        }
        let summary =
            try await client.send(
                GitLabMergeRequestEndpoints
                    .approvals(at: route)
            )
        return GitLabMergeRequestMergePreflight(
            mergeRequest: mergeRequest,
            approvalSummary: summary
        )
    }

    @concurrent
    func merge(
        at route: GitLabMergeRequestRoute,
        sha: String,
        action:
            GitLabMergeRequestMergeAction
    ) async throws(GitLabSessionClientError)
        -> GitLabMergeRequest
    {
        let endpoint:
            GitLabAPIRequest<
                GitLabMergeRequest
            >
        do {
            endpoint =
                try GitLabMergeRequestEndpoints
                    .merge(
                        at: route,
                        sha: sha,
                        autoMerge:
                            action
                                == .autoMerge
                    )
        } catch {
            throw .api(.invalidResponse)
        }

        let response: GitLabMergeRequest
        do {
            response =
                try await client.send(
                    endpoint
                )
        } catch {
            if Self.shouldInvalidate(
                after: error
            ) {
                await invalidateMergeReads(
                    at: route
                )
            }
            throw error
        }
        guard response.route == route else {
            await invalidateMergeReads(
                at: route
            )
            throw .api(.invalidResponse)
        }
        await invalidateMergeReads(
            at: route
        )
        return response
    }
}

private nonisolated extension
    LiveGitLabMergeRequestMergeService
{
    static func shouldInvalidate(
        after error:
            GitLabSessionClientError
    ) -> Bool {
        if
            error
                == .api(
                    .validation(
                        statusCode: 409
                    )
                )
        {
            return true
        }
        if
            error
                == .api(
                    .http(statusCode: 405)
                )
        {
            return false
        }
        return error
            .mutationDeliveryCertainty
            == .deliveryUnknown
    }

    @concurrent
    func invalidateMergeReads(
        at route: GitLabMergeRequestRoute
    ) async {
        await readInvalidator
            .invalidateMergeRequestReads(
                route: route
            )
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .approvals(at: route)
        )
        await client.invalidateCachedResponse(
            GitLabMergeRequestEndpoints
                .approvalDetails(at: route)
        )
        if
            let pipelineHistory =
                GitLabPipelineEndpoints
                .mergeRequestPipelines(
                    at: route
                )
        {
            await client
                .invalidateCachedResponse(
                    pipelineHistory
                )
        }
    }
}
