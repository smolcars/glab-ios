import Foundation

typealias ProjectsModel =
    GitLabPaginatedResourceModel<
        GitLabProject,
        Int
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabProject,
    Identity == Int
{
    convenience init(
        mode: GitLabProjectListMode,
        loader: any GitLabProjectLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<GitLabProject> in
                let page = try await loader.loadProjectsPage(
                    for: mode,
                    after: nextPageURL
                )
                return GitLabResourcePage(
                    items: page.projects,
                    nextPageURL: page.nextPageURL
                )
            },
            identity: { $0.id },
            searchValues: {
                [
                    $0.name,
                    $0.nameWithNamespace,
                    $0.pathWithNamespace,
                    $0.visibility.title,
                    $0.namespace?.name,
                    $0.namespace?.path,
                    $0.namespace?.fullPath,
                ]
                .compactMap(\.self)
            }
        )
    }

    var projects: [GitLabProject] {
        items
    }

    var displayedProjects: [GitLabProject] {
        displayedItems
    }
}

