import Foundation
import Testing
@testable import Glab

@Suite("Read-only Markdown renderer")
struct GitLabReadOnlyMarkdownParserTests {
    @Test("Renders Bark-style HTML and routes images through native blocks")
    func barkStyleReadme() async throws {
        let source =
            """
            ![bark: Ark on bitcoin](assets/bark-header-white.jpg)

            <div align="center">
            <h1>Bark: Ark on bitcoin</h1>
            <p>Fast, low-cost payments on bitcoin.</p>
            </div>

            <p align="center">
              <a href="https://docs.example.com">Docs</a> ·
              <a href="https://gitlab.example.com/group/project/issues">Issues</a>
            </p>

            <div align="center">

            [![Release](https://img.shields.io/badge/build-passing.svg)](https://gitlab.example.com/group/project/tags)
            [![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

            </div>
            """

        let document = try await GitLabReadOnlyMarkdownParser
            .parse(
                makeRepositoryRequest(source: source)
            )

        let header = try #require(
            document.blocks.compactMap(\.image).first
        )
        #expect(
            header.url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/10/repository/files/docs%2Fassets%2Fbark-header-white.jpg/raw?ref=main"
        )

        let richText = document.blocks
            .compactMap { block -> GitLabMarkdownRichText? in
                guard case let .richText(value) = block else {
                    return nil
                }
                return value
            }
        let renderedHTML = richText
            .map(\.plainText)
            .joined(separator: " ")
        #expect(renderedHTML.contains("Bark: Ark on bitcoin"))
        #expect(renderedHTML.contains("Fast, low-cost payments"))
        #expect(renderedHTML.contains("Docs"))
        #expect(!renderedHTML.contains("<div"))
        #expect(!renderedHTML.contains("<h1"))

        let badgeGroup = try #require(
            document.blocks.compactMap(\.imageGroup).first
        )
        #expect(badgeGroup.alignment == .center)
        #expect(badgeGroup.images.count == 2)
        #expect(
            badgeGroup.images.map(\.altText)
                == ["Release", "License"]
        )
        #expect(
            badgeGroup.images[0].linkURL?.absoluteString
                == "https://gitlab.example.com/group/project/tags"
        )
        #expect(
            badgeGroup.images[1].linkURL?.absoluteString
                == "https://gitlab.example.com/group/project/-/blob/main/docs/LICENSE"
        )
    }

    @Test("Removes unsafe HTML while keeping visible content")
    func unsafeHTML() async throws {
        let document = try await GitLabReadOnlyMarkdownParser
            .parse(
                makeRepositoryRequest(
                    source:
                        """
                        <script>alert('unsafe')</script>
                        <p onclick="alert('unsafe')">Visible</p>
                        """
                )
            )

        #expect(document.plainText.contains("Visible"))
        #expect(!document.plainText.contains("unsafe"))
        #expect(!document.plainText.contains("script"))
    }

    @Test("Preserves links around raw HTML images")
    func linkedHTMLImage() async throws {
        let document = try await GitLabReadOnlyMarkdownParser
            .parse(
                makeRepositoryRequest(
                    source:
                        """
                        <p align="center"><a href="releases"><img alt="release" src="assets/release.svg"></a></p>
                        """
                )
            )
        let group = try #require(
            document.blocks.compactMap(\.imageGroup).first
        )
        let image = try #require(group.images.first)

        #expect(group.alignment == .center)
        #expect(
            image.linkURL?.absoluteString
                == "https://gitlab.example.com/group/project/-/blob/main/docs/releases"
        )
    }

    @Test("Displays task lists without creating mutable task identities")
    func readOnlyTasks() async throws {
        let document = try await GitLabReadOnlyMarkdownParser
            .parse(
                makeIssueNoteRequest(
                    source:
                        """
                        - [x] Shipped
                        - [ ] Follow up
                        """
                )
            )
        let list = try #require(
            document.blocks.compactMap(\.list).first
        )

        #expect(
            list.items.map(\.taskState)
                == [.complete, .incomplete]
        )
        #expect(
            list.items.map(\.plainText)
                == ["Shipped", "Follow up"]
        )
        #expect(
            list.items.allSatisfy {
                $0.taskSourceID == nil
            }
        )
        #expect(!document.hasMappedMutableTask)
    }

    @Test("Renders uploaded media in comments without leaking GitLab attributes")
    func uploadedCommentMedia() async throws {
        let document = try await GitLabReadOnlyMarkdownParser
            .parse(
                makeIssueNoteRequest(
                    source:
                        """
                        ![ledger](/uploads/abc/ledger.png){width=900 height=335}

                        ![demo](/uploads/abc/demo.mov)
                        """
                )
            )
        let media = document.blocks.compactMap(\.image)

        #expect(media.count == 2)
        let image = try #require(media.first)
        #expect(
            image.url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/10/uploads/abc/ledger.png"
        )
        #expect(
            image.fallbackURLs.map(\.absoluteString)
                == [
                    "https://gitlab.example.com/-/project/10/uploads/abc/ledger.png",
                    "https://gitlab.example.com/group/project/uploads/abc/ledger.png",
                ]
        )
        #expect(
            image.dimensions?.width
                == GitLabMarkdownMediaDimension(
                    value: 900,
                    unit: .pixels
                )
        )
        #expect(
            image.dimensions?.height
                == GitLabMarkdownMediaDimension(
                    value: 335,
                    unit: .pixels
                )
        )
        #expect(!document.plainText.contains("width="))
        #expect(media[1].kind == .video)
        #expect(
            media[1].browserURL?.absoluteString
                == "https://gitlab.example.com/-/project/10/uploads/abc/demo.mov"
        )
    }

    private func makeRepositoryRequest(
        source: String
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 7
            ),
            resource: .repositoryFile(
                projectID: 10,
                ref: "main",
                path: "docs/README.md",
                blobID: "readme-blob"
            ),
            source: source,
            webURL: URL(
                string:
                    "https://gitlab.example.com/group/project/-/blob/main/docs/README.md"
            )
        )
    }

    private func makeIssueNoteRequest(
        source: String
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 7
            ),
            resource: .issueNote(
                projectID: 10,
                issueIID: 42,
                noteID: 9
            ),
            source: source,
            webURL: URL(
                string:
                    "https://gitlab.example.com/group/project/-/issues/42"
            )
        )
    }
}
