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
    func load()
        async throws(HomeDashboardLoadingError)
        -> HomeDashboardLoadResult
    {
        async let user = loadCurrentUser()
        async let assignedIssues = loadWorkItems(
            HomeDashboardEndpoints.assignedIssues
        ) { $0.workItem }
        async let assignedMergeRequests = loadWorkItems(
            HomeDashboardEndpoints.assignedMergeRequests
        ) { $0.workItem }
        async let reviewRequests = loadWorkItems(
            HomeDashboardEndpoints.reviewRequests
        ) { $0.workItem }
        async let recentProjects = loadWorkItems(
            HomeDashboardEndpoints.recentProjects
        ) { $0.workItem }
        async let starredProjects = loadWorkItems(
            HomeDashboardEndpoints.starredProjects
        ) { $0.workItem }

        let values = await (
            user,
            assignedIssues,
            assignedMergeRequests,
            reviewRequests,
            recentProjects,
            starredProjects
        )

        guard !Task.isCancelled else {
            throw .cancelled
        }

        return HomeDashboardLoadResult(
            user: values.0,
            sections: [
                .assignedIssues: values.1,
                .assignedMergeRequests: values.2,
                .reviewRequests: values.3,
                .recentProjects: values.4,
                .starredProjects: values.5,
            ]
        )
    }

    private func loadCurrentUser() async
        -> HomeDashboardLoadResult.UserResult
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
        -> HomeDashboardLoadResult.WorkResult
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
