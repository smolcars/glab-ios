import Foundation
import Observation

nonisolated enum GitLabResourceDetailState<Resource>:
    Equatable,
    Sendable
where Resource: Equatable & Sendable {
    case idle
    case loading
    case loaded(Resource)
    case failed(GitLabSessionClientError)
}

@MainActor
@Observable
final class GitLabResourceDetailModel<Resource, Route>
where
    Resource: Equatable & Sendable,
    Route: Sendable
{
    private(set) var state =
        GitLabResourceDetailState<Resource>.idle
    private(set) var refreshError:
        GitLabSessionClientError?
    private(set) var resourceSource:
        GitLabAPIResponseSource?
    private(set) var cacheStoredAt: Date?

    private let route: Route
    private let loadResource:
        @Sendable (Route) async throws(GitLabSessionClientError)
            -> Resource
    private let loadResourceEvents:
        (@Sendable (
            Route,
            GitLabCacheRefreshBehavior,
            @escaping @Sendable (
                GitLabAPIResponseEvent<Resource>
            ) async -> Void
        ) async throws(GitLabSessionClientError) -> Void)?

    init(
        route: Route,
        loadResource: @escaping @Sendable (Route) async throws(
            GitLabSessionClientError
        ) -> Resource,
        loadResourceEvents:
            (@Sendable (
                Route,
                GitLabCacheRefreshBehavior,
                @escaping @Sendable (
                    GitLabAPIResponseEvent<Resource>
                ) async -> Void
            ) async throws(GitLabSessionClientError) -> Void)? = nil
    ) {
        self.route = route
        self.loadResource = loadResource
        self.loadResourceEvents = loadResourceEvents
    }

    var authenticationFailure: GitLabSessionClientError? {
        if
            refreshError?
                .requiresReauthentication == true
        {
            return refreshError
        }
        guard
            case let .failed(error) = state,
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }

    func loadIfNeeded() async {
        guard state == .idle else {
            return
        }
        await load()
    }

    func retry() async {
        await load()
    }

    private func load() async {
        guard state != .loading else {
            return
        }

        let previousState = state
        let previousRefreshError = refreshError
        let previousResourceSource = resourceSource
        let previousCacheStoredAt = cacheStoredAt
        if case .loaded = previousState {
            state = previousState
        } else {
            state = .loading
        }
        refreshError = nil

        do {
            if let loadResourceEvents {
                try await loadResourceEvents(
                    route,
                    previousState == .idle
                        ? .ifStale
                        : .always
                ) { [weak self] event in
                    await self?.apply(event)
                }
            } else {
                let resource = try await loadResource(
                    route
                )
                apply(
                    GitLabAPIResponseEvent(
                        value: resource,
                        metadata:
                            GitLabResponseMetadata(),
                        source: .network
                    )
                )
            }

            guard !Task.isCancelled else {
                state = previousState
                refreshError =
                    previousRefreshError
                resourceSource =
                    previousResourceSource
                cacheStoredAt =
                    previousCacheStoredAt
                return
            }
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                state = previousState
                refreshError =
                    previousRefreshError
                resourceSource =
                    previousResourceSource
                cacheStoredAt =
                    previousCacheStoredAt
                return
            }

            if case .loaded = state {
                refreshError = error
            } else {
                state = .failed(error)
            }
        }
    }

    private func apply(
        _ event: GitLabAPIResponseEvent<Resource>
    ) {
        state = .loaded(event.value)
        refreshError = nil
        resourceSource = event.source
        cacheStoredAt = event.cacheStoredAt
    }
}
