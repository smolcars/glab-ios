import Foundation

nonisolated enum GitLabDiscussionMutationError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible
{
    case encoding
    case invalidDiffResource
    case latestDiffVersionUnavailable
    case staleDiffVersion
    case request(GitLabSessionClientError)

    var description: String {
        switch self {
        case .encoding:
            "Glab could not prepare this comment."
        case .invalidDiffResource:
            "A line comment requires a merge request."
        case .latestDiffVersionUnavailable:
            "GitLab did not return a current diff version. "
                + "Refresh the merge request and try again."
        case .staleDiffVersion:
            "This diff changed before the comment was sent. "
                + "Refresh the changed files and review the line again."
        case let .request(error):
            error.description
        }
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol GitLabDiscussionLoading:
    Sendable
{
    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>

    func loadDiscussionsFirstPage(
        for resource: GitLabDiscussionResource,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

nonisolated protocol GitLabDiscussionMutating:
    Sendable
{
    func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion

    func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion

    func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionNote
}

extension GitLabDiscussionLoading {
    func loadDiscussionsFirstPage(
        for resource: GitLabDiscussionResource,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadDiscussionsPage(
            for: resource,
            after: nil
        )
        await onPage(
            GitLabResourcePageEvent(
                page: page,
                source: .network
            )
        )
    }
}

nonisolated struct LiveGitLabDiscussionService:
    GitLabDiscussionLoading,
    GitLabDiscussionMutating,
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
    func loadDiscussionsPage(
        for resource: GitLabDiscussionResource,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<GitLabDiscussion>
    {
        let pageRequest:
            GitLabAPIPageRequest<
                [GitLabDiscussion]
            > =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(
                        GitLabDiscussionEndpoints
                            .discussions(
                                for: resource
                            )
                    )
                }
        let response = try await client.sendPage(
            pageRequest
        )

        return GitLabResourcePage(
            items: response.value,
            nextPageURL:
                response.metadata.nextPageURL,
            totalCount:
                response.metadata.totalCount
        )
    }

    @concurrent
    func loadDiscussionsFirstPage(
        for resource: GitLabDiscussionResource,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabDiscussionEndpoints
                    .discussions(for: resource)
            ),
            cachePolicy: .discussions,
            refreshBehavior: refreshBehavior
        ) {
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: $0
                )
            )
        }
    }

    @concurrent
    func createDiscussion(
        for resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        let endpoint:
            GitLabAPIRequest<GitLabDiscussion>
        do {
            endpoint =
                try GitLabDiscussionEndpoints
                    .createDiscussion(
                    for: resource,
                    body: body
                )
        } catch {
            throw .encoding
        }

        let discussion: GitLabDiscussion
        do {
            discussion = try await client.send(
                endpoint
            )
        } catch {
            throw .request(error)
        }
        await invalidateDiscussions(
            for: resource
        )
        return discussion
    }

    @concurrent
    func createDiffDiscussion(
        for route: GitLabMergeRequestRoute,
        body: GitLabDiscussionCommentBody,
        position: GitLabDiffLinePosition
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussion
    {
        let versions:
            [GitLabMergeRequestDiffVersion]
        do {
            versions = try await client.send(
                GitLabMergeRequestEndpoints
                    .diffVersions(at: route)
            )
        } catch {
            throw .request(error)
        }

        guard !Task.isCancelled else {
            throw .request(.api(.cancelled))
        }
        guard
            let latestVersion =
                versions.first?.identity
        else {
            throw .latestDiffVersionUnavailable
        }
        guard latestVersion == position.version else {
            throw .staleDiffVersion
        }

        let endpoint:
            GitLabAPIRequest<GitLabDiscussion>
        do {
            endpoint =
                try GitLabDiscussionEndpoints
                    .createDiffDiscussion(
                        for: route,
                        body: body,
                        position: position
                    )
        } catch {
            throw .encoding
        }

        let discussion: GitLabDiscussion
        do {
            discussion = try await client.send(
                endpoint
            )
        } catch {
            throw .request(error)
        }
        await invalidateDiscussions(
            for: .mergeRequest(route)
        )
        return discussion
    }

    @concurrent
    func reply(
        to discussionID: String,
        in resource: GitLabDiscussionResource,
        body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionNote
    {
        let endpoint:
            GitLabAPIRequest<GitLabDiscussionNote>
        do {
            endpoint =
                try GitLabDiscussionEndpoints
                    .reply(
                        to: discussionID,
                        in: resource,
                        body: body
                    )
        } catch {
            throw .encoding
        }

        let note: GitLabDiscussionNote
        do {
            note = try await client.send(
                endpoint
            )
        } catch {
            throw .request(error)
        }
        await invalidateDiscussions(
            for: resource
        )
        return note
    }

    private func invalidateDiscussions(
        for resource: GitLabDiscussionResource
    ) async {
        await client.invalidateCachedResponse(
            GitLabDiscussionEndpoints
                .discussions(for: resource)
        )
    }
}
