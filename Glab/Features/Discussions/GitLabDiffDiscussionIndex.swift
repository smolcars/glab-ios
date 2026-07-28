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
    let currentDiscussionCount: Int

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
        var currentDiscussionCount = 0

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
            currentDiscussionCount += 1
        }

        self.discussionsByPosition =
            discussionsByPosition
        self.outdatedDiscussions =
            outdatedDiscussions
        self.unmappedDiscussions =
            unmappedDiscussions
        self.currentDiscussionCount =
            currentDiscussionCount
    }

    var positionedDiscussionCount: Int {
        currentDiscussionCount
            + outdatedDiscussions.count
            + unmappedDiscussions.count
    }

    func discussions(
        at position: GitLabDiffLinePosition
    ) -> [GitLabDiscussion] {
        discussionsByPosition[position] ?? []
    }
}
