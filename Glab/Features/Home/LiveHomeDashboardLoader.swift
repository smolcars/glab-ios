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
        onUpdate:
            @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
    ) async throws(HomeDashboardLoadingError) {
        await withTaskGroup(
            of: HomeDashboardLoadUpdate.self
        ) { group in
            group.addTask {
                .user(await loadCurrentUser())
            }
            group.addTask {
                .section(
                    .assignedIssues,
                    await loadWorkItems(
                        HomeDashboardEndpoints.assignedIssues
                    ) { $0.workItem }
                )
            }
            group.addTask {
                .section(
                    .assignedMergeRequests,
                    await loadWorkItems(
                        HomeDashboardEndpoints.assignedMergeRequests
                    ) { $0.workItem }
                )
            }
            group.addTask {
                .section(
                    .reviewRequests,
                    await loadWorkItems(
                        HomeDashboardEndpoints.reviewRequests
                    ) { $0.workItem }
                )
            }
            group.addTask {
                .section(
                    .recentProjects,
                    await loadWorkItems(
                        HomeDashboardEndpoints.recentProjects
                    ) { $0.workItem }
                )
            }
            group.addTask {
                .section(
                    .starredProjects,
                    await loadWorkItems(
                        HomeDashboardEndpoints.starredProjects
                    ) { $0.workItem }
                )
            }

            for await update in group {
                guard !Task.isCancelled else {
                    group.cancelAll()
                    return
                }

                await onUpdate(update)
            }
        }

        guard !Task.isCancelled else {
            throw .cancelled
        }
    }

    private func loadCurrentUser() async
        -> HomeDashboardLoadUpdate.UserResult
    {
        do {
            return .success(
                try await client.send(
                    HomeDashboardEndpoints.currentUser
                )
            )
        } catch {
            return .failure(error)
        }
    }

    private func loadWorkItems<Item>(
        _ request: GitLabAPIRequest<[Item]>,
        transform: @Sendable (Item) -> GitLabHomeWorkItem
    ) async
        -> HomeDashboardLoadUpdate.WorkResult
    where Item: Decodable, Item: Sendable
    {
        do {
            let items = try await client.send(request)
            return .success(items.map(transform))
        } catch {
            return .failure(error)
        }
    }
}
