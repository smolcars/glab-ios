import Foundation
import Observation

typealias GitLabProjectMergeRequestsPageModel =
    GitLabPaginatedResourceModel<
        GitLabMergeRequest,
        GitLabMergeRequestRoute
    >

extension GitLabPaginatedResourceModel
where
    Item == GitLabMergeRequest,
    Identity == GitLabMergeRequestRoute
{
    convenience init(
        projectID: Int,
        state: GitLabProjectMergeRequestState,
        loader: any GitLabMergeRequestLoading
    ) {
        self.init(
            loadPage: {
                (nextPageURL: URL?) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabMergeRequest
                > in
                try await loader
                    .loadProjectMergeRequestsPage(
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
                                GitLabMergeRequest
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await loader
                    .loadProjectMergeRequestsFirstPage(
                        projectID: projectID,
                        state: state,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: { $0.route },
            searchValues: {
                let users =
                    [$0.author]
                    + $0.assignees
                    + $0.reviewers
                return [
                    $0.title,
                    $0.references.short,
                    $0.references.full,
                    $0.sourceBranch,
                    $0.targetBranch,
                ]
                    + $0.labels
                    + users.flatMap {
                        [$0.name, $0.username]
                    }
            }
        )
    }
}

@MainActor
@Observable
final class ProjectMergeRequestsModel {
    var selectedState =
        GitLabProjectMergeRequestState.opened
    {
        didSet {
            activateSelectedState()
        }
    }

    private(set) var activeModel:
        GitLabProjectMergeRequestsPageModel
    @ObservationIgnored
    private let projectID: Int
    @ObservationIgnored
    private let loader:
        any GitLabMergeRequestLoading
    @ObservationIgnored
    private var cachedModels: [
        GitLabProjectMergeRequestState:
            GitLabProjectMergeRequestsPageModel
    ]

    init(
        projectID: Int,
        loader: any GitLabMergeRequestLoading
    ) {
        let model =
            GitLabProjectMergeRequestsPageModel(
                projectID: projectID,
                state: .opened,
                loader: loader
            )
        self.projectID = projectID
        self.loader = loader
        activeModel = model
        cachedModels = [.opened: model]
    }

    func reconcileEditedMergeRequest(
        _ mergeRequest: GitLabMergeRequest
    ) {
        guard
            mergeRequest.projectID == projectID
        else {
            return
        }
        guard
            let targetState =
                GitLabProjectMergeRequestState
                .allCases
                .first(where: {
                    $0.contains(mergeRequest)
                })
        else {
            for model in cachedModels.values {
                _ = model.removeItemIfPresent(
                    mergeRequest
                )
            }
            return
        }

        for (state, model) in cachedModels
        where state != targetState {
            _ = model.removeItemIfPresent(
                mergeRequest
            )
        }

        guard
            let targetModel =
                cachedModels[targetState]
        else {
            return
        }
        if
            !targetModel.reconcileItemIfPresent(
                mergeRequest
            ),
            targetModel.hasLoaded
        {
            targetModel.reconcileItemAtStart(
                mergeRequest,
                countAdjustmentIfInserted: 1
            )
        }
    }

    func model(
        for state:
            GitLabProjectMergeRequestState
    ) -> GitLabProjectMergeRequestsPageModel {
        if let model = cachedModels[state] {
            return model
        }
        let model =
            GitLabProjectMergeRequestsPageModel(
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
