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

    private let route: Route
    private let loadResource:
        @Sendable (Route) async throws(GitLabSessionClientError)
            -> Resource

    init(
        route: Route,
        loadResource: @escaping @Sendable (Route) async throws(
            GitLabSessionClientError
        ) -> Resource
    ) {
        self.route = route
        self.loadResource = loadResource
    }

    var authenticationFailure: GitLabSessionClientError? {
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
        state = .loading

        do {
            let resource = try await loadResource(route)
            guard !Task.isCancelled else {
                state = previousState
                return
            }

            state = .loaded(resource)
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                state = previousState
                return
            }

            state = .failed(error)
        }
    }
}
