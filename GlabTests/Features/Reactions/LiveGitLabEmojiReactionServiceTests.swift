import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab emoji reaction service")
struct LiveGitLabEmojiReactionServiceTests {
    @Test("Loads initial, cached, and next reaction pages")
    func loadsPages() async throws {
        let award = makeTestEmojiAward()
        let nextURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/issues/7/award_emoji"
                    + "?page=2&per_page=100"
            )
        )
        let client = RecordingReactionClient(
            award: award,
            nextPageURL: nextURL
        )
        let service =
            LiveGitLabEmojiReactionService(
                client: client
            )

        let first = try await service
            .loadReactionsPage(
                for: testIssueAwardable,
                after: nil
            )
        let next = try await service
            .loadReactionsPage(
                for: testIssueAwardable,
                after: nextURL
            )
        let collector =
            ReactionPageEventCollector()
        try await service
            .loadReactionsFirstPage(
                for: testIssueAwardable,
                refreshBehavior: .ifStale
            ) {
                await collector.append($0)
            }

        #expect(first.items == [award])
        #expect(first.nextPageURL == nextURL)
        #expect(first.totalCount == 101)
        #expect(next.items == [award])
        #expect(
            await collector.events
                .map(\.page.items)
                == [[award]]
        )
        #expect(
            await client.cachePolicies
                == [.reactions]
        )
        #expect(
            await client.refreshBehaviors
                == [.ifStale]
        )
    }

    @Test("Adds and removes exact awards with target-local invalidation")
    func mutatesAwards() async throws {
        let award = makeTestEmojiAward(
            id: 404,
            name: "heart"
        )
        let client = RecordingReactionClient(
            award: award,
            nextPageURL: nil
        )
        let service =
            LiveGitLabEmojiReactionService(
                client: client
            )

        let created = try await service.addReaction(
            named: "heart",
            to: testIssueAwardable
        )
        try await service.removeReaction(
            awardID: created.id,
            from: testIssueAwardable
        )

        #expect(created == award)
        #expect(
            await client.sentMethods
                == [.post, .delete]
        )
        #expect(
            await client.sentPaths
                == [
                    "projects/42/issues/7/award_emoji",
                    "projects/42/issues/7/award_emoji/404",
                ]
        )
        #expect(
            await client.invalidatedPaths
                == [
                    "projects/42/issues/7/award_emoji",
                    "projects/42/issues/7/award_emoji",
                ]
        )
    }

    @Test("Leaves cached reactions after mutation failure")
    func leavesCacheAfterFailure() async {
        let failure =
            GitLabSessionClientError
                .api(
                    .validation(statusCode: 422)
                )
        let client = RecordingReactionClient(
            award: makeTestEmojiAward(),
            nextPageURL: nil,
            mutationFailure: failure
        )
        let service =
            LiveGitLabEmojiReactionService(
                client: client
            )

        await #expect(throws: failure) {
            try await service.addReaction(
                named: "thumbsup",
                to: testIssueAwardable
            )
        }

        #expect(
            await client.invalidatedPaths
                .isEmpty
        )
    }
}

private actor RecordingReactionClient:
    GitLabPaginatedSessionRequestSending
{
    let award: GitLabEmojiAward
    let nextPageURL: URL?
    let mutationFailure:
        GitLabSessionClientError?

    private(set) var cachePolicies:
        [GitLabResponseCachePolicy] = []
    private(set) var refreshBehaviors:
        [GitLabCacheRefreshBehavior] = []
    private(set) var sentMethods:
        [GitLabHTTPMethod] = []
    private(set) var sentPaths: [String] = []
    private(set) var invalidatedPaths:
        [String] = []

    init(
        award: GitLabEmojiAward,
        nextPageURL: URL?,
        mutationFailure:
            GitLabSessionClientError? = nil
    ) {
        self.award = award
        self.nextPageURL = nextPageURL
        self.mutationFailure = mutationFailure
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sentMethods.append(endpoint.method)
        sentPaths.append(
            endpoint.pathComponents
                .joined(separator: "/")
        )
        if let mutationFailure {
            throw mutationFailure
        }
        if Response.self
            == GitLabEmojiAward.self
        {
            return award as! Response
        }
        if Response.self
            == GitLabEmptyResponse.self
        {
            return GitLabEmptyResponse()
                as! Response
        }
        throw .api(.invalidResponse)
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        GitLabAPIResponse(
            value: [award] as! Response,
            metadata: GitLabResponseMetadata(
                nextPageURL: nextPageURL,
                totalCount: 101
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
        cachePolicies.append(cachePolicy)
        refreshBehaviors.append(
            refreshBehavior
        )
        await onResponse(
            GitLabAPIResponseEvent(
                value: [award] as! Response,
                metadata:
                    GitLabResponseMetadata(
                        nextPageURL:
                            nextPageURL,
                        totalCount: 101
                    ),
                source: .cache(.stale)
            )
        )
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) {
        invalidatedPaths.append(
            endpoint.pathComponents
                .joined(separator: "/")
        )
    }
}

private actor ReactionPageEventCollector {
    private(set) var events:
        [
            GitLabResourcePageEvent<
                GitLabEmojiAward
            >
        ] = []

    func append(
        _ event:
            GitLabResourcePageEvent<
                GitLabEmojiAward
            >
    ) {
        events.append(event)
    }
}
