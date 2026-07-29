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
    let title: String
    let rawDescription: String
    let labelNames: [String]
    let assigneeIDs: [Int]
    let confidential: Bool
    let dueDate: GitLabIssueDueDate?

    init(
        projectID: Int?,
        title: String,
        description: String = "",
        labelNames: [String] = [],
        assigneeIDs: [Int] = [],
        confidential: Bool = false,
        dueDate: GitLabIssueDueDate? = nil
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

        self.projectID = projectID
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

nonisolated struct GitLabProjectMember:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: Int
    let username: String
    let name: String
    let state: String
    let avatarURL: URL?
    let webURL: URL?
    let accessLevel: Int

    var isActive: Bool {
        state.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .lowercased() == "active"
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case username
        case name
        case state
        case avatarURL = "avatar_url"
        case webURL = "web_url"
        case accessLevel = "access_level"
    }
}
