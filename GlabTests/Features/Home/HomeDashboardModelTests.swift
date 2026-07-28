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
        #expect(
            model.presentation(for: .assignedMergeRequests).subtitle
                == "GitLab is unavailable"
        )
        #expect(!model.hasTotalWorkFailure)
    }

    @Test("Publishes completed sections while another request is pending")
    func publishesCompletedSectionsIndependently() async {
        let issue = workItem(id: "issue-1", title: "Loaded issue")
        let loader = PausedDashboardLoader(
            result: loadResult(
                successes: allEmptySections(
                    replacing: [.assignedIssues: [issue]]
                )
            )
        )
        let model = HomeDashboardModel(loader: loader)

        let load = Task {
            await model.loadIfNeeded()
        }
        await loader.waitUntilPending()

        #expect(
            model.state(for: .assignedIssues)
                == .loaded([issue])
        )
        #expect(model.state(for: .starredProjects) == .loading)
        #expect(model.isLoading)

        await loader.finish()
        await load.value
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
        #expect(
            await loader.refreshBehaviors
                == [.ifStale, .always]
        )
    }

    @Test("A failed revalidation keeps cached content visible")
    func preservesCachedContentAfterRevalidationFailure() async {
        let cached = workItem(
            id: "project-1",
            title: "Cached project"
        )
        let failure = GitLabSessionClientError.api(
            .server(statusCode: 500)
        )
        let model = HomeDashboardModel(
            loader: RevalidationFailureDashboardLoader(
                section: .recentProjects,
                cachedItems: [cached],
                failure: failure
            )
        )

        await model.loadIfNeeded()

        #expect(
            model.state(for: .recentProjects)
                == .loaded([cached])
        )
        let presentation = model.presentation(
            for: .recentProjects
        )
        #expect(presentation.status == .stale)
        #expect(presentation.subtitle == "Cached project")
        #expect(
            presentation.accessibilityValue
                .contains("Could not refresh")
        )
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

    @Test("Surfaces a session failure that requires authentication")
    func surfacesAuthenticationFailure() async {
        let failure = GitLabSessionClientError.api(.unauthenticated)
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

        #expect(model.authenticationFailure == failure)
    }

    @Test("Reconciles edited resources only into matching loaded previews")
    func reconcilesLoadedEditedResourcePreviews() async {
        let issueItem = workItem(
            id: "issue:42:7",
            title: "Original issue"
        )
        let mergeRequestItem = workItem(
            id: "merge-request:42:8",
            title: "Original merge request"
        )
        let model = HomeDashboardModel(
            loader: QueueDashboardLoader(
                outcomes: [
                    .success(
                        loadResult(
                            successes: allEmptySections(
                                replacing: [
                                    .assignedIssues: [issueItem],
                                    .assignedMergeRequests: [
                                        mergeRequestItem,
                                    ],
                                    .reviewRequests: [
                                        mergeRequestItem,
                                    ],
                                ]
                            )
                        )
                    ),
                ]
            )
        )
        await model.loadIfNeeded()

        model.reconcileEditedResource(
            .issue(
                makeTestIssue(
                    title: "Edited issue"
                )
            )
        )
        model.reconcileEditedResource(
            .mergeRequest(
                makeTestMergeRequest(
                    id: 201,
                    iid: 8,
                    title: "Edited merge request"
                )
            )
        )
        model.reconcileEditedResource(
            .issue(
                makeTestIssue(
                    id: 999,
                    iid: 99,
                    title: "Missing issue"
                )
            )
        )

        #expect(
            model.presentation(for: .assignedIssues).subtitle
                == "Edited issue"
        )
        #expect(
            model.presentation(for: .assignedMergeRequests).subtitle
                == "Edited merge request"
        )
        #expect(
            model.presentation(for: .reviewRequests).subtitle
                == "Edited merge request"
        )
        #expect(
            model.state(for: .recentProjects) == .loaded([])
        )
    }
}

private extension HomeDashboardModelTests {
    struct DashboardSnapshot: Sendable {
        let user: HomeDashboardLoadUpdate.UserResult
        let sections: [
            HomeDashboardSection: HomeDashboardLoadUpdate.WorkResult
        ]
    }

    actor QueueDashboardLoader: HomeDashboardLoading {
        enum Outcome: Sendable {
            case success(DashboardSnapshot)
            case cancelled
        }

        private var outcomes: [Outcome]
        private(set) var callCount = 0
        private(set) var refreshBehaviors:
            [GitLabCacheRefreshBehavior] = []

        init(outcomes: [Outcome]) {
            self.outcomes = outcomes
        }

        func load(
            refreshBehavior: GitLabCacheRefreshBehavior,
            onUpdate:
                @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
        ) async throws(HomeDashboardLoadingError) {
            callCount += 1
            refreshBehaviors.append(refreshBehavior)
            let outcome = outcomes.removeFirst()

            switch outcome {
            case let .success(result):
                await onUpdate(.user(result.user))
                for section in HomeDashboardSection.allCases {
                    guard let sectionResult = result.sections[section] else {
                        continue
                    }
                    await onUpdate(.section(section, sectionResult))
                }
            case .cancelled:
                throw .cancelled
            }
        }
    }

    actor PausedDashboardLoader: HomeDashboardLoading {
        private let result: DashboardSnapshot
        private var continuation: CheckedContinuation<Void, Never>?
        private var isPending = false
        private var pendingWaiters: [CheckedContinuation<Void, Never>] = []

        init(result: DashboardSnapshot) {
            self.result = result
        }

        func load(
            refreshBehavior: GitLabCacheRefreshBehavior,
            onUpdate:
                @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
        ) async throws(HomeDashboardLoadingError) {
            await onUpdate(.user(result.user))
            if let assignedIssues = result.sections[.assignedIssues] {
                await onUpdate(
                    .section(.assignedIssues, assignedIssues)
                )
            }

            isPending = true
            let waiters = pendingWaiters
            pendingWaiters.removeAll()
            waiters.forEach {
                $0.resume()
            }

            await withCheckedContinuation {
                continuation = $0
            }

            for section in HomeDashboardSection.allCases
            where section != .assignedIssues {
                guard let sectionResult = result.sections[section] else {
                    continue
                }
                await onUpdate(.section(section, sectionResult))
            }
        }

        func waitUntilPending() async {
            guard !isPending else {
                return
            }

            await withCheckedContinuation {
                pendingWaiters.append($0)
            }
        }

        func finish() {
            continuation?.resume()
            continuation = nil
        }
    }

    actor RevalidationFailureDashboardLoader:
        HomeDashboardLoading
    {
        let section: HomeDashboardSection
        let cachedItems: [GitLabHomeWorkItem]
        let failure: GitLabSessionClientError

        init(
            section: HomeDashboardSection,
            cachedItems: [GitLabHomeWorkItem],
            failure: GitLabSessionClientError
        ) {
            self.section = section
            self.cachedItems = cachedItems
            self.failure = failure
        }

        func load(
            refreshBehavior: GitLabCacheRefreshBehavior,
            onUpdate:
                @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
        ) async throws(HomeDashboardLoadingError) {
            await onUpdate(
                .section(
                    section,
                    .success(cachedItems)
                )
            )
            await onUpdate(
                .section(
                    section,
                    .failure(failure)
                )
            )
        }
    }

    func loadResult(
        successes: [HomeDashboardSection: [GitLabHomeWorkItem]],
        failure: GitLabSessionClientError = .api(.transport)
    ) -> DashboardSnapshot {
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
                        HomeDashboardLoadUpdate.WorkResult.success(items)
                    )
                }
                return (
                    section,
                    HomeDashboardLoadUpdate.WorkResult.failure(failure)
                )
            }
        )

        return DashboardSnapshot(
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
