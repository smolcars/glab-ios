import Foundation
import Testing
@testable import Glab

@Suite("GitLab session response caching")
struct GitLabSessionClientCacheTests {
    @Test("A fresh cache hit publishes without using the transport")
    func freshCacheSkipsNetwork() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let fixture = try makeFixture(
            cache: cache,
            currentDate: { now }
        )
        try await cache.store(
            cachedResponse(
                value: "cached",
                storedAt: now.addingTimeInterval(-30)
            ),
            for: fixture.cacheKey
        )
        let events =
            APIResponseEventCollector<TestResponse>()

        try await fixture.client.loadResponse(
            fixture.request,
            cachePolicy: cachePolicy,
            refreshBehavior: .ifStale
        ) {
            await events.append($0)
        }

        #expect(await fixture.transport.requestCount == 0)
        #expect(
            await events.values.map(\.value.value)
                == ["cached"]
        )
        #expect(
            await events.values.map(\.source)
                == [.cache(.fresh)]
        )
        #expect(
            await events.values.map(\.cacheStoredAt)
                == [now.addingTimeInterval(-30)]
        )
    }

    @Test("A stale cache hit publishes before one request completes")
    func staleCacheRevalidatesOnce() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let transport = GatedCacheTransport(
            outcome: .success("remote")
        )
        let fixture = try makeFixture(
            transport: transport,
            cache: cache,
            currentDate: { now }
        )
        try await cache.store(
            cachedResponse(
                value: "cached",
                storedAt: now.addingTimeInterval(-90)
            ),
            for: fixture.cacheKey
        )
        let events =
            APIResponseEventCollector<TestResponse>()

        let load = Task {
            try await fixture.client.loadResponse(
                fixture.request,
                cachePolicy: cachePolicy,
                refreshBehavior: .ifStale
            ) {
                await events.append($0)
            }
        }
        await transport.waitUntilRequested()

        #expect(
            await events.values.map(\.value.value)
                == ["cached"]
        )

        await transport.release()
        try await load.value

        #expect(await transport.requestCount == 1)
        #expect(
            await events.values.map(\.value.value)
                == ["cached", "remote"]
        )
        #expect(
            await events.values.map(\.source)
                == [.cache(.stale), .network]
        )
    }

    @Test("A stale cache hit remains available when revalidation fails")
    func staleCacheSurvivesFailure() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let transport = GatedCacheTransport(
            outcome: .offline
        )
        let fixture = try makeFixture(
            transport: transport,
            cache: cache,
            currentDate: { now }
        )
        try await cache.store(
            cachedResponse(
                value: "cached",
                storedAt: now.addingTimeInterval(-90)
            ),
            for: fixture.cacheKey
        )
        let events =
            APIResponseEventCollector<TestResponse>()

        let load = Task {
            try await fixture.client.loadResponse(
                fixture.request,
                cachePolicy: cachePolicy,
                refreshBehavior: .ifStale
            ) {
                await events.append($0)
            }
        }
        await transport.waitUntilRequested()
        await transport.release()

        await #expect(
            throws:
                GitLabSessionClientError.api(
                    .connectivity(
                        .notConnectedToInternet
                    )
                )
        ) {
            try await load.value
        }
        #expect(
            await events.values.map(\.value.value)
                == ["cached"]
        )
        #expect(
            await cache.response(
                for: fixture.cacheKey
            )?.body
                == cachedResponse(
                    value: "cached",
                    storedAt:
                        now.addingTimeInterval(-90)
                ).body
        )
    }

    @Test("An expired entry is removed and replaced from the network")
    func expiredEntryReloads() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let fixture = try makeFixture(
            cache: cache,
            currentDate: { now }
        )
        try await cache.store(
            cachedResponse(
                value: "expired",
                storedAt:
                    now.addingTimeInterval(-3_601)
            ),
            for: fixture.cacheKey
        )
        let events =
            APIResponseEventCollector<TestResponse>()

        try await fixture.client.loadResponse(
            fixture.request,
            cachePolicy: cachePolicy,
            refreshBehavior: .ifStale
        ) {
            await events.append($0)
        }

        #expect(await fixture.transport.requestCount == 1)
        #expect(
            await events.values.map(\.value.value)
                == ["network"]
        )
        #expect(
            await events.values.map(\.source)
                == [.network]
        )
        #expect(
            await cache.response(
                for: fixture.cacheKey
            )?.storedAt == now
        )
    }

    @Test("An undecodable cache entry self-heals through the network")
    func undecodableEntryReloads() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let fixture = try makeFixture(
            cache: cache,
            currentDate: { now }
        )
        try await cache.store(
            GitLabCachedResponse(
                body: Data("not json".utf8),
                nextPageURL: nil,
                totalCount: nil,
                entityTag: nil,
                lastModified: nil,
                storedAt: now,
                lastAccessedAt: now
            ),
            for: fixture.cacheKey
        )
        let events =
            APIResponseEventCollector<TestResponse>()

        try await fixture.client.loadResponse(
            fixture.request,
            cachePolicy: cachePolicy,
            refreshBehavior: .ifStale
        ) {
            await events.append($0)
        }

        #expect(await fixture.transport.requestCount == 1)
        #expect(
            await events.values.map(\.value.value)
                == ["network"]
        )
        #expect(
            await cache.response(
                for: fixture.cacheKey
            )?.body
                == cachedResponse(
                    value: "network",
                    storedAt: now
                ).body
        )
    }

    @Test("Forced refresh bypasses a fresh entry but retains it on failure")
    func forcedRefreshBypassesFreshEntry() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let transport = GatedCacheTransport(
            outcome: .offline
        )
        let fixture = try makeFixture(
            transport: transport,
            cache: cache,
            currentDate: { now }
        )
        let stored = cachedResponse(
            value: "cached",
            storedAt: now.addingTimeInterval(-10)
        )
        try await cache.store(
            stored,
            for: fixture.cacheKey
        )
        let events =
            APIResponseEventCollector<TestResponse>()

        let load = Task {
            try await fixture.client.loadResponse(
                fixture.request,
                cachePolicy: cachePolicy,
                refreshBehavior: .always
            ) {
                await events.append($0)
            }
        }
        await transport.waitUntilRequested()
        await transport.release()

        await #expect(
            throws:
                GitLabSessionClientError.api(
                    .connectivity(
                        .notConnectedToInternet
                    )
                )
        ) {
            try await load.value
        }
        #expect(await events.values.isEmpty)
        #expect(
            await cache.response(
                for: fixture.cacheKey
            )?.body == stored.body
        )
    }

    @Test("Invalidation removes only the selected request")
    func invalidatesSelectedRequest() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let cache = InMemoryGitLabResponseCache(
            currentDate: { now }
        )
        let fixture = try makeFixture(
            cache: cache,
            currentDate: { now }
        )
        let otherKey = GitLabResponseCacheKey(
            account: fixture.cacheKey.account,
            requestURL: try #require(
                URL(
                    string:
                        "https://gitlab.example.com/api/v4/issues"
                )
            )
        )
        let response = cachedResponse(
            value: "cached",
            storedAt: now
        )
        try await cache.store(
            response,
            for: fixture.cacheKey
        )
        try await cache.store(
            response,
            for: otherKey
        )

        await fixture.client.invalidateCachedResponse(
            fixture.request
        )

        #expect(
            await cache.response(
                for: fixture.cacheKey
            ) == nil
        )
        #expect(
            await cache.response(
                for: otherKey
            ) != nil
        )
    }
}

private extension GitLabSessionClientCacheTests {
    nonisolated struct TestResponse:
        Decodable,
        Equatable,
        Sendable
    {
        let value: String
    }

    struct Fixture {
        let client: GitLabSessionClient<
            GatedCacheTransport,
            UnusedTokenExchanger
        >
        let transport: GatedCacheTransport
        let request: GitLabAPIRequest<TestResponse>
        let cacheKey: GitLabResponseCacheKey
    }

    var cachePolicy: GitLabResponseCachePolicy {
        GitLabResponseCachePolicy(
            freshFor: 60,
            maximumAge: 3_600
        )
    }

    func makeFixture(
        transport: GatedCacheTransport =
            GatedCacheTransport(
                outcome: .success("network"),
                startsReleased: true
            ),
        cache: any GitLabResponseCaching,
        currentDate:
            @escaping @Sendable () -> Date
    ) throws -> Fixture {
        let session = try GitLabStoredSession(
            host: GitLabHost(
                "gitlab.example.com"
            ),
            user: GitLabUserSummary(
                id: 42,
                username: "octocat",
                name: "The Octocat",
                avatarURL: nil
            ),
            oauthApplicationID: nil,
            personalAccessTokenMetadata:
                GitLabPersonalAccessTokenMetadata(
                    scopes: ["api"],
                    expiresOn: nil
                ),
            credential:
                GitLabCredential.personalAccessToken(
                    "pat-secret"
                )
        )
        let request =
            GitLabAPIRequest<TestResponse>.get(
                requires: .read,
                path: ["projects"]
            )
        let requestURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/projects"
            )
        )

        return Fixture(
            client: GitLabSessionClient(
                session: session,
                transport: transport,
                tokenExchanger:
                    UnusedTokenExchanger(),
                credentialStore:
                    InMemoryGitLabCredentialStore(
                        session: session
                    ),
                responseCache: cache,
                currentDate: currentDate
            ),
            transport: transport,
            request: request,
            cacheKey: GitLabResponseCacheKey(
                account:
                    GitLabCacheAccount(
                        session: session
                    ),
                requestURL: requestURL
            )
        )
    }

    func cachedResponse(
        value: String,
        storedAt: Date
    ) -> GitLabCachedResponse {
        GitLabCachedResponse(
            body: Data(
                #"{"value":"\#(value)"}"#.utf8
            ),
            nextPageURL: nil,
            totalCount: nil,
            entityTag: nil,
            lastModified: nil,
            storedAt: storedAt,
            lastAccessedAt: storedAt
        )
    }

    actor APIResponseEventCollector<Value>
    where Value: Sendable {
        private(set) var values:
            [GitLabAPIResponseEvent<Value>] = []

        func append(
            _ event: GitLabAPIResponseEvent<Value>
        ) {
            values.append(event)
        }
    }

    actor GatedCacheTransport:
        GitLabHTTPTransport
    {
        enum Outcome: Sendable {
            case success(String)
            case offline
        }

        private let outcome: Outcome
        private var isReleased: Bool
        private var continuation:
            CheckedContinuation<Void, Never>?
        private var requestWaiters:
            [CheckedContinuation<Void, Never>] = []
        private(set) var requestCount = 0

        init(
            outcome: Outcome,
            startsReleased: Bool = false
        ) {
            self.outcome = outcome
            isReleased = startsReleased
        }

        func data(
            for request: URLRequest
        ) async throws -> (Data, URLResponse) {
            requestCount += 1
            let waiters = requestWaiters
            requestWaiters.removeAll()
            waiters.forEach {
                $0.resume()
            }

            if !isReleased {
                await withCheckedContinuation {
                    continuation = $0
                }
            }

            switch outcome {
            case let .success(value):
                return (
                    Data(
                        #"{"value":"\#(value)"}"#.utf8
                    ),
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: 200,
                        httpVersion: "HTTP/2",
                        headerFields: nil
                    )!
                )
            case .offline:
                throw URLError(
                    .notConnectedToInternet
                )
            }
        }

        func waitUntilRequested() async {
            guard requestCount == 0 else {
                return
            }
            await withCheckedContinuation {
                requestWaiters.append($0)
            }
        }

        func release() {
            isReleased = true
            continuation?.resume()
            continuation = nil
        }
    }

    actor UnusedTokenExchanger:
        GitLabOAuthTokenExchanging
    {
        func exchangeAuthorizationCode(
            configuration:
                GitLabOAuthConfiguration,
            code: String,
            codeVerifier: String
        ) async throws(GitLabOAuthTokenError)
            -> GitLabCredential
        {
            throw .invalidGrant
        }

        func refresh(
            configuration:
                GitLabOAuthConfiguration,
            refreshToken: String
        ) async throws(GitLabOAuthTokenError)
            -> GitLabCredential
        {
            throw .invalidGrant
        }
    }
}
