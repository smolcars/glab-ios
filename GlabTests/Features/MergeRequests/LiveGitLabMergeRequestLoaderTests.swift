import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab merge request loader")
struct LiveGitLabMergeRequestLoaderTests {
    @Test("Loads list modes, detail, and head-aware diff pages")
    func loadsMergeRequestResources() async throws {
        let mergeRequest = makeTestMergeRequest()
        let diff = makeTestDiffFile()
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "merge_requests?page=2"
            )
        )
        let nextDiffPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/merge_requests/7/"
                    + "diffs?page=2"
            )
        )
        let client = RecordingMergeRequestClient(
            mergeRequest: mergeRequest,
            diff: diff,
            returnedNextPageURL: nextPageURL
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )

        let assigned = try await loader.loadMergeRequestsPage(
            for: .assigned,
            after: nil
        )
        let reviewRequested = try await loader.loadMergeRequestsPage(
            for: .reviewRequested,
            after: nil
        )
        let nextPage = try await loader.loadMergeRequestsPage(
            for: .assigned,
            after: nextPageURL
        )
        let detail = try await loader.loadMergeRequest(
            at: mergeRequest.route
        )
        let firstDiffPage =
            try await loader.loadMergeRequestDiffsPage(
                at: mergeRequest.route,
                headSHA: "head-sha",
                after: nil
            )
        let nextDiffPage =
            try await loader.loadMergeRequestDiffsPage(
                at: mergeRequest.route,
                headSHA: "head-sha",
                after: nextDiffPageURL
            )

        #expect(assigned.mergeRequests == [mergeRequest])
        #expect(assigned.nextPageURL == nextPageURL)
        #expect(reviewRequested.mergeRequests == [mergeRequest])
        #expect(nextPage.mergeRequests == [mergeRequest])
        #expect(detail == mergeRequest)
        #expect(firstDiffPage.files == [diff])
        #expect(
            firstDiffPage.nextPageURL
                == nextPageURL
        )
        #expect(nextDiffPage.files == [diff])
        #expect(
            await client.pageSources
                == [
                    "initial:merge_requests:assigned_to_me",
                    "initial:merge_requests:reviews_for_me",
                    "next:\(nextPageURL.absoluteString)",
                ]
        )
        #expect(
            await client.diffPageSources
                == [
                    "initial:head-sha",
                    "next:\(nextDiffPageURL.absoluteString)",
                ]
        )
        #expect(
            await client.detailPaths
                == [["projects", "42", "merge_requests", "7"]]
        )
    }

    @Test("Publishes a diff first page through the diff cache policy")
    func loadsCachedDiffFirstPage() async throws {
        let mergeRequest = makeTestMergeRequest()
        let diff = makeTestDiffFile()
        let client = RecordingMergeRequestClient(
            mergeRequest: mergeRequest,
            diff: diff,
            returnedNextPageURL: nil
        )
        let loader = LiveGitLabMergeRequestLoader(
            client: client
        )
        let events = DiffPageEventRecorder()

        try await loader.loadMergeRequestDiffsFirstPage(
            at: mergeRequest.route,
            headSHA: "head-sha",
            refreshBehavior: .ifStale
        ) {
            await events.append($0)
        }

        #expect(
            await client.loadedCachePolicies
                == [.mergeRequestDiffs]
        )
        #expect(
            await client.loadedRefreshBehaviors
                == [.ifStale]
        )
        #expect(
            await events.values.map(\.page.items)
                == [[diff]]
        )
    }
}

private extension LiveGitLabMergeRequestLoaderTests {
    actor RecordingMergeRequestClient:
        GitLabPaginatedSessionRequestSending
    {
        let mergeRequest: GitLabMergeRequest
        let diff: GitLabMergeRequestDiffFile
        let returnedNextPageURL: URL?
        private(set) var pageSources: [String] = []
        private(set) var diffPageSources:
            [String] = []
        private(set) var detailPaths: [[String]] = []
        private(set) var loadedCachePolicies:
            [GitLabResponseCachePolicy] = []
        private(set) var loadedRefreshBehaviors:
            [GitLabCacheRefreshBehavior] = []

        init(
            mergeRequest: GitLabMergeRequest,
            diff: GitLabMergeRequestDiffFile,
            returnedNextPageURL: URL?
        ) {
            self.mergeRequest = mergeRequest
            self.diff = diff
            self.returnedNextPageURL = returnedNextPageURL
        }

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            detailPaths.append(endpoint.pathComponents)
            return mergeRequest as! Response
        }

        func sendPage<Response>(
            _ page: GitLabAPIPageRequest<Response>
        ) async throws(GitLabSessionClientError)
            -> GitLabAPIResponse<Response>
        {
            switch page {
            case let .initial(endpoint):
                if endpoint.pathComponents.last == "diffs" {
                    diffPageSources.append(
                        "initial:"
                            + (endpoint.cacheVariant ?? "missing")
                    )
                    return GitLabAPIResponse(
                        value: [diff] as! Response,
                        metadata: GitLabResponseMetadata(
                            nextPageURL:
                                returnedNextPageURL
                        )
                    )
                } else {
                    let scope = endpoint.queryItems.first {
                        $0.name == "scope"
                    }?.value ?? "missing"
                    pageSources.append(
                        "initial:"
                            + endpoint.pathComponents
                                .joined(separator: "/")
                            + ":\(scope)"
                    )
                }
            case let .next(url):
                if url.path.hasSuffix("/diffs") {
                    diffPageSources.append(
                        "next:\(url.absoluteString)"
                    )
                    return GitLabAPIResponse(
                        value: [diff] as! Response,
                        metadata:
                            GitLabResponseMetadata()
                    )
                }
                pageSources.append("next:\(url.absoluteString)")
            }

            return GitLabAPIResponse(
                value: [mergeRequest] as! Response,
                metadata: GitLabResponseMetadata(
                    nextPageURL: returnedNextPageURL
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
            loadedCachePolicies.append(cachePolicy)
            loadedRefreshBehaviors.append(
                refreshBehavior
            )
            let response = try await sendPage(page)
            await onResponse(
                GitLabAPIResponseEvent(
                    value: response.value,
                    metadata: response.metadata,
                    source: .network
                )
            )
        }
    }
}

private actor DiffPageEventRecorder {
    private(set) var values:
        [
            GitLabResourcePageEvent<
                GitLabMergeRequestDiffFile
            >
        ] = []

    func append(
        _ event: GitLabResourcePageEvent<
            GitLabMergeRequestDiffFile
        >
    ) {
        values.append(event)
    }
}
