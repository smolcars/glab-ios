import Foundation
import Testing
@testable import Glab

@Suite("GitLab response cache")
struct GitLabResponseCacheTests {
    @Test("Normalizes request query order without exposing cache identity")
    func normalizesKey() throws {
        let account = try account(
            host: "https://gitlab.example.com",
            userID: 42
        )
        let first = GitLabResponseCacheKey(
            account: account,
            requestURL: try #require(
                URL(
                    string:
                        "https://gitlab.example.com/api/v4/issues"
                        + "?state=opened&scope=assigned_to_me"
                )
            )
        )
        let second = GitLabResponseCacheKey(
            account: account,
            requestURL: try #require(
                URL(
                    string:
                        "https://gitlab.example.com/api/v4/issues"
                        + "?scope=assigned_to_me&state=opened"
                )
            )
        )

        #expect(first == second)
        #expect(!first.description.contains("gitlab.example.com"))
        #expect(!first.description.contains("issues"))
    }

    @Test("Separates local variants without exposing them")
    func separatesVariants() throws {
        let account = try account(
            host:
                "https://gitlab.example.com",
            userID: 42
        )
        let requestURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/merge_requests/7/diffs"
            )
        )
        let first = GitLabResponseCacheKey(
            account: account,
            requestURL: requestURL,
            variant: "head-a"
        )
        let same = GitLabResponseCacheKey(
            account: account,
            requestURL: requestURL,
            variant: "head-a"
        )
        let second = GitLabResponseCacheKey(
            account: account,
            requestURL: requestURL,
            variant: "head-b"
        )

        #expect(first == same)
        #expect(first != second)
        #expect(!first.description.contains("head-a"))
        #expect(!second.description.contains("head-b"))
    }

    @Test(
        "Classifies fresh, stale, and expired entries",
        arguments: [
            (
                age: TimeInterval(30),
                expected: GitLabCachedResponseFreshness.fresh
            ),
            (
                age: TimeInterval(90),
                expected: GitLabCachedResponseFreshness.stale
            ),
            (
                age: TimeInterval(3_601),
                expected: GitLabCachedResponseFreshness.expired
            ),
        ]
    )
    func classifiesFreshness(
        age: TimeInterval,
        expected: GitLabCachedResponseFreshness
    ) {
        let now = Date(timeIntervalSince1970: 10_000)
        let response = cachedResponse(
            body: Data("response".utf8),
            storedAt: now.addingTimeInterval(-age)
        )
        let policy = GitLabResponseCachePolicy(
            freshFor: 60,
            maximumAge: 3_600
        )

        #expect(
            response.freshness(
                at: now,
                policy: policy
            ) == expected
        )
    }

    @Test("Persists responses while isolating accounts")
    func persistsAndIsolatesAccounts() async throws {
        try await withTemporaryCache { rootDirectory in
            let firstAccount = try account(
                host: "https://gitlab.example.com",
                userID: 1
            )
            let secondAccount = try account(
                host: "https://gitlab.example.com",
                userID: 2
            )
            let requestURL = try #require(
                URL(
                    string:
                        "https://gitlab.example.com/api/v4/projects"
                )
            )
            let firstKey = GitLabResponseCacheKey(
                account: firstAccount,
                requestURL: requestURL
            )
            let secondKey = GitLabResponseCacheKey(
                account: secondAccount,
                requestURL: requestURL
            )
            let stored = cachedResponse(
                body: Data("private response".utf8)
            )
            let firstStore = FileGitLabResponseCache(
                rootDirectory: rootDirectory
            )

            try await firstStore.store(stored, for: firstKey)

            #expect(
                await firstStore.response(for: secondKey) == nil
            )

            let restoredStore = FileGitLabResponseCache(
                rootDirectory: rootDirectory
            )
            let restored = await restoredStore.response(
                for: firstKey
            )
            #expect(restored?.body == stored.body)
            #expect(restored?.nextPageURL == stored.nextPageURL)
            #expect(restored?.totalCount == stored.totalCount)
        }
    }

    @Test("Treats corrupt entries as misses and removes them")
    func removesCorruptEntries() async throws {
        try await withTemporaryCache { rootDirectory in
            let key = try cacheKey(userID: 9)
            let store = FileGitLabResponseCache(
                rootDirectory: rootDirectory
            )
            try await store.store(
                cachedResponse(body: Data("valid".utf8)),
                for: key
            )
            let cacheFile = try #require(
                cacheFiles(in: rootDirectory).first
            )
            try Data("not a property list".utf8).write(
                to: cacheFile,
                options: .atomic
            )

            #expect(await store.response(for: key) == nil)
            #expect(cacheFiles(in: rootDirectory).isEmpty)
        }
    }

    @Test("Replaces one hashed cache file without exposing request data")
    func replacesResponseAtomically() async throws {
        try await withTemporaryCache { rootDirectory in
            let key = try cacheKey(userID: 10)
            let store = FileGitLabResponseCache(
                rootDirectory: rootDirectory
            )
            try await store.store(
                cachedResponse(body: Data("first".utf8)),
                for: key
            )
            try await store.store(
                cachedResponse(body: Data("replacement".utf8)),
                for: key
            )

            #expect(
                await store.response(for: key)?.body
                    == Data("replacement".utf8)
            )

            let files = cacheFiles(in: rootDirectory)
            #expect(files.count == 1)
            #expect(
                files.allSatisfy {
                    !$0.path.contains("gitlab.example.com")
                        && !$0.path.contains("projects")
                }
            )
        }
    }

    @Test("Updates LRU metadata without rewriting the cached payload")
    func touchesResponseWithoutRewritingPayload() async throws {
        try await withTemporaryCache { rootDirectory in
            let storedAt = Date(
                timeIntervalSince1970: 1_000
            )
            let accessedAt = Date(
                timeIntervalSince1970: 2_000
            )
            let key = try cacheKey(userID: 11)
            let store = FileGitLabResponseCache(
                rootDirectory: rootDirectory,
                currentDate: { accessedAt }
            )
            try await store.store(
                cachedResponse(
                    body: Data("private response".utf8),
                    storedAt: storedAt
                ),
                for: key
            )
            let cacheFile = try #require(
                cacheFiles(in: rootDirectory).first
            )
            let dataBeforeRead = try Data(
                contentsOf: cacheFile
            )

            let restored = await store.response(
                for: key
            )
            let dataAfterRead = try Data(
                contentsOf: cacheFile
            )
            let modificationDate = try cacheFile
                .resourceValues(
                    forKeys: [
                        .contentModificationDateKey,
                    ]
                )
                .contentModificationDate

            #expect(restored?.lastAccessedAt == accessedAt)
            #expect(dataAfterRead == dataBeforeRead)
            #expect(modificationDate == accessedAt)
        }
    }

    @Test("Purges only the selected account")
    func purgesSelectedAccount() async throws {
        try await withTemporaryCache { rootDirectory in
            let firstKey = try cacheKey(userID: 20)
            let secondKey = try cacheKey(userID: 21)
            let store = FileGitLabResponseCache(
                rootDirectory: rootDirectory
            )
            try await store.store(
                cachedResponse(body: Data("first".utf8)),
                for: firstKey
            )
            try await store.store(
                cachedResponse(body: Data("second".utf8)),
                for: secondKey
            )

            await store.removeAll(for: firstKey.account)

            #expect(await store.response(for: firstKey) == nil)
            #expect(
                await store.response(for: secondKey)?.body
                    == Data("second".utf8)
            )
        }
    }

    @Test("Prunes least-recently-used entries to the capacity limit")
    func prunesToCapacity() async throws {
        try await withTemporaryCache { rootDirectory in
            let capacity = 1_500
            let store = FileGitLabResponseCache(
                rootDirectory: rootDirectory,
                capacityBytes: capacity
            )
            let oldest = try cacheKey(userID: 30, path: "oldest")
            let newest = try cacheKey(userID: 30, path: "newest")

            try await store.store(
                cachedResponse(
                    body: Data(repeating: 1, count: 700),
                    storedAt: Date(timeIntervalSince1970: 100)
                ),
                for: oldest
            )
            try await store.store(
                cachedResponse(
                    body: Data(repeating: 2, count: 700),
                    storedAt: Date(timeIntervalSince1970: 200)
                ),
                for: newest
            )

            #expect(await store.response(for: oldest) == nil)
            #expect(await store.response(for: newest) != nil)
            #expect(
                cacheFiles(in: rootDirectory)
                    .reduce(0) { total, url in
                        total + fileSize(at: url)
                    }
                    <= capacity
            )
        }
    }
}

private extension GitLabResponseCacheTests {
    func account(
        host: String,
        userID: Int
    ) throws -> GitLabCacheAccount {
        GitLabCacheAccount(
            host: try GitLabHost(host),
            userID: userID
        )
    }

    func cacheKey(
        userID: Int,
        path: String = "projects"
    ) throws -> GitLabResponseCacheKey {
        let account = try account(
            host: "https://gitlab.example.com",
            userID: userID
        )
        return GitLabResponseCacheKey(
            account: account,
            requestURL: try #require(
                URL(
                    string:
                        "https://gitlab.example.com/api/v4/"
                        + path
                )
            )
        )
    }

    func cachedResponse(
        body: Data,
        storedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> GitLabCachedResponse {
        GitLabCachedResponse(
            body: body,
            nextPageURL: URL(
                string:
                    "https://gitlab.example.com/api/v4/projects"
                    + "?page=2"
            ),
            totalCount: 40,
            entityTag: "\"cache-tag\"",
            lastModified: "Mon, 27 Jul 2026 12:00:00 GMT",
            storedAt: storedAt,
            lastAccessedAt: storedAt
        )
    }

    func withTemporaryCache(
        operation:
            (URL) async throws -> Void
    ) async throws {
        let rootDirectory = FileManager.default.temporaryDirectory
            .appending(
                path: "GlabCacheTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(
                at: rootDirectory
            )
        }
        try await operation(rootDirectory)
    }

    func cacheFiles(in rootDirectory: URL) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [.isRegularFileKey]
            )
        else {
            return []
        }

        return enumerator.compactMap { element in
            guard
                let url = element as? URL,
                (try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                ).isRegularFile) == true
            else {
                return nil
            }
            return url
        }
    }

    func fileSize(at url: URL) -> Int {
        (try? url.resourceValues(
            forKeys: [.fileSizeKey]
        ).fileSize) ?? 0
    }
}
