import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab project loader")
struct LiveGitLabProjectLoaderTests {
    @Test("Loads both project modes and follows a next-page URL")
    func loadsProjectPages() async throws {
        let project = makeTestProject()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects?page=2"
            )
        )
        let client = RecordingProjectClient(
            project: project,
            returnedNextPageURL: nextPageURL
        )
        let loader = LiveGitLabProjectLoader(
            client: client
        )

        let recent = try await loader.loadProjectsPage(
            for: .recent,
            after: nil
        )
        let starred = try await loader.loadProjectsPage(
            for: .starred,
            after: nil
        )
        let nextPage = try await loader.loadProjectsPage(
            for: .recent,
            after: nextPageURL
        )
        let cachedPages = ProjectPageEventCollector()
        try await loader.loadProjectsFirstPage(
            for: .starred,
            refreshBehavior: .ifStale
        ) {
            await cachedPages.append($0)
        }

        #expect(recent.projects == [project])
        #expect(recent.nextPageURL == nextPageURL)
        #expect(starred.projects == [project])
        #expect(nextPage.projects == [project])
        #expect(
            await cachedPages.events
                .map(\.page.items) == [[project]]
        )
        #expect(
            await cachedPages.events
                .map(\.page.nextPageURL)
                == [nextPageURL]
        )
        #expect(
            await cachedPages.events
                .map(\.source)
                == [.cache(.stale)]
        )
        #expect(
            await client.cachePolicies
                == [.projects]
        )
        #expect(
            await client.refreshBehaviors
                == [.ifStale]
        )
        #expect(
            await client.pageSources
                == [
                    "initial:projects:membership",
                    "initial:projects:starred",
                    "next:\(nextPageURL.absoluteString)",
                    "initial:projects:starred",
                ]
        )
    }
}

private extension LiveGitLabProjectLoaderTests {
    actor RecordingProjectClient:
        GitLabPaginatedSessionRequestSending
    {
        let project: GitLabProject
        let returnedNextPageURL: URL?
        private(set) var pageSources: [String] = []
        private(set) var cachePolicies:
            [GitLabResponseCachePolicy] = []
        private(set) var refreshBehaviors:
            [GitLabCacheRefreshBehavior] = []

        init(
            project: GitLabProject,
            returnedNextPageURL: URL?
        ) {
            self.project = project
            self.returnedNextPageURL = returnedNextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            throw .api(.invalidResponse)
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                let filter = endpoint.queryItems.first?.name
                    ?? "missing"
                pageSources.append(
                    "initial:"
                        + endpoint.pathComponents.joined(separator: "/")
                        + ":\(filter)"
                )
            case let .next(url):
                pageSources.append("next:\(url.absoluteString)")
            }

            return GitLabAPIResponse(
                value: [project] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL: returnedNextPageURL
                )
            )
        }

        func loadPage<Response>(
            _ page: GitLabAPIPageRequest<Response>,
            cachePolicy: GitLabResponseCachePolicy,
            refreshBehavior: GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<Response>
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            cachePolicies.append(cachePolicy)
            refreshBehaviors.append(refreshBehavior)
            let response:
                GitLabAPIResponse<Response> =
                    try await sendPage(page)
            await onResponse(
                GitLabAPIResponseEvent(
                    value: response.value,
                    metadata: response.metadata,
                    source: .cache(.stale)
                )
            )
        }
    }

    actor ProjectPageEventCollector {
        private(set) var events:
            [GitLabResourcePageEvent<GitLabProject>] = []

        func append(
            _ event:
                GitLabResourcePageEvent<GitLabProject>
        ) {
            events.append(event)
        }
    }
}
