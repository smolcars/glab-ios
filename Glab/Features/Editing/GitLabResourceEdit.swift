import Foundation

nonisolated enum GitLabResourceEditTarget:
    Codable,
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case issue(GitLabIssueRoute)
    case mergeRequest(GitLabMergeRequestRoute)

    private enum Kind:
        String,
        Codable
    {
        case issue
        case mergeRequest
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case kind
        case projectID
        case resourceIID
    }

    init(from decoder: any Decoder) throws {
        let container =
            try decoder.container(
                keyedBy: CodingKeys.self
            )
        let kind = try container.decode(
            Kind.self,
            forKey: .kind
        )
        let projectID = try container.decode(
            Int.self,
            forKey: .projectID
        )
        let resourceIID = try container.decode(
            Int.self,
            forKey: .resourceIID
        )

        self =
            switch kind {
            case .issue:
                .issue(
                    GitLabIssueRoute(
                        projectID: projectID,
                        issueIID: resourceIID
                    )
                )
            case .mergeRequest:
                .mergeRequest(
                    GitLabMergeRequestRoute(
                        projectID: projectID,
                        mergeRequestIID:
                            resourceIID
                    )
                )
            }
    }

    func encode(
        to encoder: any Encoder
    ) throws {
        var container =
            encoder.container(
                keyedBy: CodingKeys.self
            )
        try container.encode(
            kind,
            forKey: .kind
        )
        try container.encode(
            projectID,
            forKey: .projectID
        )
        try container.encode(
            resourceIID,
            forKey: .resourceIID
        )
    }

    var description: String {
        "GitLabResourceEditTarget(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var projectID: Int {
        switch self {
        case let .issue(route):
            route.projectID
        case let .mergeRequest(route):
            route.projectID
        }
    }

    var resourceIID: Int {
        switch self {
        case let .issue(route):
            route.issueIID
        case let .mergeRequest(route):
            route.mergeRequestIID
        }
    }

    var kindStorageIdentifier: String {
        kind.rawValue
    }

    private var kind: Kind {
        switch self {
        case .issue:
            .issue
        case .mergeRequest:
            .mergeRequest
        }
    }
}

nonisolated struct GitLabResourceEditSnapshot:
    Codable,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let target: GitLabResourceEditTarget
    let resourceID: Int
    let title: String
    let rawDescription: String
    let updatedAt: Date

    private enum CodingKeys:
        String,
        CodingKey
    {
        case target
        case resourceID
        case title
        case rawDescription = "description"
        case updatedAt
    }

    init(
        target: GitLabResourceEditTarget,
        resourceID: Int,
        title: String,
        description: String,
        updatedAt: Date
    ) {
        self.target = target
        self.resourceID = resourceID
        self.title = title
        rawDescription = description
        self.updatedAt = updatedAt
    }

    init(issue: GitLabIssue) {
        self.init(
            target: .issue(issue.route),
            resourceID: issue.id,
            title: issue.title,
            description:
                issue.description ?? "",
            updatedAt: issue.updatedAt
        )
    }

    init(mergeRequest: GitLabMergeRequest) {
        self.init(
            target:
                .mergeRequest(
                    mergeRequest.route
                ),
            resourceID: mergeRequest.id,
            title: mergeRequest.title,
            description:
                mergeRequest.description ?? "",
            updatedAt: mergeRequest.updatedAt
        )
    }

    var description: String {
        "GitLabResourceEditSnapshot(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabResourceEditValidationError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case emptyTitle
    case descriptionTooLong(maximum: Int)
    case noChanges

    var description: String {
        switch self {
        case .emptyTitle:
            "Enter a title before saving."
        case let .descriptionTooLong(maximum):
            "The description cannot exceed \(maximum) characters."
        case .noChanges:
            "Change the title or description before saving."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated struct GitLabResourceEditChanges:
    Equatable,
    Sendable,
    CustomReflectable
{
    static let maximumDescriptionLength = 1_048_576

    let title: String?
    let description: String?

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["redacted": true],
            displayStyle: .struct
        )
    }

    init(
        title: String? = nil,
        description: String? = nil
    ) throws(GitLabResourceEditValidationError) {
        guard title != nil || description != nil else {
            throw .noChanges
        }
        if
            let title,
            title.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        {
            throw .emptyTitle
        }
        if
            let description,
            description.count
                > Self.maximumDescriptionLength
        {
            throw .descriptionTooLong(
                maximum:
                    Self.maximumDescriptionLength
            )
        }

        self.title = title
        self.description = description
    }
}
