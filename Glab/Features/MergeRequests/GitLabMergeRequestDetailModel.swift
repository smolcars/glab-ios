import Observation

nonisolated enum GitLabMergeRequestDetailState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded(GitLabMergeRequest)
    case failed(GitLabSessionClientError)
}

@MainActor
@Observable
final class GitLabMergeRequestDetailModel {
    private(set) var state =
        GitLabMergeRequestDetailState.idle

    private let route: GitLabMergeRequestRoute
    private let loader: any GitLabMergeRequestLoading

    init(
        route: GitLabMergeRequestRoute,
        loader: any GitLabMergeRequestLoading
    ) {
        self.route = route
        self.loader = loader
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
            let mergeRequest = try await loader
                .loadMergeRequest(at: route)
            guard !Task.isCancelled else {
                state = previousState
                return
            }

            state = .loaded(mergeRequest)
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
