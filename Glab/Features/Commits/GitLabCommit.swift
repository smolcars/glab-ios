import Foundation

nonisolated struct GitLabCommit:
    Decodable,
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let shortID: String
    let title: String
    let authorName: String
    let authorEmail: String
    let authoredDate: Date
    let committerName: String
    let committerEmail: String
    let committedDate: Date
    let message: String
    let parentIDs: [String]
    let webURL: URL?

    var safeWebURL: URL? {
        GitLabWebURL.validated(webURL)
    }

    var authorMark: String {
        let components = authorName
            .components(
                separatedBy:
                    CharacterSet
                    .alphanumerics
                    .inverted
            )
            .filter { !$0.isEmpty }

        guard let first = components.first else {
            return "?"
        }
        guard
            let last =
                components.dropFirst().last
        else {
            return String(first.prefix(2))
                .uppercased()
        }

        return (
            String(first.prefix(1))
                + String(last.prefix(1))
        )
        .uppercased()
    }

    private enum CodingKeys:
        String,
        CodingKey
    {
        case id
        case shortID = "short_id"
        case title
        case authorName = "author_name"
        case authorEmail = "author_email"
        case authoredDate = "authored_date"
        case committerName = "committer_name"
        case committerEmail = "committer_email"
        case committedDate = "committed_date"
        case message
        case parentIDs = "parent_ids"
        case webURL = "web_url"
    }
}

nonisolated struct GitLabCommitPage:
    Equatable,
    Sendable
{
    let commits: [GitLabCommit]
    let nextPageURL: URL?
}

nonisolated struct GitLabCommitDiffRoute:
    Equatable,
    Hashable,
    Sendable
{
    let projectID: Int
    let commitSHA: String
}

nonisolated struct GitLabLineChanges:
    Equatable,
    Sendable
{
    let additions: Int
    let deletions: Int

    static let zero = Self(
        additions: 0,
        deletions: 0
    )

    static func + (
        lhs: Self,
        rhs: Self
    ) -> Self {
        Self(
            additions:
                lhs.additions
                    + rhs.additions,
            deletions:
                lhs.deletions
                    + rhs.deletions
        )
    }
}

nonisolated extension GitLabDiffFile {
    var lineChanges: GitLabLineChanges {
        var additions = 0
        var deletions = 0
        var isInsideHunk = false

        for line in diff.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ) {
            if line.hasPrefix("@@") {
                isInsideHunk = true
                continue
            }
            guard isInsideHunk else {
                continue
            }

            switch line.first {
            case "+":
                additions += 1
            case "-":
                deletions += 1
            default:
                break
            }
        }

        return GitLabLineChanges(
            additions: additions,
            deletions: deletions
        )
    }
}

nonisolated extension Collection
where Element == GitLabDiffFile {
    var lineChanges: GitLabLineChanges {
        reduce(.zero) {
            $0 + $1.lineChanges
        }
    }
}
