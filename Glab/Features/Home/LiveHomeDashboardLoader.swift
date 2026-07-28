import Foundation

nonisolated struct LiveHomeDashboardLoader:
    HomeDashboardLoading,
    Sendable
{
    private let client: any GitLabSessionRequestSending

    init(client: any GitLabSessionRequestSending) {
        self.client = client
    }

    @concurrent
    func load(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onUpdate:
            @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
    ) async throws(HomeDashboardLoadingError) {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await loadCurrentUser(
                    refreshBehavior: refreshBehavior,
                    onUpdate: onUpdate
                )
            }
            group.addTask {
                await loadWorkItems(
                    HomeDashboardEndpoints.assignedIssues,
                    section: .assignedIssues,
                    refreshBehavior: refreshBehavior,
                    transform: { $0.workItem },
                    onUpdate: onUpdate
                )
            }
            group.addTask {
                await loadWorkItems(
                    HomeDashboardEndpoints.assignedMergeRequests,
                    section: .assignedMergeRequests,
                    refreshBehavior: refreshBehavior,
                    transform: { $0.workItem },
                    onUpdate: onUpdate
                )
            }
            group.addTask {
                await loadWorkItems(
                    HomeDashboardEndpoints.reviewRequests,
                    section: .reviewRequests,
                    refreshBehavior: refreshBehavior,
                    transform: { $0.workItem },
                    onUpdate: onUpdate
                )
            }
            group.addTask {
                await loadWorkItems(
                    HomeDashboardEndpoints.recentProjects,
                    section: .recentProjects,
                    refreshBehavior: refreshBehavior,
                    transform: { $0.workItem },
                    onUpdate: onUpdate
                )
            }
            group.addTask {
                await loadWorkItems(
                    HomeDashboardEndpoints.starredProjects,
                    section: .starredProjects,
                    refreshBehavior: refreshBehavior,
                    transform: { $0.workItem },
                    onUpdate: onUpdate
                )
            }

            for await _ in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }
            }
        }

        guard !Task.isCancelled else {
            throw .cancelled
        }
    }

    private func loadCurrentUser(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onUpdate:
            @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
    ) async {
        do {
            try await client.loadResponse(
                HomeDashboardEndpoints.currentUser,
                cachePolicy: .home,
                refreshBehavior: refreshBehavior
            ) {
                await onUpdate(
                    .user(.success($0.value))
                )
            }
        } catch {
            await onUpdate(.user(.failure(error)))
        }
    }

    private func loadWorkItems<Item>(
        _ request: GitLabAPIRequest<[Item]>,
        section: HomeDashboardSection,
        refreshBehavior: GitLabCacheRefreshBehavior,
        transform:
            @escaping @Sendable (Item) -> GitLabHomeWorkItem,
        onUpdate:
            @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
    ) async
    where Item: Decodable, Item: Sendable {
        do {
            try await client.loadResponse(
                request,
                cachePolicy: .home,
                refreshBehavior: refreshBehavior
            ) {
                await onUpdate(
                    .section(
                        section,
                        .success(
                            $0.value.map(transform)
                        )
                    )
                )
            }
        } catch {
            await onUpdate(
                .section(
                    section,
                    .failure(error)
                )
            )
        }
    }
}
