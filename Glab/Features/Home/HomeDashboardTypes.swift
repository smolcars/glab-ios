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
    case recentProjects
    case starredProjects

    static let displayedCases: [Self] = [
        .assignedIssues,
        .assignedMergeRequests,
        .recentProjects,
        .starredProjects,
    ]

    var title: String {
        switch self {
        case .assignedIssues:
            "Your Issues"
        case .assignedMergeRequests:
            "Your Merge Requests"
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
        case .recentProjects:
            "clock"
        case .starredProjects:
            "star.fill"
        }
    }

    var emptyMessage: String {
        switch self {
        case .assignedIssues:
            "No open issues"
        case .assignedMergeRequests:
            "No open merge requests"
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
    let updatedAt: Date?

    init(
        id: String,
        title: String,
        detail: String,
        webURL: URL?,
        updatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.detail = detail
        self.webURL = webURL
        self.updatedAt = updatedAt
    }
}

nonisolated enum HomeDashboardPreview {
    static func merge(
        _ scopedItems:
            [[GitLabHomeWorkItem]],
        limit: Int
    ) -> [GitLabHomeWorkItem] {
        var newestByID:
            [String: GitLabHomeWorkItem] = [:]

        for item in scopedItems.joined() {
            guard
                let existing =
                    newestByID[item.id]
            else {
                newestByID[item.id] = item
                continue
            }

            if isNewer(item, than: existing) {
                newestByID[item.id] = item
            }
        }

        return Array(
            newestByID.values
                .sorted {
                    if $0.updatedAt
                        != $1.updatedAt
                    {
                        return ($0.updatedAt
                            ?? .distantPast)
                            > ($1.updatedAt
                                ?? .distantPast)
                    }
                    return $0.id < $1.id
                }
                .prefix(max(0, limit))
        )
    }

    private static func isNewer(
        _ candidate: GitLabHomeWorkItem,
        than existing: GitLabHomeWorkItem
    ) -> Bool {
        (candidate.updatedAt ?? .distantPast)
            > (existing.updatedAt
                ?? .distantPast)
    }
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
    case stale
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

nonisolated enum HomeDashboardLoadUpdate:
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

    case user(UserResult)
    case section(HomeDashboardSection, WorkResult)
}

nonisolated enum HomeDashboardLoadingError:
    Error,
    Equatable,
    Sendable
{
    case cancelled
}

nonisolated protocol HomeDashboardLoading: Sendable {
    func load(
        refreshBehavior: GitLabCacheRefreshBehavior,
        onUpdate:
            @escaping @Sendable (HomeDashboardLoadUpdate) async -> Void
    )
        async throws(HomeDashboardLoadingError)
}
