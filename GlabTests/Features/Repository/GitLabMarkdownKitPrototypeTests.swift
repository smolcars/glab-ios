import Foundation
import Testing
import UIKit
@testable import Glab

@Suite("MarkdownKit repository prototype")
struct GitLabMarkdownKitPrototypeTests {
    @Test(
        "Renders Bark-style raw HTML instead of showing tags"
    )
    func rendersRawHTML() async throws {
        let source =
            """
            <div align="center">
            <h1>Bark: Ark on bitcoin</h1>
            <p>Fast, low-cost payments. <a href="https://example.com/docs">Docs</a></p>
            </div>
            """

        let rendered = try #require(
            await GitLabMarkdownKitPrototypeRenderer
                .render(
                    source: source,
                    palette: .dark
                )
        )

        #expect(
            rendered.string.contains(
                "Bark: Ark on bitcoin"
            )
        )
        #expect(
            rendered.string.contains(
                "Fast, low-cost payments. Docs"
            )
        )
        #expect(!rendered.string.contains("<div"))
        #expect(!rendered.string.contains("<h1"))

        let headingRange = (rendered.string as NSString)
            .range(of: "Bark: Ark on bitcoin")
        let paragraphStyle = try #require(
            rendered.attribute(
                .paragraphStyle,
                at: headingRange.location,
                effectiveRange: nil
            ) as? NSParagraphStyle
        )
        #expect(paragraphStyle.alignment == .center)
    }

    @Test("Does not expose script content as text")
    func omitsScriptContent() async throws {
        let rendered = try #require(
            await GitLabMarkdownKitPrototypeRenderer
                .render(
                    source:
                        "<script>alert('unsafe')</script>\n\nVisible",
                    palette: .light
                )
        )

        #expect(rendered.string.contains("Visible"))
        #expect(!rendered.string.contains("unsafe"))
        #expect(!rendered.string.contains("script"))
    }

    @Test("Keeps all comparison modes available")
    func exposesComparisonModes() {
        #expect(
            GitLabRepositoryFilePresentation
                .allCases
                == [
                    .markdownKit,
                    .rendered,
                    .raw,
                ]
        )
        #expect(
            GitLabRepositoryFilePresentation
                .markdownKit.title
                == "MarkdownKit Prototype"
        )
    }
}
