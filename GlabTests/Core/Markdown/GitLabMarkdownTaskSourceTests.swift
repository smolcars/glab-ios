import Foundation
import Testing
@testable import Glab

@Suite("GitLab Markdown task source")
struct GitLabMarkdownTaskSourceTests {
    @Test("Indexes supported list tasks in exact source order")
    func indexesSupportedTasks() async throws {
        let source =
            GitLabMarkdownFixtures.taskSourceComplex
        let tasks =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)

        #expect(
            tasks.map(\.state)
                == [
                    .incomplete,
                    .complete,
                    .complete,
                    .inapplicable,
                    .incomplete,
                    .complete,
                    .incomplete,
                    .complete,
                ]
        )
        #expect(
            tasks.map(\.sourceID.markerUTF8Offset)
                == markerOffsets(in: source)
        )
        #expect(
            Set(tasks.map(\.sourceID)).count
                == tasks.count
        )
    }

    @Test("Excludes unsupported and ambiguous task-like source")
    func excludesUnsupportedSource() async throws {
        let tasks =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(
                    in:
                        GitLabMarkdownFixtures
                            .taskSourceExcluded
                )

        #expect(tasks.count == 1)
        #expect(tasks.first?.state == .incomplete)
    }

    @Test("Preserves identities across Unicode and mixed line endings")
    func unicodeAndLineEndings() async throws {
        let source =
            GitLabMarkdownFixtures
                .taskSourceMixedLineEndings
        let first =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
        let second =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)

        #expect(first == second)
        #expect(first.count == 3)
        #expect(
            first.map(\.sourceID.markerUTF8Offset)
                == markerOffsets(in: source)
        )
    }

    @Test("Toggles only the selected marker byte")
    func exactByteRewrite() async throws {
        let source =
            GitLabMarkdownFixtures.taskSourceComplex
        let tasks =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)

        for task in tasks
        where task.state != .inapplicable {
            let desired:
                GitLabMarkdownTaskState =
                    task.state == .complete
                    ? .incomplete
                    : .complete
            let rewritten =
                try await GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source,
                        task: task,
                        to: desired
                    )
            let originalBytes =
                Array(source.utf8)
            let rewrittenBytes =
                Array(rewritten.utf8)
            let differences =
                zip(
                    originalBytes,
                    rewrittenBytes
                )
                .enumerated()
                .compactMap {
                    index,
                    pair in
                    pair.0 == pair.1
                        ? nil
                        : index
                }

            #expect(
                rewrittenBytes.count
                    == originalBytes.count
            )
            #expect(
                differences
                    == [
                        task.sourceID
                            .markerUTF8Offset
                            + 1
                    ]
            )
        }
    }

    @Test("Uppercase completion toggles without normalizing other bytes")
    func uppercaseCompletion() async throws {
        let source =
            GitLabMarkdownFixtures.taskSourceComplex
        let tasks =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
        let uppercaseOffset = try #require(
            utf8Offset(
                of: "[X]",
                in: source
            )
        )
        let task = try #require(
            tasks.first {
                $0.sourceID.markerUTF8Offset
                    == uppercaseOffset
            }
        )

        let rewritten =
            try await GitLabMarkdownTaskSourceRewriter
                .rewrite(
                    source,
                    task: task,
                    to: .incomplete
                )

        #expect(
            Array(rewritten.utf8)[
                uppercaseOffset
                    ..< uppercaseOffset + 3
            ]
                == Array("[ ]".utf8)[...]
        )
        #expect(
            Array(rewritten.utf8)
                .enumerated()
                .allSatisfy {
                    index,
                    byte in
                    index == uppercaseOffset + 1
                        || byte
                            == Array(source.utf8)[
                                index
                            ]
                }
        )
    }

    @Test("Rejects stale, inapplicable, no-op, and fabricated tasks")
    func rejectsUnsafeRewrites() async throws {
        let source = "- [ ] Ready\n- [~] Skip"
        let tasks =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
        let incomplete = try #require(
            tasks.first {
                $0.state == .incomplete
            }
        )
        let inapplicable = try #require(
            tasks.first {
                $0.state == .inapplicable
            }
        )

        await #expect(
            throws:
                GitLabMarkdownTaskRewriteError
                    .staleSource
        ) {
            _ =
                try await GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source + "\n",
                        task: incomplete,
                        to: .complete
                    )
        }
        await #expect(
            throws:
                GitLabMarkdownTaskRewriteError
                    .inapplicable
        ) {
            _ =
                try await GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source,
                        task: inapplicable,
                        to: .complete
                    )
        }
        await #expect(
            throws:
                GitLabMarkdownTaskRewriteError
                    .noChange
        ) {
            _ =
                try await GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source,
                        task: incomplete,
                        to: .incomplete
                    )
        }

        let fabricated =
            GitLabMarkdownIndexedTask(
                sourceID:
                    GitLabMarkdownTaskSourceID(
                        sourceDigest:
                            incomplete
                                .sourceID
                                .sourceDigest,
                        markerUTF8Offset: 1
                    ),
                state: .incomplete
            )
        await #expect(
            throws:
                GitLabMarkdownTaskRewriteError
                    .invalidTask
        ) {
            _ =
                try await GitLabMarkdownTaskSourceRewriter
                    .rewrite(
                        source,
                        task: fabricated,
                        to: .complete
                    )
        }
    }

    @Test("Task identity descriptions and mirrors redact source data")
    func redactedIdentity() async throws {
        let privateText =
            "private customer task"
        let task = try #require(
            try await GitLabMarkdownTaskSourceIndex
                .tasks(
                    in: "- [ ] \(privateText)"
                )
                .first
        )
        let descriptions = [
            task.sourceID.description,
            task.sourceID.debugDescription,
            String(reflecting: task.sourceID),
        ]

        #expect(
            descriptions.allSatisfy {
                !$0.contains(privateText)
                    && !$0.contains("5b")
            }
        )
        #expect(
            task.sourceID.customMirror.children
                .contains {
                    $0.label == "redacted"
                }
        )
    }

    private func markerOffsets(
        in source: String
    ) -> [Int] {
        let bytes = Array(source.utf8)
        guard bytes.count >= 3 else {
            return []
        }
        return (0...(bytes.count - 3))
            .compactMap { index in
                guard
                    bytes[index]
                        == Character("[")
                            .asciiValue,
                    bytes[index + 2]
                        == Character("]")
                            .asciiValue,
                    bytes[index + 1]
                        == Character(" ")
                            .asciiValue
                        || bytes[index + 1]
                            == Character("x")
                                .asciiValue
                        || bytes[index + 1]
                            == Character("X")
                                .asciiValue
                        || bytes[index + 1]
                            == Character("~")
                                .asciiValue
                else {
                    return nil
                }
                return index
            }
    }

    private func utf8Offset(
        of value: String,
        in source: String
    ) -> Int? {
        guard
            let range = source.range(
                of: value
            )
        else {
            return nil
        }
        return source.utf8.distance(
            from: source.utf8.startIndex,
            to: range.lowerBound
        )
    }
}
