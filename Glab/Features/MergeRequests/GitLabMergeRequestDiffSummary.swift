import Foundation

nonisolated struct GitLabMergeRequestDiffSummary:
    Equatable,
    Sendable
{
    let additions: Int
    let deletions: Int
    let changes: Int
    let fileCount: Int
}

nonisolated enum GitLabMergeRequestDiffSummaryAvailability:
    Equatable,
    Sendable
{
    case available(
        GitLabMergeRequestDiffSummary
    )
    case unavailable
}

nonisolated struct GitLabMergeRequestDiffSummaryPresentation:
    Equatable,
    Sendable
{
    let fileText: String
    let additionsText: String?
    let deletionsText: String?
    let isLoading: Bool
    let accessibilityLabel: String

    init(
        state:
            GitLabResourceDetailState<
                GitLabMergeRequestDiffSummaryAvailability
            >,
        restChangesCount: String?
    ) {
        isLoading = switch state {
        case .idle, .loading:
            true
        case .loaded, .failed:
            false
        }

        if
            case let .loaded(.available(summary)) =
                state
        {
            fileText = Self.fileText(
                count:
                    String(summary.fileCount)
            )
            additionsText =
                "+\(summary.additions)"
            deletionsText =
                "−\(summary.deletions)"
            accessibilityLabel =
                "\(summary.fileCount) changed "
                + (summary.fileCount == 1
                    ? "file"
                    : "files")
                + ", \(summary.additions) additions"
                + ", \(summary.deletions) deletions"
            return
        }

        fileText = Self.fileText(
            count:
                Self.normalizedRESTCount(
                    restChangesCount
                )
        )
        additionsText = nil
        deletionsText = nil
        accessibilityLabel = fileText
    }

    private static func normalizedRESTCount(
        _ value: String?
    ) -> String? {
        guard
            let value = value?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !value.isEmpty
        else {
            return nil
        }

        let digits = value.hasSuffix("+")
            ? value.dropLast()
            : value[...]
        guard
            !digits.isEmpty,
            digits.allSatisfy(\.isNumber)
        else {
            return nil
        }
        return value
    }

    private static func fileText(
        count: String?
    ) -> String {
        guard let count else {
            return "Changed files"
        }
        return count == "1"
            ? "1 file"
            : "\(count) files"
    }
}

nonisolated enum GitLabMergeRequestDiffSummaryEndpoint {
    static func query(
        mergeRequestID: Int
    ) throws -> GitLabAPIRequest<
        GitLabMergeRequestDiffSummaryGraphQLResponse
    > {
        try .graphQL(
            requires: .read,
            body:
                GitLabMergeRequestDiffSummaryGraphQLBody(
                    query: queryDocument,
                    variables:
                        .init(
                            id:
                                "gid://gitlab/MergeRequest/"
                                + String(
                                    mergeRequestID
                                )
                        )
                )
        )
    }

    private static let queryDocument =
        """
        query GlabMergeRequestDiffSummary($id: MergeRequestID!) {
          mergeRequest(id: $id) {
            diffStatsSummary {
              additions
              deletions
              changes
              fileCount
            }
          }
        }
        """
}

private nonisolated struct GitLabMergeRequestDiffSummaryGraphQLBody:
    Encodable,
    Sendable
{
    let query: String
    let variables: Variables

    struct Variables:
        Encodable,
        Sendable
    {
        let id: String
    }
}

nonisolated struct GitLabMergeRequestDiffSummaryGraphQLResponse:
    Decodable,
    Sendable
{
    let data: DataPayload?

    struct DataPayload:
        Decodable,
        Sendable
    {
        let mergeRequest: MergeRequest?
    }

    struct MergeRequest:
        Decodable,
        Sendable
    {
        let diffStatsSummary: Summary?
    }

    struct Summary:
        Decodable,
        Sendable
    {
        let additions: Int?
        let deletions: Int?
        let changes: Int?
        let fileCount: Int?
    }
}
