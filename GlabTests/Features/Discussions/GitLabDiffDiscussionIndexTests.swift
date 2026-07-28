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
        #expect(
            index.currentDiscussions
                .map(\.id)
                == ["first", "second"]
        )
        #expect(
            index.allPositionedDiscussions
                .map(\.id)
                == ["first", "second"]
        )
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
        #expect(
            index.allPositionedDiscussions
                .map(\.id)
                == [
                    "outdated",
                    "partial",
                    "non-text",
                ]
        )
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

    @Test("Builds constant-time line markers for read and write access")
    func buildsLineMarkers() throws {
        let version = try makeVersion()
        let rawPosition = makeRawPosition(
            version: version
        )
        let discussion = makeTestDiscussion(
            id: "thread",
            notes: [
                makeTestDiscussionNote(
                    type: "DiffNote",
                    position: rawPosition
                ),
            ]
        )
        let index = GitLabDiffDiscussionIndex(
            discussions: [discussion],
            currentVersion: version
        )
        let readOnly =
            GitLabDiffDiscussionContext(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                index: index,
                revision: 4,
                allowsCommenting: false
            )
        let write =
            GitLabDiffDiscussionContext(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                index: index,
                revision: 4,
                allowsCommenting: true
            )
        let threadedLine = GitLabDiffLine(
            ordinal: 0,
            kind: .context,
            oldLineNumber: 20,
            newLineNumber: 21,
            text: "threaded"
        )
        let unthreadedLine = GitLabDiffLine(
            ordinal: 1,
            kind: .addition,
            oldLineNumber: nil,
            newLineNumber: 22,
            text: "unthreaded"
        )

        #expect(
            readOnly.marker(
                for: threadedLine
            )?.discussionCount == 1
        )
        #expect(
            readOnly.marker(
                for: unthreadedLine
            ) == nil
        )
        #expect(
            write.marker(
                for: unthreadedLine
            )?.discussionCount == 0
        )
        #expect(
            write.marker(
                for: unthreadedLine
            )?.allowsCommenting == true
        )
    }

    @Test("Indexes two thousand mixed discussions within budget")
    func indexPerformanceBudget() throws {
        let currentVersion = try makeVersion()
        let oldVersion = try makeVersion(
            headSHA: "old-head"
        )
        let discussions = (0..<2_000).map {
            index in
            let position:
                GitLabDiscussionPosition
            if index < 1_800 {
                let line = index % 500 + 1
                position =
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
                        positionType: "text",
                        oldPath:
                            "Sources/File.swift",
                        newPath:
                            "Sources/File.swift",
                        oldLine: line,
                        newLine: line
                    )
            } else if index < 1_900 {
                position =
                    GitLabDiscussionPosition(
                        baseSHA:
                            oldVersion.baseSHA,
                        startSHA:
                            oldVersion.startSHA,
                        headSHA:
                            oldVersion.headSHA,
                        positionType: "text",
                        oldPath:
                            "Sources/File.swift",
                        newPath:
                            "Sources/File.swift",
                        oldLine: index,
                        newLine: index
                    )
            } else {
                position =
                    GitLabDiscussionPosition(
                        baseSHA: nil,
                        startSHA: "start",
                        headSHA: "head",
                        positionType: "text",
                        oldPath:
                            "Sources/File.swift",
                        newPath:
                            "Sources/File.swift",
                        oldLine: index,
                        newLine: index
                    )
            }
            return makeTestDiscussion(
                id: "thread-\(index)",
                notes: [
                    makeTestDiscussionNote(
                        id: index + 1,
                        type: "DiffNote",
                        position: position
                    ),
                ]
            )
        }

        var samples: [Double] = []
        samples.reserveCapacity(30)
        for _ in 0..<30 {
            let start = ContinuousClock.now
            let index =
                GitLabDiffDiscussionIndex(
                    discussions: discussions,
                    currentVersion:
                        currentVersion
                )
            #expect(
                index.positionedDiscussionCount
                    == 2_000
            )
            samples.append(
                milliseconds(
                    start.duration(
                        to: ContinuousClock.now
                    )
                )
            )
        }
        let p95 = percentile95(samples)
        print(
            "DIFF_DISCUSSION_INDEX_PERFORMANCE "
                + "discussions=2000 p95_ms="
                + p95.formatted(
                    .number.precision(
                        .fractionLength(3)
                    )
                )
        )

        #if DEBUG
            #expect(p95 < 40)
        #else
            #expect(p95 < 20)
        #endif
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

    private func percentile95(
        _ samples: [Double]
    ) -> Double {
        let sorted = samples.sorted()
        let index = min(
            sorted.count - 1,
            Int(
                ceil(
                    Double(sorted.count)
                        * 0.95
                )
            ) - 1
        )
        return sorted[index]
    }

    private func milliseconds(
        _ duration: Duration
    ) -> Double {
        let components = duration.components
        return
            Double(components.seconds)
                * 1_000
            + Double(components.attoseconds)
                / 1_000_000_000_000_000
    }
}
