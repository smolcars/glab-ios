import Foundation
import Testing
@testable import Glab

@Suite("GitLab unified diff parser")
struct GitLabUnifiedDiffParserTests {
    @Test("Defines deterministic parser fixtures")
    func fixtureSizes() {
        #expect(
            sourceLineCount(
                GitLabUnifiedDiffFixtures.oneThousandLines
            ) == 1_000
        )
        #expect(
            sourceLineCount(
                GitLabUnifiedDiffFixtures.tenThousandLines
            ) == 10_000
        )
        #expect(
            sourceLineCount(
                GitLabUnifiedDiffFixtures.fiftyThousandLines
            ) == 50_000
        )
    }

    @Test("Parses metadata, hunks, line kinds, and exact line numbers")
    func parsesRepresentativePatch() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            GitLabUnifiedDiffFixtures.representative
        )

        #expect(document.hunks.count == 2)
        #expect(
            document.hunks[0]
                == GitLabDiffHunk(
                    ordinal: 0,
                    header:
                        "@@ -2,3 +2,4 @@ struct Example {",
                    oldStart: 2,
                    oldCount: 3,
                    newStart: 2,
                    newCount: 4,
                    renderItemIndex: 4
                )
        )
        #expect(
            document.hunks[1]
                == GitLabDiffHunk(
                    ordinal: 1,
                    header:
                        "@@ -10 +11,0 @@ extension Example {",
                    oldStart: 10,
                    oldCount: 1,
                    newStart: 11,
                    newCount: 0,
                    renderItemIndex: 11
                )
        )

        let lines = document.items.compactMap(\.line)
        #expect(
            lines.map(\.kind)
                == [
                    .context,
                    .deletion,
                    .addition,
                    .addition,
                    .context,
                    .deletion,
                ]
        )
        #expect(
            lines.map(\.oldLineNumber)
                == [2, 3, nil, nil, 4, 10]
        )
        #expect(
            lines.map(\.newLineNumber)
                == [2, nil, 3, 4, 5, nil]
        )
        #expect(
            lines.map(\.text)
                == [
                    "let first = 1",
                    "let old = 2",
                    "let new = 2",
                    "let extra = 3",
                    "let last = 4",
                    "let removed = true",
                ]
        )
        #expect(
            document.items.contains(where: {
                if case .noNewlineMarker = $0 {
                    true
                } else {
                    false
                }
            })
        )
        #expect(document.lineCount == 13)
        #expect(document.estimatedCacheCost > 0)
        #expect(
            document.maximumRenderedLineLength
                == 50
        )
    }

    @Test("Accepts CRLF and a missing final newline")
    func acceptsLineEndings() async throws {
        let source =
            "@@ -1,2 +1,2 @@\r\n"
            + " same\r\n"
            + "-old\r\n"
            + "+new"
        let document = try await GitLabUnifiedDiffParser.parse(
            source
        )

        #expect(document.lineCount == 4)
        #expect(
            document.items.compactMap(\.line)
                .map(\.text)
                == ["same", "old", "new"]
        )
    }

    @Test("Uses count one when a hunk range omits its count")
    func defaultsHunkCounts() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            "@@ -7 +9 @@\n-old\n+new"
        )
        let hunk = try #require(document.hunks.first)

        #expect(hunk.oldStart == 7)
        #expect(hunk.oldCount == 1)
        #expect(hunk.newStart == 9)
        #expect(hunk.newCount == 1)
    }

    @Test("Preserves unknown content as metadata without false numbers")
    func preservesUnknownContent() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            "@@ -1 +1 @@\n?server metadata\n context"
        )

        #expect(document.items.count == 3)
        #expect(
            document.items[1]
                == .fileMetadata("?server metadata")
        )
        let line = try #require(document.items[2].line)
        #expect(line.oldLineNumber == 1)
        #expect(line.newLineNumber == 1)
    }

    @Test("Reports the one-based source line of a malformed hunk")
    func rejectsMalformedHunk() async {
        await #expect(
            throws:
                GitLabUnifiedDiffParserError
                .malformedHunk(sourceLine: 2)
        ) {
            try await GitLabUnifiedDiffParser.parse(
                "--- a/File.swift\n@@ broken"
            )
        }
    }

    @Test("Rejects a hunk with an invalid closing marker")
    func rejectsInvalidClosingMarker() async {
        await #expect(
            throws:
                GitLabUnifiedDiffParserError
                .malformedHunk(sourceLine: 1)
        ) {
            try await GitLabUnifiedDiffParser.parse(
                "@@ -1 +1 @@@"
            )
        }
    }

    @Test("Never overflows adversarial line-number counters")
    func lineNumberOverflow() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            """
            @@ -\(Int.max) +\(Int.max) @@
             first
             second
            """
        )
        let lines = document.items.compactMap(\.line)

        #expect(lines.count == 2)
        #expect(
            lines.map(\.oldLineNumber)
                == [Int.max, nil]
        )
        #expect(
            lines.map(\.newLineNumber)
                == [Int.max, nil]
        )
    }

    @Test("Observes cancellation")
    func cancellation() async {
        let task = Task {
            try await GitLabUnifiedDiffParser.parse(
                GitLabUnifiedDiffFixtures
                    .fiftyThousandLines
            )
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    private func sourceLineCount(
        _ source: String
    ) -> Int {
        source.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).count
    }
}
