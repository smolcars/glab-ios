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
                await loadCombinedWorkItems(
                    [
                        HomeDashboardEndpoints
                            .assignedIssues,
                        HomeDashboardEndpoints
                            .createdIssues,
                    ],
                    section: .assignedIssues,
                    refreshBehavior: refreshBehavior,
                    transform: { $0.workItem },
                    onUpdate: onUpdate
                )
            }
            group.addTask {
                await loadCombinedWorkItems(
                    [
                        HomeDashboardEndpoints
                            .assignedMergeRequests,
                        HomeDashboardEndpoints
                            .createdMergeRequests,
                        HomeDashboardEndpoints
                            .reviewRequests,
                    ],
                    section: .assignedMergeRequests,
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

    private func loadCombinedWorkItems<Item>(
        _ requests:
            [GitLabAPIRequest<[Item]>],
        section: HomeDashboardSection,
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        transform:
            @escaping @Sendable (
                Item
            ) -> GitLabHomeWorkItem,
        onUpdate:
            @escaping @Sendable (
                HomeDashboardLoadUpdate
            ) async -> Void
    ) async
    where Item: Decodable, Item: Sendable {
        let accumulator =
            HomeDashboardPreviewAccumulator(
                section: section,
                sourceCount: requests.count,
                onUpdate: onUpdate
            )

        await withTaskGroup(
            of: Void.self
        ) { group in
            for (
                source,
                request
            ) in requests.enumerated() {
                group.addTask {
                    do {
                        try await client
                            .loadResponse(
                                request,
                                cachePolicy: .home,
                                refreshBehavior:
                                    refreshBehavior
                            ) {
                                await accumulator
                                    .receive(
                                        $0.value.map(
                                            transform
                                        ),
                                        from: source
                                    )
                            }
                        await accumulator
                            .complete(
                                source: source
                            )
                    } catch
                        let error
                            as GitLabSessionClientError
                    {
                        await accumulator
                            .complete(
                                source: source,
                                error: error
                            )
                    } catch {
                        await accumulator
                            .complete(
                                source: source,
                                error:
                                    .api(
                                        .invalidResponse
                                    )
                            )
                    }
                }
            }

            await group.waitForAll()
        }
    }
}

private actor
    HomeDashboardPreviewAccumulator
{
    private let section:
        HomeDashboardSection
    private let sourceCount: Int
    private let onUpdate:
        @Sendable (
            HomeDashboardLoadUpdate
        ) async -> Void
    private var itemsBySource:
        [Int: [GitLabHomeWorkItem]] = [:]
    private var completedSources: Set<Int> = []
    private var errors:
        [GitLabSessionClientError] = []

    init(
        section: HomeDashboardSection,
        sourceCount: Int,
        onUpdate:
            @escaping @Sendable (
                HomeDashboardLoadUpdate
            ) async -> Void
    ) {
        self.section = section
        self.sourceCount = sourceCount
        self.onUpdate = onUpdate
    }

    func receive(
        _ items: [GitLabHomeWorkItem],
        from source: Int
    ) async {
        itemsBySource[source] = items
        guard
            itemsBySource.count
                == sourceCount
        else {
            return
        }

        await publishItems()
    }

    func complete(
        source: Int,
        error:
            GitLabSessionClientError? = nil
    ) async {
        completedSources.insert(source)
        if let error {
            errors.append(error)
        }

        guard
            completedSources.count
                == sourceCount
        else {
            return
        }

        if
            itemsBySource.count
                < sourceCount,
            !itemsBySource.isEmpty
        {
            await publishItems()
        }

        if let error = errors.first {
            await onUpdate(
                .section(
                    section,
                    .failure(error)
                )
            )
        }
    }

    private func publishItems() async {
        await onUpdate(
            .section(
                section,
                .success(
                    HomeDashboardPreview.merge(
                        Array(
                            itemsBySource
                                .values
                        ),
                        limit: 3
                    )
                )
            )
        )
    }
}
