import Testing
@testable import Glab

@MainActor
@Suite("GitLab project detail model")
struct GitLabProjectDetailModelTests {
    @Test("Loads a project by its namespaced path")
    func loadsProject() async {
        let project = makeTestProject()
        let loader =
            ProjectDetailLoader(
                result: .success(project)
            )
        let route = GitLabProjectRoute(
            pathWithNamespace:
                "group/project"
        )
        let model = GitLabProjectDetailModel(
            route: route,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.state == .loaded(project))
        #expect(
            await loader.paths
                == ["group/project"]
        )
    }

    @Test("Shows a routed project while revalidating")
    func showsRoutedProjectWhileRevalidating() async {
        let initialProject = makeTestProject(
            starCount: 2
        )
        let refreshedProject = makeTestProject(
            starCount: 3
        )
        let loader = ProjectDetailLoader(
            result: .success(refreshedProject)
        )
        let model = GitLabProjectDetailModel(
            route: GitLabProjectRoute(
                pathWithNamespace:
                    "mobile/glab-ios",
                initialProject:
                    initialProject
            ),
            loader: loader
        )

        #expect(
            model.state
                == .loaded(initialProject)
        )

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(
            model.state
                == .loaded(refreshedProject)
        )
        #expect(
            await loader.paths
                == ["mobile/glab-ios"]
        )
    }

    @Test("Exposes a project loading failure")
    func exposesFailure() async {
        let loader =
            ProjectDetailLoader(
                result:
                    .failure(
                        .api(.notFound)
                    )
            )
        let model = GitLabProjectDetailModel(
            route: GitLabProjectRoute(
                pathWithNamespace:
                    "group/missing"
            ),
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(
            model.state == .failed(
                .api(.notFound)
            )
        )
    }
}

private actor ProjectDetailLoader:
    GitLabProjectResolving
{
    let result:
        Result<
            GitLabProject,
            GitLabSessionClientError
        >
    private(set) var paths: [String] = []

    init(
        result:
            Result<
                GitLabProject,
                GitLabSessionClientError
            >
    ) {
        self.result = result
    }

    func loadProject(
        pathWithNamespace: String
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
    {
        paths.append(pathWithNamespace)
        return try result.get()
    }
}
