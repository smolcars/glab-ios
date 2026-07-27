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
        async let assignedIssues = loadAssignedIssues()
        async let assignedMergeRequests = loadAssignedMergeRequests()
        async let reviewRequests = loadReviewRequests()
        async let recentProjects = loadRecentProjects()
        async let starredProjects = loadStarredProjects()

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

    private func loadAssignedIssues() async
        -> HomeDashboardLoadResult.WorkResult
    {
        do {
            let issues = try await client.send(
                HomeDashboardEndpoints.assignedIssues
            )
            return .success(issues.map(\.workItem))
        } catch {
            return .failure(error)
        }
    }

    private func loadAssignedMergeRequests() async
        -> HomeDashboardLoadResult.WorkResult
    {
        do {
            let mergeRequests = try await client.send(
                HomeDashboardEndpoints.assignedMergeRequests
            )
            return .success(mergeRequests.map(\.workItem))
        } catch {
            return .failure(error)
        }
    }

    private func loadReviewRequests() async
        -> HomeDashboardLoadResult.WorkResult
    {
        do {
            let mergeRequests = try await client.send(
                HomeDashboardEndpoints.reviewRequests
            )
            return .success(mergeRequests.map(\.workItem))
        } catch {
            return .failure(error)
        }
    }

    private func loadRecentProjects() async
        -> HomeDashboardLoadResult.WorkResult
    {
        do {
            let projects = try await client.send(
                HomeDashboardEndpoints.recentProjects
            )
            return .success(projects.map(\.workItem))
        } catch {
            return .failure(error)
        }
    }

    private func loadStarredProjects() async
        -> HomeDashboardLoadResult.WorkResult
    {
        do {
            let projects = try await client.send(
                HomeDashboardEndpoints.starredProjects
            )
            return .success(projects.map(\.workItem))
        } catch {
            return .failure(error)
        }
    }
}
