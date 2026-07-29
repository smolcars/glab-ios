import Foundation
import Observation

typealias GitLabPipelinePollWaiter =
    @Sendable () async throws -> Void

@MainActor
private final class GitLabPipelineAccountScope {
    private let isCurrent:
        @MainActor () -> Bool

    init(
        isCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.isCurrent = isCurrent
    }

    func check() -> Bool {
        isCurrent()
    }
}

@MainActor
@Observable
final class GitLabMergeRequestPipelinesModel {
    let accountID: GitLabAccountID
    let route: GitLabMergeRequestRoute
    let pipelines:
        GitLabPaginatedResourceModel<
            GitLabPipeline,
            Int
        >

    @ObservationIgnored
    private let accountScope:
        GitLabPipelineAccountScope
    @ObservationIgnored
    private let pollWaiter:
        GitLabPipelinePollWaiter

    init(
        accountID: GitLabAccountID,
        route: GitLabMergeRequestRoute,
        loader: any GitLabPipelineLoading,
        pollWaiter:
            @escaping GitLabPipelinePollWaiter = {
                try await Task.sleep(
                    for: .seconds(15)
                )
            },
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        let accountScope =
            GitLabPipelineAccountScope(
                isCurrent: isAccountCurrent
            )
        self.accountID = accountID
        self.route = route
        self.accountScope = accountScope
        self.pollWaiter = pollWaiter
        pipelines = Self.makePipelinesModel(
            route: route,
            loader: loader,
            accountScope: accountScope
        )
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        pipelines.authenticationFailure
    }

    var hasActivelyChangingPipelines: Bool {
        pipelines.items.contains {
            $0.status.isActivelyChanging
        }
    }

    func loadIfNeeded() async {
        guard accountScope.check() else {
            return
        }
        await pipelines.loadIfNeeded()
    }

    func refresh() async {
        guard accountScope.check() else {
            return
        }
        await pipelines.refresh()
    }

    func loadNextPageIfNeeded(
        after pipeline: GitLabPipeline
    ) async {
        guard accountScope.check() else {
            return
        }
        await pipelines.loadNextPageIfNeeded(
            after: pipeline
        )
    }

    func retryNextPage() async {
        guard accountScope.check() else {
            return
        }
        await pipelines.retryNextPage()
    }

    func runVisible(
        isSceneActive: Bool
    ) async {
        guard
            isSceneActive,
            accountScope.check()
        else {
            return
        }

        await pipelines.loadIfNeeded()

        while shouldPoll(
            isSceneActive: isSceneActive
        ) {
            do {
                try await pollWaiter()
                try Task.checkCancellation()
            } catch {
                return
            }

            guard shouldPoll(
                isSceneActive: isSceneActive
            ) else {
                return
            }

            await pipelines.refresh()
        }
    }

    private func shouldPoll(
        isSceneActive: Bool
    ) -> Bool {
        isSceneActive
            && !Task.isCancelled
            && accountScope.check()
            && authenticationFailure == nil
            && hasActivelyChangingPipelines
    }

    private static func makePipelinesModel(
        route: GitLabMergeRequestRoute,
        loader: any GitLabPipelineLoading,
        accountScope:
            GitLabPipelineAccountScope
    ) -> GitLabPaginatedResourceModel<
        GitLabPipeline,
        Int
    > {
        GitLabPaginatedResourceModel(
            loadPage: {
                nextPageURL async throws(
                    GitLabSessionClientError
                ) in
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }

                let page =
                    try await loader
                    .loadMergeRequestPipelinesPage(
                        at: route,
                        after: nextPageURL
                    )

                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
                return page
            },
            loadFirstPage: {
                refreshBehavior,
                onPage async throws(
                    GitLabSessionClientError
                ) in
                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }

                try await loader
                    .loadMergeRequestPipelinesFirstPage(
                        at: route,
                        refreshBehavior:
                            refreshBehavior
                    ) { event in
                        guard
                            await accountScope
                                .check()
                        else {
                            return
                        }
                        await onPage(event)
                    }

                guard
                    await accountScope.check()
                else {
                    throw .api(.cancelled)
                }
            },
            firstPageRefreshMode:
                .retainLoadedTail,
            identity: \.id,
            searchValues: {
                [
                    $0.name ?? "",
                    $0.ref,
                    $0.sha,
                    String($0.iid ?? $0.id),
                    $0.status.title,
                ]
            }
        )
    }
}
