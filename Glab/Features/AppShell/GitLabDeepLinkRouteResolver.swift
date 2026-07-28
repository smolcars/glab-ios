import Foundation
import Observation

nonisolated enum GitLabNativeRoute:
    Equatable,
    Hashable,
    Sendable
{
    case project(GitLabProjectRoute)
    case issue(GitLabIssueRoute)
    case mergeRequest(
        GitLabMergeRequestRoute
    )
}

nonisolated protocol
    GitLabDeepLinkRouteResolving:
    Sendable
{
    func resolve(
        _ target: GitLabDeepLinkTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabNativeRoute
}

nonisolated struct
    GitLabDeepLinkRouteResolver:
    GitLabDeepLinkRouteResolving,
    Sendable
{
    private let projectLoader:
        any GitLabProjectResolving

    init(
        projectLoader:
            any GitLabProjectResolving
    ) {
        self.projectLoader = projectLoader
    }

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
        case let .issue(path, iid):
            let project =
                try await projectLoader
                    .loadProject(
                        pathWithNamespace:
                            path
                    )
            return .issue(
                GitLabIssueRoute(
                    projectID: project.id,
                    issueIID: iid
                )
            )
        case let .mergeRequest(path, iid):
            let project =
                try await projectLoader
                    .loadProject(
                        pathWithNamespace:
                            path
                    )
            return .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: project.id,
                    mergeRequestIID: iid
                )
            )
        }
    }
}

nonisolated enum
    GitLabDeepLinkResolutionState:
    Equatable,
    Sendable
{
    case idle
    case resolving(sourceURL: URL)
    case resolved(
        route: GitLabNativeRoute,
        sourceURL: URL
    )
    case failed(
        sourceURL: URL,
        error: GitLabSessionClientError
    )
}

@MainActor
@Observable
final class GitLabDeepLinkResolutionModel {
    let accountID: GitLabAccountID

    private(set) var state =
        GitLabDeepLinkResolutionState.idle

    private let resolver:
        any GitLabDeepLinkRouteResolving
    private var requestGeneration = 0

    init(
        accountID: GitLabAccountID,
        resolver:
            any GitLabDeepLinkRouteResolving
    ) {
        self.accountID = accountID
        self.resolver = resolver
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .failed(_, error) =
                state,
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }

    func resolve(
        _ target: GitLabDeepLinkTarget,
        for expectedAccountID:
            GitLabAccountID,
        sourceURL: URL
    ) async {
        guard
            expectedAccountID == accountID
        else {
            return
        }

        requestGeneration &+= 1
        let generation = requestGeneration
        state = .resolving(
            sourceURL: sourceURL
        )

        do {
            let route =
                try await resolver.resolve(
                    target
                )
            guard
                requestGeneration
                    == generation
            else {
                return
            }
            guard !Task.isCancelled else {
                state = .idle
                return
            }

            state = .resolved(
                route: route,
                sourceURL: sourceURL
            )
        } catch {
            guard
                requestGeneration
                    == generation
            else {
                return
            }
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                state = .idle
                return
            }

            state = .failed(
                sourceURL: sourceURL,
                error: error
            )
        }
    }

    func cancel() {
        requestGeneration &+= 1
        state = .idle
    }
}
