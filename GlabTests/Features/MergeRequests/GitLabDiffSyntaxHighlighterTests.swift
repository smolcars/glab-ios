import Foundation
import Testing
@testable import Glab

@Suite("GitLab diff syntax highlighting")
struct GitLabDiffSyntaxHighlighterTests {
    @Test("Maps old and new hunk projections back to diff rows")
    func mapsBothSides() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            """
            @@ -1,3 +1,3 @@
             let shared = true
            -let oldValue = 1
            +const newValue = 1
             print(shared)
            """
        )
        let syntaxHighlighter = RecordingSyntaxHighlighter()
        let result = try await GitLabDiffSyntaxHighlighter(
            syntaxHighlighter: syntaxHighlighter
        )
        .highlight(
            GitLabDiffSyntaxHighlightRequest(
                document: document,
                oldLanguage: try language(
                    "Sources/File.swift"
                ),
                newLanguage: try language(
                    "Sources/File.js"
                ),
                theme: .dark
            )
        )

        #expect(result.count == 4)
        #expect(language(in: result[0]) == "javascript")
        #expect(language(in: result[1]) == "swift")
        #expect(language(in: result[2]) == "javascript")
        #expect(language(in: result[3]) == "javascript")
        #expect(
            result[1]?.attributedString.string
                == "let oldValue = 1"
        )
        #expect(
            result[2]?.attributedString.string
                == "const newValue = 1"
        )

        let requests = await syntaxHighlighter.requests
        #expect(
            requests
                == [
                    RecordedSyntaxRequest(
                        source:
                            "let shared = true\n"
                            + "let oldValue = 1\n"
                            + "print(shared)",
                        language: "swift",
                        theme: .dark
                    ),
                    RecordedSyntaxRequest(
                        source:
                            "let shared = true\n"
                            + "const newValue = 1\n"
                            + "print(shared)",
                        language: "javascript",
                        theme: .dark
                    ),
                ]
        )
    }

    @Test("Highlights each hunk independently")
    func isolatesHunks() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            """
            @@ -1 +1 @@
            -let oldFirst = 1
            +let newFirst = 1
            @@ -20 +20 @@
            -let oldLast = 20
            +let newLast = 20
            """
        )
        let syntaxHighlighter = RecordingSyntaxHighlighter()
        let language = try language(
            "Sources/File.swift"
        )

        _ = try await GitLabDiffSyntaxHighlighter(
            syntaxHighlighter: syntaxHighlighter
        )
        .highlight(
            GitLabDiffSyntaxHighlightRequest(
                document: document,
                oldLanguage: language,
                newLanguage: language,
                theme: .light
            )
        )

        let sources = await syntaxHighlighter.requests
            .map(\.source)
        #expect(
            sources
                == [
                    "let oldFirst = 1",
                    "let newFirst = 1",
                    "let oldLast = 20",
                    "let newLast = 20",
                ]
        )
    }

    @Test("Keeps the supported side when a rename changes language")
    func supportsOneSideOfRename() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            """
            @@ -1 +1 @@
            -plain text
            +let value = 1
            """
        )
        let language = try language(
            "Sources/File.swift"
        )

        let result = try await GitLabDiffSyntaxHighlighter(
            syntaxHighlighter: RecordingSyntaxHighlighter()
        )
        .highlight(
            GitLabDiffSyntaxHighlightRequest(
                document: document,
                oldLanguage: nil,
                newLanguage: language,
                theme: .light
            )
        )

        #expect(!result.keys.contains(0))
        #expect(result[1]?.attributedString.string == "let value = 1")
    }

    @Test("Rejects a highlighter result that does not match the projection")
    func rejectsMismatchedOutput() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            "@@ -0,0 +1 @@\n+let value = 1"
        )
        let language = try language(
            "Sources/File.swift"
        )

        let result = try await GitLabDiffSyntaxHighlighter(
            syntaxHighlighter:
                MismatchedSyntaxHighlighter()
        )
        .highlight(
            GitLabDiffSyntaxHighlightRequest(
                document: document,
                oldLanguage: language,
                newLanguage: language,
                theme: .light
            )
        )

        #expect(result.isEmpty)
    }

    @Test("Observes cancellation")
    func cancellation() async throws {
        let document = try await GitLabUnifiedDiffParser.parse(
            "@@ -0,0 +1 @@\n+let value = 1"
        )
        let language = try language(
            "Sources/File.swift"
        )
        let highlighter = GitLabDiffSyntaxHighlighter(
            syntaxHighlighter: RecordingSyntaxHighlighter()
        )
        let request = GitLabDiffSyntaxHighlightRequest(
            document: document,
            oldLanguage: language,
            newLanguage: language,
            theme: .light
        )
        let task = Task {
            try await highlighter.highlight(request)
        }
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }

    @Test("Skips oversized projected source before highlighting")
    func skipsOversizedProjection() async throws {
        let oversizedLine = String(
            repeating: "x",
            count:
                GitLabDiffSyntaxHighlighter
                    .maximumProjectedSourceByteCount + 1
        )
        let line = GitLabDiffLine(
            ordinal: 0,
            kind: .addition,
            oldLineNumber: nil,
            newLineNumber: 1,
            text: oversizedLine
        )
        let document = GitLabParsedDiffDocument(
            items: [
                .hunkHeader(
                    ordinal: 0,
                    text: "@@ -0,0 +1 @@"
                ),
                .addition(line),
            ],
            hunks: [
                GitLabDiffHunk(
                    ordinal: 0,
                    header: "@@ -0,0 +1 @@",
                    oldStart: 0,
                    oldCount: 0,
                    newStart: 1,
                    newCount: 1,
                    renderItemIndex: 0
                ),
            ],
            lineCount: 2,
            estimatedCacheCost: oversizedLine.utf8.count,
            maximumRenderedColumnCount: oversizedLine.count
        )
        let syntaxHighlighter = RecordingSyntaxHighlighter()

        let result = try await GitLabDiffSyntaxHighlighter(
            syntaxHighlighter: syntaxHighlighter
        )
        .highlight(
            GitLabDiffSyntaxHighlightRequest(
                document: document,
                oldLanguage: nil,
                newLanguage: try language("File.swift"),
                theme: .dark
            )
        )

        #expect(result.isEmpty)
        #expect(await syntaxHighlighter.requests.isEmpty)
    }

    private func language(
        in text: GitLabDiffHighlightedLine?
    ) -> String? {
        guard
            let text,
            text.attributedString.length > 0
        else {
            return nil
        }
        return text.attributedString.attribute(
            Self.languageAttribute,
            at: 0,
            effectiveRange: nil
        ) as? String
    }

    private func language(
        _ fileName: String
    ) throws -> GitLabSyntaxLanguage {
        try #require(
            GitLabSyntaxLanguage(
                fileName: fileName
            )
        )
    }

    nonisolated fileprivate static let languageAttribute =
        NSAttributedString.Key(
            "GitLabDiffSyntaxHighlighterTests.language"
        )
}

private struct RecordedSyntaxRequest:
    Equatable,
    Sendable
{
    let source: String
    let language: String
    let theme: GitLabSyntaxTheme
}

private actor RecordingSyntaxHighlighter:
    GitLabSyntaxHighlighting
{
    private(set) var requests:
        [RecordedSyntaxRequest] = []

    func highlight(
        _ request: GitLabSyntaxHighlightRequest
    ) async -> GitLabHighlightedText? {
        let source = request.renderedSource
        requests.append(
            RecordedSyntaxRequest(
                source: source,
                language:
                    request.language.identifier,
                theme: request.theme
            )
        )
        return GitLabHighlightedText(
            NSAttributedString(
                string: source,
                attributes: [
                    GitLabDiffSyntaxHighlighterTests
                        .languageAttribute:
                        request.language.identifier,
                ]
            )
        )
    }
}

private struct MismatchedSyntaxHighlighter:
    GitLabSyntaxHighlighting
{
    func highlight(
        _ request: GitLabSyntaxHighlightRequest
    ) async -> GitLabHighlightedText? {
        GitLabHighlightedText(
            NSAttributedString(
                string: "different source"
            )
        )
    }
}
