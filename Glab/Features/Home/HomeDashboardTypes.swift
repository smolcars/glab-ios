import Foundation

nonisolated enum HomeDashboardSection:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case assignedIssues
    case assignedMergeRequests
    case reviewRequests
    case recentProjects
    case starredProjects

    var title: String {
        switch self {
        case .assignedIssues:
            "Assigned Issues"
        case .assignedMergeRequests:
            "Assigned Merge Requests"
        case .reviewRequests:
            "Review Requests"
        case .recentProjects:
            "Recent Projects"
        case .starredProjects:
            "Starred Projects"
        }
    }

    var systemImage: String {
        switch self {
        case .assignedIssues:
            "smallcircle.filled.circle"
        case .assignedMergeRequests:
            "arrow.triangle.branch"
        case .reviewRequests:
            "person.crop.circle.badge.checkmark"
        case .recentProjects:
            "clock"
        case .starredProjects:
            "star.fill"
        }
    }

    var emptyMessage: String {
        switch self {
        case .assignedIssues:
            "No assigned issues"
        case .assignedMergeRequests:
            "No assigned merge requests"
        case .reviewRequests:
            "No open review requests"
        case .recentProjects:
            "No recent projects"
        case .starredProjects:
            "No starred projects"
        }
    }

}

nonisolated struct GitLabHomeWorkItem:
    Identifiable,
    Equatable,
    Sendable
{
    let id: String
    let title: String
    let detail: String
    let webURL: URL?
}

nonisolated enum HomeDashboardSectionState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded([GitLabHomeWorkItem])
    case failed(GitLabSessionClientError)
}

nonisolated enum HomeDashboardRowStatus:
    Equatable,
    Sendable
{
    case loading
    case empty
    case content
    case failed
}

nonisolated struct HomeDashboardRowPresentation:
    Equatable,
    Sendable
{
    let status: HomeDashboardRowStatus
    let subtitle: String
    let accessibilityValue: String
}

nonisolated struct HomeDashboardLoadResult:
    Equatable,
    Sendable
{
    typealias UserResult = Result<
        GitLabAuthenticatedUser,
        GitLabSessionClientError
    >
    typealias WorkResult = Result<
        [GitLabHomeWorkItem],
        GitLabSessionClientError
    >

    let user: UserResult
    let sections: [HomeDashboardSection: WorkResult]
}

nonisolated enum HomeDashboardLoadingError:
    Error,
    Equatable,
    Sendable
{
    case cancelled
}

nonisolated protocol HomeDashboardLoading: Sendable {
    func load()
        async throws(HomeDashboardLoadingError)
        -> HomeDashboardLoadResult
}
