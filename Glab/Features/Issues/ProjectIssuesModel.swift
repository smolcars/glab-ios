import Foundation
import Observation

typealias GitLabProjectIssuesPageModel =
    GitLabPaginatedResourceModel<
        GitLabIssue,
        GitLabIssueRoute
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabIssue,
    Identity == GitLabIssueRoute
{
    convenience init(
        projectID: Int,
        state: GitLabProjectIssueState,
        loader: any GitLabIssueLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabIssue
                > in
                try await loader
                    .loadProjectIssuesPage(
                        projectID: projectID,
                        state: state,
                        after: nextPageURL
                    )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabIssue
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadProjectIssuesFirstPage(
                        projectID: projectID,
                        state: state,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: { $0.route },
            searchValues: {
                [
                    $0.title,
                    $0.references.short,
                    $0.references.full,
                ]
                    + $0.labels
                    + $0.assignees.flatMap {
                        [$0.name, $0.username]
                    }
            }
        )
    }
}

@MainActor
@Observable
final class ProjectIssuesModel {
    var selectedState =
        GitLabProjectIssueState.opened
    {
        didSet {
            activateSelectedState()
        }
    }

    private(set) var activeModel:
        GitLabProjectIssuesPageModel
    @ObservationIgnored
    private let projectID: Int
    @ObservationIgnored
    private let loader:
        any GitLabIssueLoading
    @ObservationIgnored
    private var cachedModels: [
        GitLabProjectIssueState:
            GitLabProjectIssuesPageModel
    ]

    init(
        projectID: Int,
        loader: any GitLabIssueLoading
    ) {
        let model =
            GitLabProjectIssuesPageModel(
                projectID: projectID,
                state: .opened,
                loader: loader
            )
        self.projectID = projectID
        self.loader = loader
        activeModel = model
        cachedModels = [.opened: model]
    }

    func reconcileCreatedIssue(
        _ issue: GitLabIssue
    ) {
        guard issue.projectID == projectID else {
            return
        }
        let targetState =
            GitLabProjectIssueState.allCases
                .first {
                    $0.contains(issue)
                }
                ?? .opened
        for (state, model) in cachedModels
        where state != targetState {
            _ = model.removeItemIfPresent(
                issue
            )
        }
        model(for: targetState)
            .reconcileItemAtStart(
                issue,
                countAdjustmentIfInserted: 1
            )
    }

    func reconcileEditedIssue(
        _ issue: GitLabIssue
    ) {
        guard issue.projectID == projectID else {
            return
        }
        guard
            let targetState =
                GitLabProjectIssueState
                .allCases
                .first(where: {
                    $0.contains(issue)
                })
        else {
            for model in cachedModels.values {
                _ = model
                    .reconcileItemIfPresent(
                        issue
                    )
            }
            return
        }

        var movedBetweenStates = false
        for (state, model) in cachedModels
        where state != targetState {
            movedBetweenStates =
                model.removeItemIfPresent(
                    issue
                )
                || movedBetweenStates
        }

        guard
            let targetModel =
                cachedModels[targetState]
        else {
            return
        }
        if
            !targetModel
                .reconcileItemIfPresent(
                    issue
                ),
            movedBetweenStates,
            targetModel.hasLoaded
        {
            targetModel
                .reconcileItemAtStart(
                    issue,
                    countAdjustmentIfInserted: 1
                )
        }
    }

    func model(
        for state: GitLabProjectIssueState
    ) -> GitLabProjectIssuesPageModel {
        if let model = cachedModels[state] {
            return model
        }
        let model =
            GitLabProjectIssuesPageModel(
                projectID: projectID,
                state: state,
                loader: loader
            )
        cachedModels[state] = model
        return model
    }

    private func activateSelectedState() {
        activeModel = model(
            for: selectedState
        )
    }
}
