import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab deep-link resolution model")
struct GitLabDeepLinkResolutionModelTests {
    @Test("Ignores a route intended for a different account")
    func enforcesAccountGeneration() async throws {
        let activeAccount = try account(
            userID: 1
        )
        let otherAccount = try account(
            userID: 2
        )
        let resolver =
            ImmediateDeepLinkResolver()
        let model =
            GitLabDeepLinkResolutionModel(
                accountID: activeAccount,
                resolver: resolver
            )

        await model.resolve(
            .project(
                pathWithNamespace:
                    "group/project"
            ),
            for: otherAccount,
            sourceURL: try projectURL()
        )

        #expect(model.state == .idle)
        #expect(await resolver.callCount == 0)
    }

    @Test("A late prior lookup cannot replace a newer route")
    func rejectsLateResolution() async throws {
        let accountID = try account(
            userID: 1
        )
        let resolver =
            ControllableDeepLinkResolver()
        let model =
            GitLabDeepLinkResolutionModel(
                accountID: accountID,
                resolver: resolver
            )
        let issueURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/issues/7"
            )
        )
        let projectURL = try projectURL()

        let oldResolution = Task {
            await model.resolve(
                .issue(
                    pathWithNamespace:
                        "group/project",
                    iid: 7
                ),
                for: accountID,
                sourceURL: issueURL
            )
        }
        await resolver.waitUntilBlocked()

        await model.resolve(
            .project(
                pathWithNamespace:
                    "group/current"
            ),
            for: accountID,
            sourceURL: projectURL
        )
        await resolver.release()
        await oldResolution.value

        #expect(
            model.state == .resolved(
                route: .project(
                    GitLabProjectRoute(
                        pathWithNamespace:
                            "group/current"
                    )
                ),
                sourceURL: projectURL
            )
        )
    }

    @Test("Cancellation discards a late result")
    func cancelsResolution() async throws {
        let accountID = try account(
            userID: 1
        )
        let resolver =
            ControllableDeepLinkResolver()
        let model =
            GitLabDeepLinkResolutionModel(
                accountID: accountID,
                resolver: resolver
            )

        let resolution = Task {
            await model.resolve(
                .issue(
                    pathWithNamespace:
                        "group/project",
                    iid: 7
                ),
                for: accountID,
                sourceURL:
                    try projectURL()
            )
        }
        await resolver.waitUntilBlocked()
        model.cancel()
        await resolver.release()
        try await resolution.value

        #expect(model.state == .idle)
    }

    @Test("A lookup failure retains the validated browser fallback")
    func retainsFailureFallback() async throws {
        let accountID = try account(
            userID: 1
        )
        let sourceURL = try projectURL()
        let model =
            GitLabDeepLinkResolutionModel(
                accountID: accountID,
                resolver:
                    FailingDeepLinkResolver()
            )

        await model.resolve(
            .issue(
                pathWithNamespace:
                    "group/project",
                iid: 7
            ),
            for: accountID,
            sourceURL: sourceURL
        )

        #expect(
            model.state == .failed(
                sourceURL: sourceURL,
                error: .api(.notFound)
            )
        )
    }
}

private extension GitLabDeepLinkResolutionModelTests {
    func account(
        userID: Int
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(
                "gitlab.example.com"
            ),
            userID: userID
        )
    }

    func projectURL() throws -> URL {
        try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project"
            )
        )
    }
}

private actor ImmediateDeepLinkResolver:
    GitLabDeepLinkRouteResolving
{
    private(set) var callCount = 0

    func resolve(
        _ target: GitLabDeepLinkTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabNativeRoute
    {
        callCount += 1
        return .project(
            GitLabProjectRoute(
                pathWithNamespace:
                    "group/project"
            )
        )
    }
}

private actor ControllableDeepLinkResolver:
    GitLabDeepLinkRouteResolving
{
    private var blockedContinuation:
        CheckedContinuation<Void, Never>?
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var isBlocked = false
    private var isReleased = false

    func resolve(
        _ target: GitLabDeepLinkTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabNativeRoute
    {
        switch target {
        case let .project(path):
            return .project(
                GitLabProjectRoute(
                    pathWithNamespace: path
                )
            )
        case .issue:
            isBlocked = true
            let waiters = startWaiters
            startWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
            if !isReleased {
                await withCheckedContinuation {
                    blockedContinuation = $0
                }
            }
            return .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
        case .mergeRequest:
            return .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 8
                )
            )
        case let .repositoryFile(
            _,
            ref,
            path
        ):
            return .repositoryFile(
                GitLabRepositoryFileRoute(
                    projectID: 42,
                    projectWebURL: nil,
                    ref: ref,
                    path: path,
                    blobID: nil
                )
            )
        }
    }

    func waitUntilBlocked() async {
        guard !isBlocked else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func release() {
        isReleased = true
        blockedContinuation?.resume()
        blockedContinuation = nil
    }
}

private struct FailingDeepLinkResolver:
    GitLabDeepLinkRouteResolving
{
    func resolve(
        _ target: GitLabDeepLinkTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabNativeRoute
    {
        throw .api(.notFound)
    }
}
