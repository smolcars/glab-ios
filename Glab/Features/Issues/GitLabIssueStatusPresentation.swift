nonisolated enum GitLabIssueStatusTone:
    Equatable,
    Sendable
{
    case secondary
    case active
    case complete
    case canceled
}

nonisolated struct GitLabIssueStatusPresentation:
    Equatable,
    Sendable
{
    let title: String
    let systemImage: String
    let tone: GitLabIssueStatusTone
    let isStale: Bool
    let accessibilityLabel: String

    init(
        status:
            GitLabIssueWorkItemStatus?,
        isStale: Bool
    ) {
        self.isStale = isStale
        guard let status else {
            title = "Set status"
            systemImage = "circle.dashed"
            tone = .secondary
            accessibilityLabel =
                "Work item status not set"
            return
        }

        title = status.name
        (systemImage, tone) =
            Self.appearance(
                for: status.category
            )
        accessibilityLabel =
            [
                "Work item status",
                status.name,
                isStale
                    ? "may be out of date"
                    : nil,
            ]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}

private nonisolated extension
    GitLabIssueStatusPresentation
{
    static func appearance(
        for category:
            GitLabIssueStatusCategory
    ) -> (
        systemImage: String,
        tone: GitLabIssueStatusTone
    ) {
        switch category {
        case .triage:
            ("tray.full", .secondary)
        case .toDo:
            ("circle", .secondary)
        case .inProgress:
            (
                "circle.lefthalf.filled",
                .active
            )
        case .done:
            (
                "checkmark.circle.fill",
                .complete
            )
        case .canceled:
            (
                "xmark.circle.fill",
                .canceled
            )
        }
    }
}
