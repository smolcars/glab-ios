import Foundation

nonisolated enum GitLabResourceStateEvent:
    String,
    Equatable,
    Sendable
{
    case close
    case reopen
}

nonisolated enum GitLabResourceLabelChanges:
    Equatable,
    Sendable
{
    case delta(
        add: [String],
        remove: [String]
    )
    case replacement([String])
}

nonisolated struct GitLabResourceMetadataChanges:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    let labels: GitLabResourceLabelChanges?
    let assigneeIDs: [Int]?
    let reviewerIDs: [Int]?
    let stateEvent: GitLabResourceStateEvent?

    init(
        labels: GitLabResourceLabelChanges? = nil,
        assigneeIDs: [Int]? = nil,
        reviewerIDs: [Int]? = nil,
        stateEvent: GitLabResourceStateEvent? = nil
    ) {
        self.labels =
            labels.map(Self.normalized)
        self.assigneeIDs =
            assigneeIDs.map(Self.unique)
        self.reviewerIDs =
            reviewerIDs.map(Self.unique)
        self.stateEvent = stateEvent
    }

    var description: String {
        "GitLabResourceMetadataChanges(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["redacted": true],
            displayStyle: .struct
        )
    }

    func updateBody(
        allowsReviewers: Bool
    ) throws(
        GitLabResourceMetadataValidationError
    ) -> GitLabResourceMetadataUpdateBody {
        if reviewerIDs != nil && !allowsReviewers {
            throw .reviewersUnsupported
        }
        if
            let assigneeIDs,
            assigneeIDs.contains(where: { $0 <= 0 })
        {
            throw .invalidAssignee
        }
        if
            let reviewerIDs,
            reviewerIDs.contains(where: { $0 <= 0 })
        {
            throw .invalidReviewer
        }

        let labelFields = try validatedLabelFields()
        let hasLabelChanges =
            labelFields.add != nil
            || labelFields.remove != nil
            || labelFields.replacement != nil
        guard
            hasLabelChanges
                || assigneeIDs != nil
                || reviewerIDs != nil
                || stateEvent != nil
        else {
            throw .noChanges
        }

        let assigneeID =
            assigneeIDs?.count == 1
            ? assigneeIDs?[0]
            : nil
        let replacementAssigneeIDs =
            assigneeIDs?.count == 1
            ? nil
            : assigneeIDs

        return GitLabResourceMetadataUpdateBody(
            addLabels:
                labelFields.add?.joined(
                    separator: ","
                ),
            removeLabels:
                labelFields.remove?.joined(
                    separator: ","
                ),
            labels:
                labelFields.replacement?.joined(
                    separator: ","
                ),
            assigneeID: assigneeID,
            assigneeIDs:
                replacementAssigneeIDs,
            reviewerIDs: reviewerIDs,
            stateEvent: stateEvent?.rawValue
        )
    }

    private func validatedLabelFields() throws(
        GitLabResourceMetadataValidationError
    ) -> (
        add: [String]?,
        remove: [String]?,
        replacement: [String]?
    ) {
        guard let labels else {
            return (nil, nil, nil)
        }

        switch labels {
        case let .delta(add, remove):
            guard
                (add + remove).allSatisfy(
                    Self.isValidLabel
                )
            else {
                throw .invalidLabel
            }
            guard
                Set(add).isDisjoint(
                    with: Set(remove)
                )
            else {
                throw .contradictoryLabels
            }

            return (
                add.isEmpty ? nil : add,
                remove.isEmpty ? nil : remove,
                nil
            )

        case let .replacement(labels):
            guard
                labels.allSatisfy(
                    Self.isValidLabel
                )
            else {
                throw .invalidLabel
            }

            return (nil, nil, labels)
        }
    }

    private static func normalized(
        _ changes: GitLabResourceLabelChanges
    ) -> GitLabResourceLabelChanges {
        switch changes {
        case let .delta(add, remove):
            .delta(
                add: unique(add),
                remove: unique(remove)
            )
        case let .replacement(labels):
            .replacement(unique(labels))
        }
    }

    private static func unique<Element: Hashable>(
        _ values: [Element]
    ) -> [Element] {
        var seen = Set<Element>()
        return values.filter {
            seen.insert($0).inserted
        }
    }

    private static func isValidLabel(
        _ label: String
    ) -> Bool {
        !label.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty
    }
}

nonisolated enum GitLabResourceMetadataValidationError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case noChanges
    case invalidAssignee
    case invalidReviewer
    case invalidLabel
    case contradictoryLabels
    case reviewersUnsupported

    var description: String {
        switch self {
        case .noChanges:
            "Choose a metadata or state change before saving."
        case .invalidAssignee:
            "One or more assignees are invalid."
        case .invalidReviewer:
            "One or more reviewers are invalid."
        case .invalidLabel:
            "One or more labels are invalid."
        case .contradictoryLabels:
            "A label cannot be added and removed together."
        case .reviewersUnsupported:
            "Issues do not support reviewers."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated struct GitLabResourceMetadataUpdateBody:
    Encodable,
    Sendable
{
    let addLabels: String?
    let removeLabels: String?
    let labels: String?
    let assigneeID: Int?
    let assigneeIDs: [Int]?
    let reviewerIDs: [Int]?
    let stateEvent: String?

    private enum CodingKeys:
        String,
        CodingKey
    {
        case addLabels = "add_labels"
        case removeLabels = "remove_labels"
        case labels
        case assigneeID = "assignee_id"
        case assigneeIDs = "assignee_ids"
        case reviewerIDs = "reviewer_ids"
        case stateEvent = "state_event"
    }
}
