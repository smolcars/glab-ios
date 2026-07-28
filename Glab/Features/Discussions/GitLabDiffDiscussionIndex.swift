import Foundation

nonisolated struct GitLabDiffDiscussionIndex:
    Equatable,
    Sendable
{
    private let discussionsByPosition:
        [
            GitLabDiffLinePosition:
                [GitLabDiscussion]
        ]

    let outdatedDiscussions:
        [GitLabDiscussion]
    let unmappedDiscussions:
        [GitLabDiscussion]
    let currentDiscussions:
        [GitLabDiscussion]

    init(
        discussions: [GitLabDiscussion],
        currentVersion:
            GitLabMergeRequestDiffVersionIdentity
    ) {
        var discussionsByPosition:
            [
                GitLabDiffLinePosition:
                    [GitLabDiscussion]
            ] = [:]
        var outdatedDiscussions:
            [GitLabDiscussion] = []
        var unmappedDiscussions:
            [GitLabDiscussion] = []
        var currentDiscussions:
            [GitLabDiscussion] = []

        for discussion in discussions {
            guard
                let position =
                    discussion.notes
                    .lazy
                    .compactMap(\.position)
                    .first
            else {
                continue
            }

            guard
                position.versionIdentity
                    == currentVersion
            else {
                if position.versionIdentity != nil {
                    outdatedDiscussions.append(
                        discussion
                    )
                } else {
                    unmappedDiscussions.append(
                        discussion
                    )
                }
                continue
            }

            guard
                let linePosition =
                    position.linePosition
            else {
                unmappedDiscussions.append(
                    discussion
                )
                continue
            }

            discussionsByPosition[
                linePosition,
                default: []
            ]
            .append(discussion)
            currentDiscussions.append(
                discussion
            )
        }

        self.discussionsByPosition =
            discussionsByPosition
        self.outdatedDiscussions =
            outdatedDiscussions
        self.unmappedDiscussions =
            unmappedDiscussions
        self.currentDiscussions =
            currentDiscussions
    }

    var currentDiscussionCount: Int {
        currentDiscussions.count
    }

    var allPositionedDiscussions:
        [GitLabDiscussion]
    {
        currentDiscussions
            + outdatedDiscussions
            + unmappedDiscussions
    }

    var positionedDiscussionCount: Int {
        currentDiscussions.count
            + outdatedDiscussions.count
            + unmappedDiscussions.count
    }

    func discussions(
        at position: GitLabDiffLinePosition
    ) -> [GitLabDiscussion] {
        discussionsByPosition[position] ?? []
    }
}

nonisolated struct GitLabDiffDiscussionMarker:
    Equatable,
    Sendable
{
    let position: GitLabDiffLinePosition
    let discussionCount: Int
    let allowsCommenting: Bool
}

nonisolated struct GitLabDiffDiscussionContext:
    Equatable,
    Sendable
{
    let version:
        GitLabMergeRequestDiffVersionIdentity
    let oldPath: String
    let newPath: String
    let index: GitLabDiffDiscussionIndex
    let revision: Int
    let allowsCommenting: Bool

    func marker(
        for line: GitLabDiffLine
    ) -> GitLabDiffDiscussionMarker? {
        guard
            let position =
                GitLabDiffLinePosition(
                    version: version,
                    oldPath: oldPath,
                    newPath: newPath,
                    line: line
                )
        else {
            return nil
        }
        let discussionCount =
            index.discussions(
                at: position
            ).count
        guard
            discussionCount > 0
                || allowsCommenting
        else {
            return nil
        }
        return GitLabDiffDiscussionMarker(
            position: position,
            discussionCount: discussionCount,
            allowsCommenting: allowsCommenting
        )
    }

    static func == (
        lhs: Self,
        rhs: Self
    ) -> Bool {
        lhs.version == rhs.version
            && lhs.oldPath == rhs.oldPath
            && lhs.newPath == rhs.newPath
            && lhs.revision == rhs.revision
            && lhs.allowsCommenting
                == rhs.allowsCommenting
    }
}
