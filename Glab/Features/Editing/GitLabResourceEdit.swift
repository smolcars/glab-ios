import Foundation

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
    Sendable
{
    static let maximumDescriptionLength = 1_048_576

    let title: String?
    let description: String?

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
