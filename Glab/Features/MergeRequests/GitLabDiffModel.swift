import Foundation
import Observation

nonisolated enum GitLabDiffModelState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded(GitLabParsedDiffDocument)
    case failed(String)
}

@MainActor
@Observable
final class GitLabDiffModel {
    private(set) var state =
        GitLabDiffModelState.idle

    private let renderer:
        any GitLabDiffRendering
    private var generation: UInt64 = 0

    init(
        renderer: any GitLabDiffRendering
    ) {
        self.renderer = renderer
    }

    var document: GitLabParsedDiffDocument? {
        guard
            case let .loaded(document) = state
        else {
            return nil
        }
        return document
    }

    func reset() {
        generation &+= 1
        state = .idle
    }

    func load(
        _ request: GitLabDiffRequest
    ) async {
        generation &+= 1
        let loadGeneration = generation
        state = .loading

        do {
            let document =
                try await renderer.render(request)
            guard
                !Task.isCancelled,
                generation == loadGeneration
            else {
                return
            }
            state = .loaded(document)
        } catch is CancellationError {
            guard generation == loadGeneration else {
                return
            }
            state = .idle
        } catch {
            guard generation == loadGeneration else {
                return
            }
            state = .failed(
                error.localizedDescription
            )
        }
    }
}
