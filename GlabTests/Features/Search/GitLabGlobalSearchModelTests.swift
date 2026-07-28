import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab global search model")
struct GitLabGlobalSearchModelTests {
    @Test("Ignores an empty query and debounces one normalized search")
    func normalizesAndDebounces() async throws {
        let recorder = SearchRecorder()
        let debounce = DebounceRecorder()
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                scope,
                query,
                nextPageURL in
                await recorder.record(
                    scope: scope,
                    query: query,
                    nextPageURL: nextPageURL
                )
                return emptyPage
            },
            debounce: {
                await debounce.record()
            }
        )

        await model.search("   ")
        #expect(await recorder.calls.isEmpty)
        #expect(await debounce.count == 0)

        await model.search("  review & test  ")

        #expect(await debounce.count == 1)
        #expect(
            Set(await recorder.calls.map(\.scope))
                == Set(GitLabSearchScope.allCases)
        )
        #expect(
            await recorder.calls.allSatisfy {
                $0.query == "review & test"
                    && $0.nextPageURL == nil
            }
        )
        #expect(model.normalizedQuery == "review & test")
    }

    @Test("Loads all first-page scopes concurrently")
    func loadsConcurrently() async throws {
        let gate = SearchConcurrencyGate(
            expectedStarts: 3
        )
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                (
                    scope:
                        GitLabSearchScope,
                    _:
                        String,
                    _:
                        URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabSearchPage in
                await gate.begin(scope)
                await gate.waitForRelease(scope)
                await gate.end()
                return page(for: scope)
            }
        )

        let search = Task {
            await model.search("glab")
        }
        await gate.waitUntilExpectedStarted()

        #expect(await gate.maximumActive == 3)

        await gate.releaseAll()
        await search.value

        for scope in GitLabSearchScope.allCases {
            #expect(
                model.state(for: scope).status
                    == .loaded
            )
            #expect(
                model.state(for: scope)
                    .results.count == 1
            )
        }
    }

    @Test("A late cancelled query cannot replace the current results")
    func rejectsLateStaleResults() async throws {
        let oldQueryGate = SearchConcurrencyGate(
            expectedStarts: 3
        )
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                scope,
                query,
                _ in
                if query == "old" {
                    await oldQueryGate.begin(scope)
                    await oldQueryGate
                        .waitForRelease(scope)
                    await oldQueryGate.end()
                    return page(
                        for: scope,
                        title: "Old"
                    )
                }

                return page(
                    for: scope,
                    title: "Current"
                )
            }
        )

        let oldSearch = Task {
            await model.search("old")
        }
        await oldQueryGate
            .waitUntilExpectedStarted()
        oldSearch.cancel()

        await model.search("current")
        await oldQueryGate.releaseAll()
        await oldSearch.value

        #expect(model.normalizedQuery == "current")
        for scope in GitLabSearchScope.allCases {
            #expect(
                titles(
                    in: model.state(
                        for: scope
                    ).results
                ) == ["Current"]
            )
        }
    }

    @Test("Keeps successful scopes beside unavailable and failed scopes")
    func presentsPartialResults() async throws {
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                (
                    scope:
                        GitLabSearchScope,
                    _:
                        String,
                    _:
                        URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabSearchPage in
                switch scope {
                case .projects:
                    return page(for: scope)
                case .issues:
                    throw GitLabSessionClientError
                        .api(.forbidden)
                case .mergeRequests:
                    throw GitLabSessionClientError
                        .api(
                            .server(statusCode: 500)
                        )
                }
            }
        )

        await model.search("glab")

        #expect(model.hasPartialResults)
        #expect(
            model.state(
                for: GitLabSearchScope.projects
            ).status
                == GitLabSearchScopeStatus.loaded
        )
        #expect(
            model.state(
                for: GitLabSearchScope.issues
            ).status
                == GitLabSearchScopeStatus
                    .unavailable(
                        GitLabSessionClientError
                            .api(.forbidden)
                )
        )
        #expect(
            model.state(
                for:
                    GitLabSearchScope
                        .mergeRequests
            ).status
                == GitLabSearchScopeStatus
                    .failed(
                        GitLabSessionClientError
                            .api(
                                .server(
                                    statusCode: 500
                                )
                            )
                    )
        )
        #expect(model.authenticationFailure == nil)
    }

    @Test("Exposes an authentication failure for the active account")
    func exposesAuthenticationFailure() async throws {
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                (
                    _:
                        GitLabSearchScope,
                    _:
                        String,
                    _:
                        URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabSearchPage in
                throw GitLabSessionClientError
                    .api(.unauthenticated)
            }
        )

        await model.search("glab")

        #expect(
            model.authenticationFailure
                == GitLabSessionClientError
                    .api(.unauthenticated)
        )
        #expect(model.allScopesFailed)
    }

    @Test("Retries every scope after a complete search failure")
    func retriesAllFailedScopes() async throws {
        let attempts = SearchAttemptRecorder()
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                (
                    scope:
                        GitLabSearchScope,
                    _:
                        String,
                    _:
                        URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabSearchPage in
                guard
                    await attempts.record(scope)
                        > 1
                else {
                    throw GitLabSessionClientError
                        .api(
                            .server(
                                statusCode: 500
                            )
                        )
                }
                return page(for: scope)
            }
        )

        await model.search("glab")
        #expect(model.allScopesFailed)

        await model.refresh()

        #expect(!model.allScopesFailed)
        for scope in GitLabSearchScope.allCases {
            #expect(
                model.state(for: scope).status
                    == GitLabSearchScopeStatus
                        .loaded
            )
            #expect(
                await attempts.count(for: scope)
                    == 2
            )
        }
    }

    @Test("Paginates one scope, deduplicates resources, and retains other scopes")
    func paginatesOneScope() async throws {
        let nextPageURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/api/v4/search"
                        + "?scope=projects&search=glab&page=2"
            )
        )
        let recorder = SearchRecorder()
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                scope,
                query,
                after in
                await recorder.record(
                    scope: scope,
                    query: query,
                    nextPageURL: after
                )

                guard scope == .projects else {
                    return emptyPage
                }
                if after == nil {
                    return GitLabSearchPage(
                        results: [
                            projectResult(
                                id: 42,
                                title: "First"
                            ),
                        ],
                        nextPageURL:
                            nextPageURL
                    )
                }
                return GitLabSearchPage(
                    results: [
                        projectResult(
                            id: 42,
                            title: "Duplicate"
                        ),
                        projectResult(
                            id: 43,
                            title: "Second"
                        ),
                    ],
                    nextPageURL: nil
                )
            }
        )

        await model.search("glab")
        await model.loadNextPage(
            for: .projects
        )

        #expect(
            titles(
                in: model.state(
                    for: .projects
                ).results
            ) == ["First", "Second"]
        )
        #expect(
            model.state(for: .projects)
                .nextPageURL == nil
        )
        #expect(
            model.state(for: .issues)
                .results.isEmpty
        )
        #expect(
            await recorder.calls.count(where: {
                $0.nextPageURL == nextPageURL
            }) == 1
        )
    }

    @Test("Bounds recent successful queries and moves a duplicate to the front")
    func maintainsRecentQueries() async throws {
        let model = try makeModel(
            loader: ScriptedSearchLoader {
                _,
                _,
                _ in
                emptyPage
            }
        )

        for query in [
            "one",
            "two",
            "three",
            "four",
            "five",
            "six",
            "three",
        ] {
            await model.search(query)
        }

        #expect(
            model.recentQueries
                == [
                    "three",
                    "six",
                    "five",
                    "four",
                    "two",
                ]
        )
    }
}

private extension GitLabGlobalSearchModelTests {
    func makeModel(
        loader: any GitLabSearchLoading,
        debounce:
            @escaping @Sendable () async throws
                -> Void = {}
    ) throws -> GitLabGlobalSearchModel {
        GitLabGlobalSearchModel(
            accountID: GitLabAccountID(
                host: try GitLabHost(
                    "gitlab.example.com"
                ),
                userID: 1
            ),
            loader: loader,
            debounce: debounce
        )
    }
}

private actor ScriptedSearchLoader:
    GitLabSearchLoading
{
    typealias Handler =
        @Sendable (
            GitLabSearchScope,
            String,
            URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabSearchPage

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func loadPage(
        scope: GitLabSearchScope,
        query: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabSearchPage
    {
        try await handler(
            scope,
            query,
            nextPageURL
        )
    }
}

private actor SearchRecorder {
    struct Call: Sendable {
        let scope: GitLabSearchScope
        let query: String
        let nextPageURL: URL?
    }

    private(set) var calls: [Call] = []

    func record(
        scope: GitLabSearchScope,
        query: String,
        nextPageURL: URL?
    ) {
        calls.append(
            Call(
                scope: scope,
                query: query,
                nextPageURL: nextPageURL
            )
        )
    }
}

private actor SearchAttemptRecorder {
    private var counts:
        [GitLabSearchScope: Int] = [:]

    func record(
        _ scope: GitLabSearchScope
    ) -> Int {
        counts[scope, default: 0] += 1
        return counts[scope, default: 0]
    }

    func count(
        for scope: GitLabSearchScope
    ) -> Int {
        counts[scope, default: 0]
    }
}

private actor DebounceRecorder {
    private(set) var count = 0

    func record() {
        count += 1
    }
}

private actor SearchConcurrencyGate {
    private let expectedStarts: Int
    private var active = 0
    private var startedScopes:
        Set<GitLabSearchScope> = []
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters:
        [
            GitLabSearchScope:
                CheckedContinuation<Void, Never>
        ] = [:]
    private var isReleased = false
    private(set) var maximumActive = 0

    init(expectedStarts: Int) {
        self.expectedStarts = expectedStarts
    }

    func begin(
        _ scope: GitLabSearchScope
    ) {
        active += 1
        maximumActive = max(
            maximumActive,
            active
        )
        startedScopes.insert(scope)

        if startedScopes.count == expectedStarts {
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func waitUntilExpectedStarted() async {
        guard
            startedScopes.count < expectedStarts
        else {
            return
        }

        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func waitForRelease(
        _ scope: GitLabSearchScope
    ) async {
        guard !isReleased else {
            return
        }

        await withCheckedContinuation {
            releaseWaiters[scope] = $0
        }
    }

    func releaseAll() {
        isReleased = true
        let waiters = releaseWaiters.values
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func end() {
        active -= 1
    }
}

private nonisolated let emptyPage =
    GitLabSearchPage(
        results: [],
        nextPageURL: nil
    )

private nonisolated func page(
    for scope: GitLabSearchScope,
    title: String = "Result"
) -> GitLabSearchPage {
    let result: GitLabSearchResult =
        switch scope {
        case .projects:
            projectResult(
                id: 42,
                title: title
            )
        case .issues:
            .issue(
                GitLabIssueSearchResult(
                    id: 101,
                    iid: 7,
                    projectID: 42,
                    title: title,
                    description: nil,
                    state: "opened",
                    confidential: false,
                    labels: [],
                    author: nil,
                    updatedAt: nil,
                    webURL: nil
                )
            )
        case .mergeRequests:
            .mergeRequest(
                GitLabMergeRequestSearchResult(
                    id: 201,
                    iid: 8,
                    projectID: 42,
                    title: title,
                    description: nil,
                    state: "opened",
                    draft: false,
                    legacyWorkInProgress: nil,
                    labels: [],
                    author: nil,
                    updatedAt: nil,
                    webURL: nil
                )
            )
        }

    return GitLabSearchPage(
        results: [result],
        nextPageURL: nil
    )
}

private nonisolated func projectResult(
    id: Int,
    title: String
) -> GitLabSearchResult {
    .project(
        GitLabProjectSearchResult(
            id: id,
            name: title,
            nameWithNamespace:
                "Mobile / \(title)",
            pathWithNamespace:
                "mobile/\(title.lowercased())",
            description: nil,
            webURL: nil,
            avatarURL: nil,
            visibility: nil,
            starCount: nil,
            lastActivityAt: nil
        )
    )
}

private nonisolated func titles(
    in results: [GitLabSearchResult]
) -> [String] {
    results.map {
        switch $0 {
        case let .project(project):
            project.name
        case let .issue(issue):
            issue.title
        case let .mergeRequest(mergeRequest):
            mergeRequest.title
        }
    }
}
