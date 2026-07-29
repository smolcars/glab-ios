import Testing
@testable import Glab

@MainActor
@Suite("GitLab issue status refresh coordinator")
struct GitLabIssueStatusRefreshCoordinatorTests {
    @Test(
        "Forwards authoritative issues only after registration"
    )
    func forwardsAfterRegistration() async {
        let coordinator =
            GitLabIssueStatusRefreshCoordinator()
        let recorder = IssueRefreshRecorder()
        let first =
            makeTestIssue(
                iid: 17,
                reference:
                    "group/project#17"
            )
        let second =
            makeTestIssue(
                iid: 18,
                reference:
                    "group/project#18"
            )

        await coordinator
            .refreshAfterIssueMutation(
                first
            )
        #expect(recorder.issues.isEmpty)

        coordinator.register {
            recorder.issues.append($0)
        }
        await coordinator
            .refreshAfterIssueMutation(
                first
            )
        await coordinator
            .refreshAfterIssueMutation(
                second
            )

        #expect(
            recorder.issues
                .map(\.route)
                == [
                    first.route,
                    second.route,
                ]
        )
    }
}

@MainActor
private final class IssueRefreshRecorder {
    var issues: [GitLabIssue] = []
}
