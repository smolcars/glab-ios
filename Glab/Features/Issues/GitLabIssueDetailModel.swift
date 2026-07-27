import Observation

nonisolated enum GitLabIssueDetailState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded(GitLabIssue)
    case failed(GitLabSessionClientError)
}

@MainActor
@Observable
final class GitLabIssueDetailModel {
    private(set) var state = GitLabIssueDetailState.idle

    private let route: GitLabIssueRoute
    private let loader: any GitLabIssueLoading

    init(
        route: GitLabIssueRoute,
        loader: any GitLabIssueLoading
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
            let issue = try await loader.loadIssue(
                at: route
            )
            guard !Task.isCancelled else {
                state = previousState
                return
            }

            state = .loaded(issue)
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

