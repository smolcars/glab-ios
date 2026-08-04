import Foundation

nonisolated protocol GitLabProjectStarringServing:
    Sendable
{
    func isStarred(
        _ project: GitLabProject
    ) async throws(GitLabSessionClientError) -> Bool

    func setStarred(
        _ isStarred: Bool,
        for project: GitLabProject
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
}

nonisolated struct LiveGitLabProjectStarringService:
    GitLabProjectStarringServing,
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
    func isStarred(
        _ project: GitLabProject
    ) async throws(GitLabSessionClientError) -> Bool {
        var page:
            GitLabAPIPageRequest<
                [GitLabProject]
            > = .initial(
                GitLabProjectEndpoints
                    .projects(
                        for: .starred,
                        perPage: 100
                    )
            )

        while true {
            let response = try await client.sendPage(
                page
            )
            if response.value.contains(
                where: { $0.id == project.id }
            ) {
                return true
            }
            guard
                let nextPageURL =
                    response.metadata.nextPageURL
            else {
                return false
            }
            page = .next(nextPageURL)
        }
    }

    @concurrent
    func setStarred(
        _ isStarred: Bool,
        for project: GitLabProject
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
    {
        let endpoint =
            if isStarred {
                GitLabProjectEndpoints.star(
                    projectID: project.id
                )
            } else {
                GitLabProjectEndpoints.unstar(
                    projectID: project.id
                )
            }

        do {
            let updatedProject: GitLabProject
            do {
                updatedProject = try await client.send(
                    endpoint
                )
            } catch let mutationError {
                guard
                    mutationError
                        == .api(.invalidResponse),
                    try await self.isStarred(
                        project
                    ) == isStarred
                else {
                    throw mutationError
                }
                updatedProject = try await client.send(
                    GitLabProjectEndpoints.project(
                        pathWithNamespace:
                            project.pathWithNamespace
                    )
                )
            }
            await invalidateProjectReads(
                pathWithNamespace:
                    project.pathWithNamespace
            )
            return updatedProject
        } catch {
            let sessionError =
                error as? GitLabSessionClientError
                    ?? .api(.transport)
            if
                sessionError
                    .mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                await invalidateProjectReads(
                    pathWithNamespace:
                        project.pathWithNamespace
                )
            }
            throw sessionError
        }
    }

    @concurrent
    private func invalidateProjectReads(
        pathWithNamespace: String
    ) async {
        await client.invalidateCachedResponse(
            GitLabProjectEndpoints.project(
                pathWithNamespace:
                    pathWithNamespace
            )
        )
        await client.invalidateCachedResponse(
            GitLabProjectEndpoints.projects(
                for: .recent
            )
        )
        await client.invalidateCachedResponse(
            GitLabProjectEndpoints.projects(
                for: .starred
            )
        )
    }
}
