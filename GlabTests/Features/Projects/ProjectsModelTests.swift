import Foundation
import Testing
@testable import Glab

@Suite("Projects model")
@MainActor
struct ProjectsModelTests {
    @Test("Appends pages without duplicate project IDs")
    func appendsPagesWithoutDuplicates() async throws {
        let first = makeTestProject(
            id: 1,
            name: "First"
        )
        let second = makeTestProject(
            id: 2,
            name: "Second"
        )
        let duplicateSecond = makeTestProject(
            id: 2,
            name: "Duplicate second"
        )
        let third = makeTestProject(
            id: 3,
            name: "Third"
        )
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects?page=2"
            )
        )
        let loader = StubProjectLoader(
            pageResults: [
                .success(
                    GitLabProjectPage(
                        projects: [first, second],
                        nextPageURL: nextPageURL
                    )
                ),
                .success(
                    GitLabProjectPage(
                        projects: [
                            duplicateSecond,
                            third,
                        ],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = ProjectsModel(
            mode: .starred,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.loadNextPageIfNeeded(
            after: try #require(model.projects.last)
        )

        #expect(
            model.projects.map(\.name)
                == ["First", "Second", "Third"]
        )
        #expect(model.nextPageURL == nil)
        #expect(
            await loader.pageModes
                == [.starred, .starred]
        )
        #expect(
            await loader.pageRequestURLs
                == [nil, nextPageURL]
        )
    }

    @Test("Filters loaded projects locally")
    func filtersLoadedProjects() async {
        let core = makeTestProject(
            id: 1,
            name: "GitLab Core",
            nameWithNamespace:
                "Platform Engineering / GitLab Core",
            pathWithNamespace:
                "platform-engineering/gitlab-core",
            visibility: .internalAccess,
            namespace: GitLabProjectNamespace(
                id: 1,
                name: "Platform Engineering",
                path: "platform-engineering",
                kind: "group",
                fullPath: "platform-engineering"
            )
        )
        let app = makeTestProject(
            id: 2,
            name: "Glab iOS",
            nameWithNamespace: "Mobile / Glab iOS",
            pathWithNamespace: "mobile/glab-ios",
            visibility: .privateAccess
        )
        let loader = StubProjectLoader(
            pageResults: [
                .success(
                    GitLabProjectPage(
                        projects: [core, app],
                        nextPageURL: nil
                    )
                ),
            ]
        )
        let model = ProjectsModel(
            mode: .recent,
            loader: loader
        )
        await model.loadIfNeeded()

        for query in [
            "core",
            "PLATFORM",
            "platform-engineering",
            "internal",
        ] {
            model.searchText = query
            #expect(model.displayedProjects.map(\.id) == [1])
        }

        model.searchText = "glab-ios"
        #expect(model.displayedProjects.map(\.id) == [2])
        model.searchText = " "
        #expect(model.displayedProjects.map(\.id) == [1, 2])
    }

    @Test("Preserves projects and reports a failed refresh")
    func preservesProjectsAfterRefreshFailure() async {
        let project = makeTestProject()
        let loader = StubProjectLoader(
            pageResults: [
                .success(
                    GitLabProjectPage(
                        projects: [project],
                        nextPageURL: nil
                    )
                ),
                .failure(.api(.server(statusCode: 503))),
            ]
        )
        let model = ProjectsModel(
            mode: .recent,
            loader: loader
        )

        await model.loadIfNeeded()
        await model.refresh()

        #expect(model.projects == [project])
        #expect(model.didFailRefresh)
        #expect(
            model.loadError == .api(.server(statusCode: 503))
        )
    }

    @Test("Treats cancellation as a non-result")
    func ignoresCancellation() async {
        let loader = StubProjectLoader(
            pageResults: [
                .failure(.api(.cancelled)),
            ]
        )
        let model = ProjectsModel(
            mode: .recent,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(!model.hasLoaded)
        #expect(model.loadError == nil)
        #expect(model.projects.isEmpty)
    }

    @Test("Exposes authentication failures")
    func exposesAuthenticationFailure() async {
        let loader = StubProjectLoader(
            pageResults: [
                .failure(.api(.unauthenticated)),
            ]
        )
        let model = ProjectsModel(
            mode: .recent,
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(
            model.authenticationFailure
                == .api(.unauthenticated)
        )
    }
}

private actor StubProjectLoader: GitLabProjectLoading {
    private var pageResults: [
        Result<GitLabProjectPage, GitLabSessionClientError>
    ]
    private(set) var pageModes: [GitLabProjectListMode] = []
    private(set) var pageRequestURLs: [URL?] = []

    init(
        pageResults: [
            Result<GitLabProjectPage, GitLabSessionClientError>
        ]
    ) {
        self.pageResults = pageResults
    }

    func loadProjectsPage(
        for mode: GitLabProjectListMode,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabProjectPage
    {
        pageModes.append(mode)
        pageRequestURLs.append(nextPageURL)
        guard !pageResults.isEmpty else {
            throw .api(.invalidResponse)
        }

        return try pageResults.removeFirst().get()
    }
}

