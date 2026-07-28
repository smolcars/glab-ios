import Foundation
import Observation

nonisolated enum GitLabEmojiReactionMutationOperation:
    Equatable,
    Sendable
{
    case add(name: String)
    case remove(
        name: String,
        awardID: Int
    )

    var name: String {
        switch self {
        case let .add(name),
             let .remove(name, _):
            name
        }
    }
}

nonisolated struct GitLabEmojiReactionMutationFailure:
    Equatable,
    Sendable
{
    let operation:
        GitLabEmojiReactionMutationOperation
    let error: GitLabSessionClientError
    let certainty:
        GitLabMutationDeliveryCertainty
}

private typealias GitLabEmojiAwardsPageModel =
    GitLabPaginatedResourceModel<
        GitLabEmojiAward,
        Int
    >

private extension GitLabPaginatedResourceModel
where
    Item == GitLabEmojiAward,
    Identity == Int
{
    convenience init(
        awardable: GitLabEmojiAwardable,
        loader:
            any GitLabEmojiReactionLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabEmojiAward
                > in
                try await loader.loadReactionsPage(
                    for: awardable,
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
                                GitLabEmojiAward
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader.loadReactionsFirstPage(
                    for: awardable,
                    refreshBehavior:
                        refreshBehavior,
                    onPage: onPage
                )
            },
            identity: \.id,
            searchValues: { [$0.name] }
        )
    }
}

@MainActor
@Observable
final class GitLabEmojiReactionsModel {
    private enum PendingMutation:
        Equatable
    {
        case add
        case remove(awardID: Int)
    }

    let awardable: GitLabEmojiAwardable
    let currentUserID: Int
    let apiAccess: GitLabAPIAccess

    private(set) var mutationFailure:
        GitLabEmojiReactionMutationFailure?

    @ObservationIgnored
    private let mutator:
        any GitLabEmojiReactionMutating
    private let pageModel:
        GitLabEmojiAwardsPageModel
    private var pendingMutations:
        [String: PendingMutation] = [:]
    private var locallyRemovedAwardIDs:
        Set<Int> = []
    private var uncertainNames:
        Set<String> = []

    init(
        awardable: GitLabEmojiAwardable,
        currentUserID: Int,
        apiAccess: GitLabAPIAccess,
        loader:
            any GitLabEmojiReactionLoading,
        mutator:
            any GitLabEmojiReactionMutating
    ) {
        self.awardable = awardable
        self.currentUserID = currentUserID
        self.apiAccess = apiAccess
        self.mutator = mutator
        pageModel =
            GitLabEmojiAwardsPageModel(
                awardable: awardable,
                loader: loader
            )
    }

    var groups: [GitLabEmojiReactionGroup] {
        let pendingRemovalIDs = Set<Int>(
            pendingMutations.values
                .compactMap { mutation -> Int? in
                    guard
                        case let .remove(
                            awardID
                        ) = mutation
                    else {
                        return nil
                    }
                    return awardID
                }
        )
        let hiddenIDs =
            locallyRemovedAwardIDs
            .union(pendingRemovalIDs)
        var groups =
            GitLabEmojiReactionGroup.groups(
                awards:
                    pageModel.items.filter {
                        !hiddenIDs
                            .contains($0.id)
                    },
                currentUserID:
                    currentUserID
            )

        for (name, mutation)
            in pendingMutations
        {
            switch mutation {
            case .add:
                if
                    let index =
                        groups.firstIndex(
                            where: {
                                $0.name == name
                            }
                        )
                {
                    let group = groups[index]
                    groups[index] =
                        GitLabEmojiReactionGroup(
                            name: group.name,
                            display: group.display,
                            count: group.count + 1,
                            currentUserAwardIDs:
                                group
                                .currentUserAwardIDs,
                            isPending: true,
                            hasPendingCurrentUserAdd:
                                true
                        )
                } else {
                    groups.append(
                        GitLabEmojiReactionGroup(
                            name: name,
                            display:
                                GitLabEmojiPickerItem
                                .item(named: name)?
                                .display
                                ?? ":\(name):",
                            count: 1,
                            currentUserAwardIDs: [],
                            isPending: true,
                            hasPendingCurrentUserAdd:
                                true
                        )
                    )
                }
            case .remove:
                if
                    let index =
                        groups.firstIndex(
                            where: {
                                $0.name == name
                            }
                        )
                {
                    let group = groups[index]
                    groups[index] =
                        GitLabEmojiReactionGroup(
                            name: group.name,
                            display: group.display,
                            count: group.count,
                            currentUserAwardIDs:
                                group
                                .currentUserAwardIDs,
                            isPending: true,
                            hasPendingCurrentUserAdd:
                                false
                        )
                }
            }
        }
        return groups
    }

    var canMutate: Bool {
        apiAccess.canWrite
    }

    var hasLoaded: Bool {
        pageModel.hasLoaded
    }

    var isLoading: Bool {
        pageModel.isLoadingInitial
            || pageModel.isRefreshing
            || pageModel.isLoadingNextPage
    }

    var loadError:
        GitLabSessionClientError?
    {
        pageModel.loadError
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        if let failure =
            pageModel.authenticationFailure
        {
            return failure
        }
        guard
            mutationFailure?.error
                .requiresReauthentication
                == true
        else {
            return nil
        }
        return mutationFailure?.error
    }

    func isPending(
        name: String
    ) -> Bool {
        pendingMutations[name] != nil
    }

    func requiresRefresh(
        name: String
    ) -> Bool {
        uncertainNames.contains(name)
    }

    func loadIfNeeded() async {
        await pageModel.loadIfNeeded()
        await loadRemainingPages()
    }

    func refresh() async {
        await pageModel.refresh()
        await loadRemainingPages()
        guard
            pageModel.hasLoaded,
            !pageModel.didFailRefresh,
            !pageModel.didFailNextPage,
            pageModel.loadError == nil
        else {
            return
        }

        let serverIDs = Set(
            pageModel.items.map(\.id)
        )
        locallyRemovedAwardIDs
            .formIntersection(serverIDs)
        uncertainNames.removeAll()
        if
            mutationFailure?.certainty
                == .deliveryUnknown
        {
            mutationFailure = nil
        }
    }

    func toggleReaction(
        named name: String
    ) async {
        guard canMutate else {
            let error =
                GitLabSessionClientError
                    .insufficientAccess(
                        required: .write
                    )
            mutationFailure =
                GitLabEmojiReactionMutationFailure(
                    operation: .add(
                        name: name
                    ),
                    error: error,
                    certainty:
                        error
                        .mutationDeliveryCertainty
                )
            return
        }
        guard
            pendingMutations[name] == nil,
            !uncertainNames.contains(name)
        else {
            return
        }

        let currentUserAwardID =
            groups.first {
                $0.name == name
            }?
            .currentUserAwardIDs.first

        if let currentUserAwardID {
            await removeReaction(
                named: name,
                awardID:
                    currentUserAwardID
            )
        } else {
            await addReaction(named: name)
        }
    }

    func dismissMutationFailure() {
        guard
            mutationFailure?.certainty
                != .deliveryUnknown
        else {
            return
        }
        mutationFailure = nil
    }

    private func addReaction(
        named name: String
    ) async {
        pendingMutations[name] = .add
        mutationFailure = nil
        defer {
            pendingMutations[name] = nil
        }

        do {
            let award =
                try await mutator.addReaction(
                    named: name,
                    to: awardable
                )
            pageModel.reconcileItem(
                award,
                countAdjustmentIfInserted: 1,
                keepsAtEndUntilLoaded: true
            )
        } catch {
            recordFailure(
                operation: .add(name: name),
                error: error
            )
        }
    }

    private func removeReaction(
        named name: String,
        awardID: Int
    ) async {
        pendingMutations[name] =
            .remove(awardID: awardID)
        mutationFailure = nil
        defer {
            pendingMutations[name] = nil
        }

        do {
            try await mutator.removeReaction(
                awardID: awardID,
                from: awardable
            )
            locallyRemovedAwardIDs
                .insert(awardID)
        } catch {
            recordFailure(
                operation: .remove(
                    name: name,
                    awardID: awardID
                ),
                error: error
            )
        }
    }

    private func recordFailure(
        operation:
            GitLabEmojiReactionMutationOperation,
        error: GitLabSessionClientError
    ) {
        let certainty =
            error.mutationDeliveryCertainty
        if certainty == .deliveryUnknown {
            uncertainNames.insert(
                operation.name
            )
        }
        mutationFailure =
            GitLabEmojiReactionMutationFailure(
                operation: operation,
                error: error,
                certainty: certainty
            )
    }

    private func loadRemainingPages() async {
        while
            let nextPageURL =
                pageModel.nextPageURL,
            !pageModel.didFailRefresh,
            !pageModel.didFailNextPage
        {
            await pageModel.retryNextPage()
            guard
                pageModel.nextPageURL
                    != nextPageURL
            else {
                break
            }
        }
    }
}
