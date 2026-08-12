import Foundation
import Testing
@testable import Glab

@Suite("GitLab syntax highlighting")
struct GitLabSyntaxHighlighterTests {
    @Test("Maps Markdown fence aliases without auto-detecting plain text")
    func markdownLanguageAliases() {
        #expect(
            GitLabSyntaxLanguage(
                markdownFence: " Swift "
            )?.identifier == "swift"
        )
        #expect(
            GitLabSyntaxLanguage(
                markdownFence: "{.js} line-numbers"
            )?.identifier == "javascript"
        )
        #expect(
            GitLabSyntaxLanguage(
                markdownFence: "objective-c"
            )?.identifier == "objectivec"
        )
        #expect(
            GitLabSyntaxLanguage(
                markdownFence: "plaintext"
            ) == nil
        )
        #expect(
            GitLabSyntaxLanguage(
                markdownFence: nil
            ) == nil
        )
    }

    @Test("Maps exact filenames and common language extensions")
    func filenameLanguages() {
        #expect(
            GitLabSyntaxLanguage(
                fileName: "Dockerfile"
            )?.identifier == "dockerfile"
        )
        #expect(
            GitLabSyntaxLanguage(
                fileName: "Sources/main.mm"
            )?.identifier == "objectivec"
        )
        #expect(
            GitLabSyntaxLanguage(
                fileName: "schema.graphql"
            )?.identifier == "graphql"
        )
        #expect(
            GitLabSyntaxLanguage(
                fileName: "notes.txt"
            ) == nil
        )
    }

    @Test("Preserves source exactly and removes layout attributes")
    func preservesSource() async throws {
        let source =
            "  let value = \"<tag> & text\"  \n\n"
        let highlighter = GitLabSyntaxHighlighter()
        let language = try #require(
            GitLabSyntaxLanguage(
                markdownFence: "swift"
            )
        )

        let result = try #require(
            await highlighter.highlight(
                GitLabSyntaxHighlightRequest(
                    source: source,
                    language: language,
                    theme: .light
                )
            )
        )

        #expect(result.attributedString.string == source)
        let fullRange = NSRange(
            location: 0,
            length: result.attributedString.length
        )
        #expect(
            result.attributedString.attribute(
                .font,
                at: 0,
                effectiveRange: nil
            ) == nil
        )
        #expect(
            result.attributedString.attribute(
                .paragraphStyle,
                at: 0,
                effectiveRange: nil
            ) == nil
        )
        var coloredRangeCount = 0
        result.attributedString.enumerateAttribute(
            .foregroundColor,
            in: fullRange
        ) { value, _, _ in
            if value != nil {
                coloredRangeCount += 1
            }
        }
        #expect(coloredRangeCount > 1)
    }

    @Test("Joins rendered source lines without losing empty lines")
    func renderedLines() async throws {
        let highlighter = GitLabSyntaxHighlighter()
        let language = try #require(
            GitLabSyntaxLanguage(
                fileName: "main.swift"
            )
        )

        let result = try #require(
            await highlighter.highlight(
                GitLabSyntaxHighlightRequest(
                    lines: [
                        "let value = 1",
                        "",
                        "print(value)",
                    ],
                    language: language,
                    theme: .dark
                )
            )
        )

        #expect(
            result.attributedString.string
                == "let value = 1\n\nprint(value)"
        )
    }

    @Test("Bounds input and least-recently-used cache size")
    func boundedCache() async throws {
        let highlighter = GitLabSyntaxHighlighter(
            maximumDocumentCount: 1,
            maximumSourceCost: 128
        )
        let language = try #require(
            GitLabSyntaxLanguage(
                markdownFence: "swift"
            )
        )
        for source in ["let first = 1", "let second = 2"] {
            _ = try #require(
                await highlighter.highlight(
                    GitLabSyntaxHighlightRequest(
                        source: source,
                        language: language,
                        theme: .light
                    )
                )
            )
        }

        #expect(await highlighter.cacheEntryCount == 1)
        #expect(
            await highlighter.cacheSourceCost
                == "let second = 2".utf8.count
        )

        let oversized = String(
            repeating: "x",
            count:
                GitLabSyntaxHighlighter
                .maximumInputByteCount + 1
        )
        #expect(
            await highlighter.highlight(
                GitLabSyntaxHighlightRequest(
                    source: oversized,
                    language: language,
                    theme: .light
                )
            ) == nil
        )
        #expect(await highlighter.cacheEntryCount == 1)
    }
}
