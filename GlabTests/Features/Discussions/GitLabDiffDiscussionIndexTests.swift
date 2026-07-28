import Foundation
import Testing
@testable import Glab

@Suite("GitLab diff discussion index")
struct GitLabDiffDiscussionIndexTests {
    @Test("Indexes multiple current threads once at their exact line")
    func indexesCurrentThreads() throws {
        let version = try makeVersion()
        let rawPosition = makeRawPosition(
            version: version
        )
        let linePosition = try #require(
            rawPosition.linePosition
        )
        let first = makeTestDiscussion(
            id: "first",
            notes: [
                makeTestDiscussionNote(
                    id: 101,
                    type: "DiffNote",
                    position: rawPosition
                ),
                makeTestDiscussionNote(
                    id: 102,
                    body: "Reply",
                    type: "DiffNote",
                    position: rawPosition
                ),
            ]
        )
        let second = makeTestDiscussion(
            id: "second",
            notes: [
                makeTestDiscussionNote(
                    id: 201,
                    type: "DiffNote",
                    position: rawPosition
                ),
            ]
        )

        let index = GitLabDiffDiscussionIndex(
            discussions: [
                first,
                second,
            ],
            currentVersion: version
        )

        #expect(
            index.discussions(
                at: linePosition
            )
            .map(\.id)
                == ["first", "second"]
        )
        #expect(index.currentDiscussionCount == 2)
        #expect(index.outdatedDiscussions.isEmpty)
        #expect(index.unmappedDiscussions.isEmpty)
    }

    @Test("Separates outdated, malformed, and non-positional threads")
    func classifiesOtherThreads() throws {
        let currentVersion = try makeVersion()
        let outdatedVersion = try makeVersion(
            headSHA: "old-head"
        )
        let outdated = makeTestDiscussion(
            id: "outdated",
            notes: [
                makeTestDiscussionNote(
                    type: "DiffNote",
                    position:
                        makeRawPosition(
                            version:
                                outdatedVersion
                        )
                ),
            ]
        )
        let partial = makeTestDiscussion(
            id: "partial",
            notes: [
                makeTestDiscussionNote(
                    type: "DiffNote",
                    position:
                        GitLabDiscussionPosition(
                            baseSHA: nil,
                            startSHA: "start",
                            headSHA: "head",
                            positionType:
                                "text",
                            oldPath:
                                "Sources/File.swift",
                            newPath:
                                "Sources/File.swift",
                            oldLine: 20,
                            newLine: 21
                        )
                ),
            ]
        )
        let nonText = makeTestDiscussion(
            id: "non-text",
            notes: [
                makeTestDiscussionNote(
                    type: "DiffNote",
                    position:
                        GitLabDiscussionPosition(
                            baseSHA:
                                currentVersion
                                .baseSHA,
                            startSHA:
                                currentVersion
                                .startSHA,
                            headSHA:
                                currentVersion
                                .headSHA,
                            positionType:
                                "image",
                            oldPath: "image.png",
                            newPath: "image.png"
                        )
                ),
            ]
        )
        let general = makeTestDiscussion(
            id: "general"
        )

        let index = GitLabDiffDiscussionIndex(
            discussions: [
                general,
                outdated,
                partial,
                nonText,
            ],
            currentVersion: currentVersion
        )

        #expect(
            index.outdatedDiscussions
                .map(\.id) == ["outdated"]
        )
        #expect(
            index.unmappedDiscussions
                .map(\.id)
                == [
                    "partial",
                    "non-text",
                ]
        )
        #expect(index.currentDiscussionCount == 0)
        #expect(index.positionedDiscussionCount == 3)
    }

    @Test("Keeps accounts and versions out of position descriptions")
    func redactsPositionDescription() throws {
        let position = try #require(
            makeRawPosition(
                version: makeVersion()
            ).linePosition
        )

        #expect(
            !String(describing: position)
                .contains("Sources/File.swift")
        )
        #expect(
            !String(reflecting: position)
                .contains("head")
        )
    }

    private func makeVersion(
        headSHA: String = "head"
    ) throws -> GitLabMergeRequestDiffVersionIdentity {
        try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "base",
                startSHA: "start",
                headSHA: headSHA
            )
        )
    }

    private func makeRawPosition(
        version:
            GitLabMergeRequestDiffVersionIdentity
    ) -> GitLabDiscussionPosition {
        GitLabDiscussionPosition(
            baseSHA: version.baseSHA,
            startSHA: version.startSHA,
            headSHA: version.headSHA,
            positionType: "text",
            oldPath: "Sources/File.swift",
            newPath: "Sources/File.swift",
            oldLine: 20,
            newLine: 21
        )
    }
}
