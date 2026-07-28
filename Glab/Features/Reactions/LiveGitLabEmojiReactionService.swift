import Foundation

nonisolated protocol GitLabEmojiReactionLoading:
    Sendable
{
    func loadReactionsPage(
        for awardable: GitLabEmojiAwardable,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabEmojiAward
        >

    func loadReactionsFirstPage(
        for awardable: GitLabEmojiAwardable,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabEmojiAward
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError)
}

extension GitLabEmojiReactionLoading {
    func loadReactionsFirstPage(
        for awardable: GitLabEmojiAwardable,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabEmojiAward
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        let page = try await loadReactionsPage(
            for: awardable,
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

nonisolated protocol GitLabEmojiReactionMutating:
    Sendable
{
    func addReaction(
        named name: String,
        to awardable: GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError)
        -> GitLabEmojiAward

    func removeReaction(
        awardID: Int,
        from awardable:
            GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError)
}

nonisolated struct LiveGitLabEmojiReactionService:
    GitLabEmojiReactionLoading,
    GitLabEmojiReactionMutating,
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
    func loadReactionsPage(
        for awardable: GitLabEmojiAwardable,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabResourcePage<
            GitLabEmojiAward
        >
    {
        let request:
            GitLabAPIPageRequest<
                [GitLabEmojiAward]
            > =
                if let nextPageURL {
                    .next(nextPageURL)
                } else {
                    .initial(
                        GitLabEmojiReactionEndpoints
                            .reactions(
                                for: awardable
                            )
                    )
                }
        let response = try await client.sendPage(
            request
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
    func loadReactionsFirstPage(
        for awardable: GitLabEmojiAwardable,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        onPage:
            @escaping @Sendable (
                GitLabResourcePageEvent<
                    GitLabEmojiAward
                >
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadPage(
            .initial(
                GitLabEmojiReactionEndpoints
                    .reactions(for: awardable)
            ),
            cachePolicy: .reactions,
            refreshBehavior:
                refreshBehavior
        ) {
            await onPage(
                GitLabResourcePageEvent(
                    apiResponse: $0
                )
            )
        }
    }

    @concurrent
    func addReaction(
        named name: String,
        to awardable: GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError)
        -> GitLabEmojiAward
    {
        let award = try await client.send(
            GitLabEmojiReactionEndpoints.add(
                name: name,
                to: awardable
            )
        )
        await invalidateReactions(
            for: awardable
        )
        return award
    }

    @concurrent
    func removeReaction(
        awardID: Int,
        from awardable:
            GitLabEmojiAwardable
    ) async throws(GitLabSessionClientError) {
        let _: GitLabEmptyResponse =
            try await client.send(
                GitLabEmojiReactionEndpoints
                    .remove(
                        awardID: awardID,
                        from: awardable
                    )
            )
        await invalidateReactions(
            for: awardable
        )
    }

    private func invalidateReactions(
        for awardable: GitLabEmojiAwardable
    ) async {
        await client.invalidateCachedResponse(
            GitLabEmojiReactionEndpoints
                .reactions(for: awardable)
        )
    }
}
