@MainActor
final class GitLabIssueStatusRefreshCoordinator {
    private var refresh:
        (@MainActor (GitLabIssue) async -> Void)?

    func register(
        refresh:
            @escaping @MainActor (
                GitLabIssue
            ) async -> Void
    ) {
        self.refresh = refresh
    }

    func refreshAfterIssueMutation(
        _ issue: GitLabIssue
    ) async {
        await refresh?(issue)
    }
}
