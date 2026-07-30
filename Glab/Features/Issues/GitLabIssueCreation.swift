import Foundation

nonisolated enum GitLabIssueCreationValidationError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case missingProject
    case emptyTitle
    case descriptionTooLong(maximum: Int)
    case invalidAssignee
    case invalidDueDate
    case invalidStatus
    case invalidMilestone
    case invalidIteration
    case missingProjectPath

    var description: String {
        switch self {
        case .missingProject:
            "Choose a project."
        case .emptyTitle:
            "Enter an issue title."
        case let .descriptionTooLong(maximum):
            "The description must be \(maximum) characters or fewer."
        case .invalidAssignee:
            "One or more selected assignees are invalid."
        case .invalidDueDate:
            "Choose a valid due date."
        case .invalidStatus:
            "Choose a valid status."
        case .invalidMilestone:
            "Choose a valid milestone."
        case .invalidIteration:
            "Choose a valid iteration."
        case .missingProjectPath:
            "Reload the selected project before choosing a status or iteration."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated struct GitLabIssueDueDate:
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    let year: Int
    let month: Int
    let day: Int

    var apiValue: String? {
        guard isValid else {
            return nil
        }

        return String(
            format: "%04d-%02d-%02d",
            year,
            month,
            day
        )
    }

    private var isValid: Bool {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.locale = Locale(
            identifier: "en_US_POSIX"
        )
        calendar.timeZone = .gmt
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day
        )
        guard
            let date = calendar.date(
                from: components
            )
        else {
            return false
        }
        let resolved = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return resolved.year == year
            && resolved.month == month
            && resolved.day == day
    }
}

nonisolated struct GitLabIssueCreationInput:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    static let maximumDescriptionLength =
        GitLabResourceEditChanges
        .maximumDescriptionLength

    let projectID: Int
    let projectPath: String
    let title: String
    let rawDescription: String
    let labelNames: [String]
    let assigneeIDs: [Int]
    let confidential: Bool
    let dueDate: GitLabIssueDueDate?
    let status: GitLabIssueWorkItemStatus?
    let milestone: GitLabIssueMilestone?
    let iteration: GitLabIssueIteration?

    init(
        projectID: Int?,
        projectPath: String? = nil,
        title: String,
        description: String = "",
        labelNames: [String] = [],
        assigneeIDs: [Int] = [],
        confidential: Bool = false,
        dueDate: GitLabIssueDueDate? = nil,
        status:
            GitLabIssueWorkItemStatus? = nil,
        milestone:
            GitLabIssueMilestone? = nil,
        iteration:
            GitLabIssueIteration? = nil
    ) throws(
        GitLabIssueCreationValidationError
    ) {
        guard
            let projectID,
            projectID > 0
        else {
            throw .missingProject
        }
        guard
            !title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw .emptyTitle
        }
        guard
            description.count
                <= Self.maximumDescriptionLength
        else {
            throw .descriptionTooLong(
                maximum:
                    Self.maximumDescriptionLength
            )
        }
        guard assigneeIDs.allSatisfy({ $0 > 0 }) else {
            throw .invalidAssignee
        }
        if
            let dueDate,
            dueDate.apiValue == nil
        {
            throw .invalidDueDate
        }
        if
            let status,
            status.id.isEmpty
                || status.name
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty
        {
            throw .invalidStatus
        }
        if
            let milestone,
            milestone.id <= 0
        {
            throw .invalidMilestone
        }
        if
            let iteration,
            iteration.id <= 0
        {
            throw .invalidIteration
        }

        let normalizedProjectPath =
            projectPath?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        if
            status != nil
                || iteration != nil,
            normalizedProjectPath?
                .isEmpty != false
        {
            throw .missingProjectPath
        }

        self.projectID = projectID
        self.projectPath =
            normalizedProjectPath ?? ""
        self.title = title
        rawDescription = description
        self.labelNames = Self.unique(
            labelNames.filter {
                !$0.isEmpty
            }
        )
        self.assigneeIDs = Self.unique(
            assigneeIDs
        )
        self.confidential = confidential
        self.dueDate = dueDate
        self.status = status
        self.milestone = milestone
        self.iteration = iteration
    }

    var description: String {
        "GitLabIssueCreationInput(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    private static func unique<Value>(
        _ values: [Value]
    ) -> [Value] where Value: Hashable {
        var seen: Set<Value> = []
        return values.filter {
            seen.insert($0).inserted
        }
    }
}

nonisolated struct GitLabProjectLabel:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let name: String
    let color: String
    let textColor: String?
    let labelDescription: String?
    let archived: Bool?

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case name
        case color
        case textColor = "text_color"
        case labelDescription = "description"
        case archived
    }
}
