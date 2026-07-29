import Foundation

@MainActor
final class GitLabPipelineAccountScope {
    private let isCurrent:
        @MainActor () -> Bool

    init(
        isCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.isCurrent = isCurrent
    }

    func check() -> Bool {
        isCurrent()
    }
}
