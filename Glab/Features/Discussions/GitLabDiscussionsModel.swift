import Foundation

typealias GitLabDiscussionsModel =
    GitLabPaginatedResourceModel<
        GitLabDiscussion,
        String
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabDiscussion,
    Identity == String
{
    convenience init(
        resource: GitLabDiscussionResource,
        loader: any GitLabDiscussionLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabDiscussion
                > in
                try await loader.loadDiscussionsPage(
                    for: resource,
                    after: nextPageURL
                )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabDiscussion
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadDiscussionsFirstPage(
                        for: resource,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: \.id,
            searchValues: {
                discussion in
                discussion.notes.flatMap {
                    [
                        $0.body,
                        $0.author.displayName,
                        $0.author.username,
                    ]
                }
            }
        )
    }

    var discussions: [GitLabDiscussion] {
        items
    }

    func reconcileCreatedDiscussion(
        _ discussion: GitLabDiscussion
    ) {
        reconcileItem(
            discussion,
            countAdjustmentIfInserted: 1,
            keepsAtEndUntilLoaded: true
        )
    }

    @discardableResult
    func reconcileAuthoritativeDiscussion(
        _ discussion: GitLabDiscussion
    ) -> Bool {
        reconcileItemIfPresent(
            discussion
        )
    }

    @discardableResult
    func reconcileCreatedReply(
        _ note: GitLabDiscussionNote,
        discussionID: String
    ) -> Bool {
        guard
            let discussion = discussions
                .first(
                    where: {
                        $0.id == discussionID
                    }
                )
        else {
            return false
        }

        reconcileItem(
            discussion.reconciling(note)
        )
        return true
    }

    func reconcile(
        _ result:
            GitLabDiscussionComposerResult
    ) {
        switch result {
        case let .discussion(discussion):
            reconcileCreatedDiscussion(
                discussion
            )
        case let .reply(
            note,
            discussionID
        ):
            reconcileCreatedReply(
                note,
                discussionID:
                    discussionID
            )
        }
    }
}
