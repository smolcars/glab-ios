import Testing
import UIKit
@testable import Glab

@Suite("GitLab diff collection view")
@MainActor
struct GitLabDiffCollectionViewTests {
    @Test("Configures a counted marker and returns its exact position")
    func configuresDiscussionMarker() throws {
        let position = try makePosition()
        var selectedPosition:
            GitLabDiffLinePosition?
        let cell = GitLabDiffCollectionViewCell(
            frame: CGRect(
                x: 0,
                y: 0,
                width: 600,
                height:
                    GitLabDiffLayoutMetrics
                    .baseRowHeight
            )
        )

        cell.configure(
            with:
                .context(
                    GitLabDiffLine(
                        ordinal: 0,
                        kind: .context,
                        oldLineNumber: 20,
                        newLineNumber: 21,
                        text: "let value = 1"
                    )
                ),
            marker:
                GitLabDiffDiscussionMarker(
                    position: position,
                    discussionCount: 2,
                    allowsCommenting: false
                )
        ) {
            selectedPosition = $0
        }

        let button = try #require(
            cell.contentView.subviews
                .compactMap {
                    $0 as? UIButton
                }
                .first
        )
        #expect(!button.isHidden)
        #expect(
            button.configuration?.title == "2"
        )
        #expect(
            button.accessibilityLabel
                == "2 line discussions"
        )
        #expect(
            cell.accessibilityTraits
                .contains(.button)
        )
        #expect(cell.accessibilityActivate())
        #expect(selectedPosition == position)
    }

    @Test("Reuse removes marker state before an unmarked row")
    func resetsMarkerDuringReuse() throws {
        let position = try makePosition()
        let cell = GitLabDiffCollectionViewCell(
            frame: CGRect(
                x: 0,
                y: 0,
                width: 600,
                height:
                    GitLabDiffLayoutMetrics
                    .baseRowHeight
            )
        )
        let line = GitLabDiffLine(
            ordinal: 0,
            kind: .addition,
            oldLineNumber: nil,
            newLineNumber: 21,
            text: "let value = 1"
        )
        cell.configure(
            with: .addition(line),
            marker:
                GitLabDiffDiscussionMarker(
                    position: position,
                    discussionCount: 0,
                    allowsCommenting: true
                )
        ) { _ in }

        cell.prepareForReuse()
        cell.configure(
            with: .addition(line),
            marker: nil
        ) { _ in }

        let button = try #require(
            cell.contentView.subviews
                .compactMap {
                    $0 as? UIButton
                }
                .first
        )
        #expect(button.isHidden)
        #expect(
            button.configuration == nil
        )
        #expect(
            button.accessibilityLabel == nil
        )
        #expect(
            !cell.accessibilityTraits
                .contains(.button)
        )
        #expect(!cell.accessibilityActivate())
    }

    @Test("In-place reconfiguration removes stale marker accessibility")
    func resetsMarkerDuringReconfiguration()
        throws
    {
        let position = try makePosition()
        let cell = GitLabDiffCollectionViewCell(
            frame: CGRect(
                x: 0,
                y: 0,
                width: 600,
                height:
                    GitLabDiffLayoutMetrics
                    .baseRowHeight
            )
        )
        let line = GitLabDiffLine(
            ordinal: 0,
            kind: .addition,
            oldLineNumber: nil,
            newLineNumber: 21,
            text: "let value = 1"
        )
        cell.configure(
            with: .addition(line),
            marker:
                GitLabDiffDiscussionMarker(
                    position: position,
                    discussionCount: 1,
                    allowsCommenting: false
                )
        ) { _ in }

        cell.configure(
            with: .addition(line),
            marker: nil
        ) { _ in }

        let button = try #require(
            cell.contentView.subviews
                .compactMap {
                    $0 as? UIButton
                }
                .first
        )
        #expect(button.isHidden)
        #expect(
            !cell.accessibilityTraits
                .contains(.button)
        )
        #expect(!cell.accessibilityActivate())
    }

    private func makePosition()
        throws -> GitLabDiffLinePosition
    {
        let version = try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "base",
                startSHA: "start",
                headSHA: "head"
            )
        )
        return try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: 20,
                newLine: 21
            )
        )
    }
}
