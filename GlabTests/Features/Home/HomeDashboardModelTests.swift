import Foundation
import Testing
@testable import Glab

@Suite("Home dashboard model")
@MainActor
struct HomeDashboardModelTests {
    @Test("Preserves successful sections when other endpoints fail")
    func preservesPartialSuccess() async {
        let issue = workItem(id: "issue-1", title: "Fix dashboard")
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 503)
        )
        let model = HomeDashboardModel(
            loader: QueueDashboardLoader(
                outcomes: [
                    .success(
                        loadResult(
                            successes: [.assignedIssues: [issue]],
                            failure: failure
                        )
                    ),
                ]
            )
        )

        await model.loadIfNeeded()

        #expect(
            model.state(for: .assignedIssues)
                == .loaded([issue])
        )
        #expect(
            model.state(for: .assignedMergeRequests)
                == .failed(failure)
        )
        #expect(!model.hasTotalWorkFailure)
    }

    @Test("Derives a total failure only when every work section fails")
    func derivesTotalFailure() async {
        let failure = GitLabSessionClientError.api(
            .connectivity(.notConnectedToInternet)
        )
        let model = HomeDashboardModel(
            loader: QueueDashboardLoader(
                outcomes: [
                    .success(
                        loadResult(
                            successes: [:],
                            failure: failure
                        )
                    ),
                ]
            )
        )

        await model.loadIfNeeded()

        #expect(model.hasTotalWorkFailure)
        #expect(model.hasLoaded)
        #expect(!model.isLoading)
    }

    @Test("Derives empty rows from successful empty responses")
    func derivesEmptyRows() async {
        let model = HomeDashboardModel(
            loader: QueueDashboardLoader(
                outcomes: [
                    .success(loadResult(successes: allEmptySections())),
                ]
            )
        )

        await model.loadIfNeeded()

        let presentation = model.presentation(
            for: .reviewRequests
        )
        #expect(
            model.state(for: .reviewRequests)
                == .loaded([])
        )
        #expect(presentation.status == .empty)
        #expect(presentation.subtitle == "No open review requests")
        #expect(!model.hasTotalWorkFailure)
    }

    @Test("Refresh replaces each section with the newest response")
    func refreshesSections() async {
        let original = workItem(
            id: "project-1",
            title: "Original project"
        )
        let refreshed = workItem(
            id: "project-2",
            title: "Refreshed project"
        )
        let loader = QueueDashboardLoader(
            outcomes: [
                .success(
                    loadResult(
                        successes: allEmptySections(
                            replacing: [.recentProjects: [original]]
                        )
                    )
                ),
                .success(
                    loadResult(
                        successes: allEmptySections(
                            replacing: [.recentProjects: [refreshed]]
                        )
                    )
                ),
            ]
        )
        let model = HomeDashboardModel(loader: loader)

        await model.loadIfNeeded()
        await model.refresh()

        #expect(
            model.state(for: .recentProjects)
                == .loaded([refreshed])
        )
        #expect(await loader.callCount == 2)
    }

    @Test("Cancellation restores the previous visible state")
    func handlesCancellation() async {
        let model = HomeDashboardModel(
            loader: QueueDashboardLoader(outcomes: [.cancelled])
        )

        await model.loadIfNeeded()

        #expect(
            HomeDashboardSection.allCases.allSatisfy {
                model.state(for: $0) == .idle
            }
        )
        #expect(!model.hasLoaded)
        #expect(!model.isLoading)
    }

    @Test("Uses loaded previews without inferring a total count")
    func derivesPreviewPresentation() async {
        let first = workItem(id: "mr-1", title: "First review")
        let second = workItem(id: "mr-2", title: "Second review")
        let model = HomeDashboardModel(
            loader: QueueDashboardLoader(
                outcomes: [
                    .success(
                        loadResult(
                            successes: allEmptySections(
                                replacing: [
                                    .reviewRequests: [first, second],
                                ]
                            )
                        )
                    ),
                ]
            )
        )

        await model.loadIfNeeded()

        let presentation = model.presentation(
            for: .reviewRequests
        )
        #expect(presentation.status == .content)
        #expect(presentation.subtitle == "First review")
    }
}

private extension HomeDashboardModelTests {
    actor QueueDashboardLoader: HomeDashboardLoading {
        enum Outcome: Sendable {
            case success(HomeDashboardLoadResult)
            case cancelled
        }

        private var outcomes: [Outcome]
        private(set) var callCount = 0

        init(outcomes: [Outcome]) {
            self.outcomes = outcomes
        }

        func load()
            async throws(HomeDashboardLoadingError)
            -> HomeDashboardLoadResult
        {
            callCount += 1
            let outcome = outcomes.removeFirst()

            switch outcome {
            case let .success(result):
                return result
            case .cancelled:
                throw .cancelled
            }
        }
    }

    func loadResult(
        successes: [HomeDashboardSection: [GitLabHomeWorkItem]],
        failure: GitLabSessionClientError = .api(.transport)
    ) -> HomeDashboardLoadResult {
        let user = GitLabAuthenticatedUser(
            id: 42,
            username: "octocat",
            name: "The Octocat",
            avatarURL: nil
        )
        let sections = Dictionary(
            uniqueKeysWithValues: HomeDashboardSection.allCases.map {
                section in
                if let items = successes[section] {
                    return (
                        section,
                        HomeDashboardLoadResult.WorkResult.success(items)
                    )
                }
                return (
                    section,
                    HomeDashboardLoadResult.WorkResult.failure(failure)
                )
            }
        )

        return HomeDashboardLoadResult(
            user: .success(user),
            sections: sections
        )
    }

    func allEmptySections(
        replacing replacements:
            [HomeDashboardSection: [GitLabHomeWorkItem]] = [:]
    ) -> [HomeDashboardSection: [GitLabHomeWorkItem]] {
        Dictionary(
            uniqueKeysWithValues: HomeDashboardSection.allCases.map {
                ($0, replacements[$0] ?? [])
            }
        )
    }

    func workItem(
        id: String,
        title: String
    ) -> GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: id,
            title: title,
            detail: "group/project",
            webURL: nil
        )
    }
}
