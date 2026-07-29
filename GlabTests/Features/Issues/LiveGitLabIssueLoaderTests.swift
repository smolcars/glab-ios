import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab issue loader")
struct LiveGitLabIssueLoaderTests {
    @Test("Loads the initial page, next page, and issue detail")
    func loadsIssueResources() async throws {
        let issue = makeTestIssue()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/issues?page=2"
            )
        )
        let client = RecordingIssueClient(
            issue: issue,
            returnedNextPageURL: nextPageURL
        )
        let loader = LiveGitLabIssueLoader(client: client)

        let initialPage = try await loader.loadAssignedIssuesPage(
            after: nil
        )
        let nextPage = try await loader.loadAssignedIssuesPage(
            after: nextPageURL
        )
        let projectPage =
            try await loader
                .loadProjectIssuesPage(
                    projectID: 42,
                    state: .opened,
                    after: nil
                )
        let projectEvents =
            IssuePageEventCollector()
        try await loader
            .loadProjectIssuesFirstPage(
                projectID: 42,
                state: .closed,
                refreshBehavior: .ifStale
            ) {
                await projectEvents.append($0)
            }
        let detail = try await loader.loadIssue(at: issue.route)
        let detailEvents = IssueDetailEventCollector()
        try await loader.loadIssue(
            at: issue.route,
            refreshBehavior: .ifStale
        ) {
            await detailEvents.append($0)
        }

        #expect(initialPage.issues == [issue])
        #expect(initialPage.nextPageURL == nextPageURL)
        #expect(nextPage.issues == [issue])
        #expect(projectPage.items == [issue])
        #expect(projectPage.totalCount == 3)
        #expect(
            await projectEvents.events
                .map(\.page.items)
                == [[issue]]
        )
        #expect(detail == issue)
        #expect(
            await detailEvents.events
                .map(\.value) == [issue]
        )
        #expect(
            await detailEvents.events
                .map(\.source)
                == [.cache(.stale)]
        )
        #expect(
            await client.cachePolicies
                == [
                    .workList,
                    .workItemDetail,
                ]
        )
        #expect(
            await client.pageSources
                == [
                    "initial:issues",
                    "next:\(nextPageURL.absoluteString)",
                    "initial:projects/42/issues",
                    "initial:projects/42/issues",
                ]
        )
        #expect(
            await client.projectStates
                == ["opened", "closed"]
        )
        #expect(
            await client.detailPaths
                == [
                    ["projects", "42", "issues", "7"],
                    ["projects", "42", "issues", "7"],
                ]
        )
    }
}

private extension LiveGitLabIssueLoaderTests {
    actor RecordingIssueClient:
        GitLabPaginatedSessionRequestSending
    {
        let issue: GitLabIssue
        let returnedNextPageURL: URL?
        private(set) var pageSources: [String] = []
        private(set) var detailPaths: [[String]] = []
        private(set) var projectStates:
            [String] = []
        private(set) var cachePolicies:
            [GitLabResponseCachePolicy] = []

        init(
            issue: GitLabIssue,
            returnedNextPageURL: URL?
        ) {
            self.issue = issue
            self.returnedNextPageURL = returnedNextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            detailPaths.append(endpoint.pathComponents)
            return issue as! Response
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                pageSources.append(
                    "initial:\(endpoint.pathComponents.joined(separator: "/"))"
                )
                if
                    endpoint.pathComponents.first
                        == "projects",
                    endpoint.pathComponents.last
                        == "issues",
                    let state =
                        endpoint.queryItems
                        .first(where: {
                            $0.name == "state"
                        })?
                        .value
                {
                    projectStates.append(state)
                }
            case let .next(url):
                pageSources.append("next:\(url.absoluteString)")
            }

            return GitLabAPIResponse(
                value: [issue] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL: returnedNextPageURL,
                    totalCount: 3
                )
            )
        }

        func loadResponse<Response>(
            _ endpoint: GitLabAPIRequest<Response>,
            cachePolicy: GitLabResponseCachePolicy,
            refreshBehavior: GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<Response>
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            cachePolicies.append(cachePolicy)
            await onResponse(
                GitLabAPIResponseEvent(
                    value:
                        try await send(endpoint),
                    metadata: GitLabResponseMetadata(),
                    source: .cache(.stale)
                )
            )
        }

        func loadPage<Response>(
            _ page:
                GitLabAPIPageRequest<Response>,
            cachePolicy:
                GitLabResponseCachePolicy,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<
                        Response
                    >
                ) async -> Void
        ) async throws(
            GitLabSessionClientError
        ) {
            cachePolicies.append(cachePolicy)
            let response =
                try await sendPage(page)
            await onResponse(
                GitLabAPIResponseEvent(
                    value: response.value,
                    metadata:
                        response.metadata,
                    source: .network
                )
            )
        }
    }

    actor IssueDetailEventCollector {
        private(set) var events:
            [GitLabAPIResponseEvent<GitLabIssue>] = []

        func append(
            _ event:
                GitLabAPIResponseEvent<GitLabIssue>
        ) {
            events.append(event)
        }
    }

    actor IssuePageEventCollector {
        private(set) var events:
            [
                GitLabResourcePageEvent<
                    GitLabIssue
                >
            ] = []

        func append(
            _ event:
                GitLabResourcePageEvent<
                    GitLabIssue
                >
        ) {
            events.append(event)
        }
    }
}
