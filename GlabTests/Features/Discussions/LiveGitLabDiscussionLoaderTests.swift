import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab discussion loader")
struct LiveGitLabDiscussionLoaderTests {
    @Test("Shares issue and merge request first and next-page loading")
    func loadsBothResources() async throws {
        let discussion = makeTestDiscussion()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/issues/7/discussions"
                    + "?page=2&per_page=20"
            )
        )
        let client = RecordingDiscussionClient(
            discussion: discussion,
            returnedNextPageURL: nextPageURL
        )
        let loader = LiveGitLabDiscussionLoader(
            client: client
        )
        let issue: GitLabDiscussionResource =
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        let mergeRequest: GitLabDiscussionResource =
            .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 9
                )
            )

        let issuePage = try await loader
            .loadDiscussionsPage(
                for: issue,
                after: nil
            )
        let mergeRequestPage = try await loader
            .loadDiscussionsPage(
                for: mergeRequest,
                after: nil
            )
        let nextPage = try await loader
            .loadDiscussionsPage(
                for: issue,
                after: nextPageURL
            )
        let collector = DiscussionPageEventCollector()
        try await loader.loadDiscussionsFirstPage(
            for: issue,
            refreshBehavior: .ifStale
        ) {
            await collector.append($0)
        }

        #expect(issuePage.items == [discussion])
        #expect(
            issuePage.nextPageURL == nextPageURL
        )
        #expect(issuePage.totalCount == 37)
        #expect(mergeRequestPage.items == [discussion])
        #expect(nextPage.items == [discussion])
        #expect(
            await collector.events
                .map(\.page.items)
                == [[discussion]]
        )
        #expect(
            await collector.events
                .map(\.source)
                == [.cache(.stale)]
        )
        #expect(
            await client.cachePolicies
                == [.discussions]
        )
        #expect(
            await client.refreshBehaviors
                == [.ifStale]
        )
        #expect(
            await client.pageSources
                == [
                    "initial:projects/42/issues/7/discussions",
                    "initial:projects/42/merge_requests/9/discussions",
                    "next:\(nextPageURL.absoluteString)",
                    "cached:projects/42/issues/7/discussions",
                ]
        )
    }
}

private extension LiveGitLabDiscussionLoaderTests {
    actor RecordingDiscussionClient:
        GitLabPaginatedSessionRequestSending
    {
        let discussion: GitLabDiscussion
        let returnedNextPageURL: URL?
        private(set) var pageSources: [String] = []
        private(set) var cachePolicies:
            [GitLabResponseCachePolicy] = []
        private(set) var refreshBehaviors:
            [GitLabCacheRefreshBehavior] = []

        init(
            discussion: GitLabDiscussion,
            returnedNextPageURL: URL?
        ) {
            self.discussion = discussion
            self.returnedNextPageURL =
                returnedNextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> Response
        {
            throw .api(.invalidResponse)
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            pageSources.append(source(for: page))
            return GitLabAPIResponse(
                value: [discussion] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL:
                        returnedNextPageURL,
                    totalCount: 37
                )
            )
        }

        func loadPage<Response>(
            _ page: GitLabAPIPageRequest<Response>,
            cachePolicy: GitLabResponseCachePolicy,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<Response>
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            pageSources.append(
                "cached:\(path(for: page))"
            )
            cachePolicies.append(cachePolicy)
            refreshBehaviors.append(refreshBehavior)
            await onResponse(
                GitLabAPIResponseEvent(
                    value:
                        [discussion] as! Response,
                    metadata:
                        GitLabResponseMetadata(
                            nextPageURL:
                                returnedNextPageURL,
                            totalCount: 37
                        ),
                    source: .cache(.stale),
                    cacheStoredAt: Date(
                        timeIntervalSince1970: 500
                    )
                )
            )
        }

        private func source<Response>(
            for page: GitLabAPIPageRequest<Response>
        ) -> String {
            switch page {
            case let .initial(endpoint):
                "initial:"
                    + endpoint.pathComponents
                    .joined(separator: "/")
            case let .next(url):
                "next:\(url.absoluteString)"
            }
        }

        private func path<Response>(
            for page: GitLabAPIPageRequest<Response>
        ) -> String {
            guard case let .initial(endpoint) = page
            else {
                return "next"
            }
            return endpoint.pathComponents
                .joined(separator: "/")
        }
    }

    actor DiscussionPageEventCollector {
        private(set) var events:
            [
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
            ] = []

        func append(
            _ event:
                GitLabResourcePageEvent<
                    GitLabDiscussion
                >
        ) {
            events.append(event)
        }
    }
}
