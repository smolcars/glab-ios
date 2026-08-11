import Foundation
import Testing
@testable import Glab

@Suite("GitLab deep-link route resolver")
struct GitLabDeepLinkRouteResolverTests {
    @Test("Projects route without an API lookup")
    func resolvesProjectDirectly() async throws {
        let projects = RecordingProjectResolver()
        let resolver =
            GitLabDeepLinkRouteResolver(
                projectLoader: projects
            )

        let route = try await resolver.resolve(
            .project(
                pathWithNamespace:
                    "group/project"
            )
        )

        #expect(
            route == .project(
                GitLabProjectRoute(
                    pathWithNamespace:
                        "group/project"
                )
            )
        )
        #expect(await projects.paths.isEmpty)
    }

    @Test("Resolves issue and merge-request project paths to numeric routes")
    func resolvesWorkItemProjectIDs() async throws {
        let projects = RecordingProjectResolver(
            project: makeTestProject(id: 42)
        )
        let resolver =
            GitLabDeepLinkRouteResolver(
                projectLoader: projects
            )

        let issue = try await resolver.resolve(
            .issue(
                pathWithNamespace:
                    "group/project",
                iid: 7
            )
        )
        let mergeRequest =
            try await resolver.resolve(
                .mergeRequest(
                    pathWithNamespace:
                        "group/project",
                    iid: 8
                )
            )

        #expect(
            issue == .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        )
        #expect(
            mergeRequest == .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 8
                )
            )
        )
        #expect(
            await projects.paths
                == [
                    "group/project",
                    "group/project",
                ]
        )
    }

    @Test("Resolves a repository file with project metadata")
    func resolvesRepositoryFile() async throws {
        let project = makeTestProject(
            id: 42,
            webURL: try #require(
                URL(
                    string:
                        "https://gitlab.example.com/group/project"
                )
            )
        )
        let projects = RecordingProjectResolver(
            project: project
        )
        let resolver = GitLabDeepLinkRouteResolver(
            projectLoader: projects
        )

        let route = try await resolver.resolve(
            .repositoryFile(
                pathWithNamespace:
                    "group/project",
                ref: "main",
                path: "docs/CONTRIBUTING.md"
            )
        )

        #expect(
            route == .repositoryFile(
                GitLabRepositoryFileRoute(
                    projectID: 42,
                    projectWebURL:
                        project.safeWebURL,
                    ref: "main",
                    path: "docs/CONTRIBUTING.md",
                    blobID: nil
                )
            )
        )
        #expect(
            await projects.paths
                == ["group/project"]
        )
    }
}

private actor RecordingProjectResolver:
    GitLabProjectResolving
{
    let project: GitLabProject
    private(set) var paths: [String] = []

    init(
        project: GitLabProject =
            makeTestProject()
    ) {
        self.project = project
    }

    func loadProject(
        pathWithNamespace: String
    ) async throws(GitLabSessionClientError)
        -> GitLabProject
    {
        paths.append(pathWithNamespace)
        return project
    }
}
