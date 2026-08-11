import Foundation
import Testing
@testable import Glab

@Suite("GitLab Markdown parser")
struct GitLabMarkdownParserTests {
    @Test("Defines deterministic performance fixtures")
    func fixtureSizes() {
        let smallSize = GitLabMarkdownFixtures.small.utf8.count
        let mediumSize = GitLabMarkdownFixtures.medium.utf8.count
        let largeSize = GitLabMarkdownFixtures.large.utf8.count

        #expect(smallSize >= 200)
        #expect(smallSize < 1_024)
        #expect(mediumSize >= 10_000)
        #expect(mediumSize < 30_000)
        #expect(largeSize >= 100_000)
    }

    @Test("Parses common block and inline Markdown")
    func commonMarkdown() async throws {
        let document = try await GitLabMarkdownParser.parse(
            makeRequest(source: GitLabMarkdownFixtures.small)
        )

        let heading = try #require(
            document.blocks.compactMap(\.heading).first
        )
        #expect(heading.level == 1)
        #expect(heading.content.plainText == "Release readiness")
        #expect(
            heading.accessibilityLabel
                == "Heading level 1, Release readiness"
        )

        let paragraph = try #require(
            document.blocks.compactMap(\.paragraph).first
        )
        let intents = paragraph.attributedString.runs
            .compactMap(\.inlinePresentationIntent)
        #expect(intents.contains(where: { $0.contains(.stronglyEmphasized) }))
        #expect(intents.contains(where: { $0.contains(.emphasized) }))
        #expect(intents.contains(where: { $0.contains(.strikethrough) }))
        #expect(intents.contains(where: { $0.contains(.code) }))
        #expect(
            paragraph.attributedString.runs
                .contains(where: { $0.link != nil })
        )

        #expect(
            document.blocks.contains(where: {
                if case .thematicBreak = $0 {
                    true
                } else {
                    false
                }
            }) == false
        )
    }

    @Test("Preserves nested lists and GitLab task states")
    func listsAndTasks() async throws {
        let source = """
        3. Parent
           - [x] Complete
           - [ ] Incomplete
           - [~] Inapplicable
        4. Next
        """
        let document = try await GitLabMarkdownParser.parse(
            makeRequest(source: source)
        )
        let list = try #require(
            document.blocks.compactMap(\.list).first
        )

        #expect(list.kind == .ordered)
        #expect(list.items.map(\.ordinal) == [3, 4])
        let nested = try #require(
            list.items[0].blocks.compactMap(\.list).first
        )
        #expect(nested.kind == .unordered)
        #expect(
            nested.items.map(\.taskState)
                == [.complete, .incomplete, .inapplicable]
        )
        #expect(
            nested.items.map(\.plainText)
                == ["Complete", "Incomplete", "Inapplicable"]
        )
        #expect(
            nested.items.map(\.accessibilityLabel)
                == [
                    "Complete task, Complete",
                    "Incomplete task, Incomplete",
                    "Inapplicable task, Inapplicable",
                ]
        )
        #expect(
            document.hasMappedMutableTask
        )
        let completeID = try #require(
            nested.items[0].taskSourceID
        )
        let incompleteID = try #require(
            nested.items[1].taskSourceID
        )
        let inapplicableID = try #require(
            nested.items[2].taskSourceID
        )
        #expect(
            nested.items[0].indexedTask
                == GitLabMarkdownIndexedTask(
                    sourceID: completeID,
                    state: .complete
                )
        )
        #expect(
            nested.items[1].indexedTask
                == GitLabMarkdownIndexedTask(
                    sourceID: incompleteID,
                    state: .incomplete
                )
        )
        #expect(
            nested.items[2].indexedTask
                == GitLabMarkdownIndexedTask(
                    sourceID: inapplicableID,
                    state: .inapplicable
                )
        )
        #expect(
            completeID.markerUTF8Offset
                < incompleteID.markerUTF8Offset
        )
        #expect(
            incompleteID.markerUTF8Offset
                < inapplicableID.markerUTF8Offset
        )
    }

    @Test("Maps complex rendered tasks to exact source identities")
    func taskSourceIdentityMapping() async throws {
        let source =
            GitLabMarkdownFixtures.taskSourceComplex
        let request = try makeRequest(
            source: source
        )
        let document =
            try await GitLabMarkdownParser.parse(
                request
            )
        let renderedTasks =
            tasks(in: document.blocks)
        let indexedTasks =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)

        #expect(
            renderedTasks.map(\.state)
                == indexedTasks.map(\.state)
        )
        #expect(
            renderedTasks
                .compactMap(\.sourceID)
                == indexedTasks.map(\.sourceID)
        )
        #expect(
            Set(
                renderedTasks
                    .compactMap(\.sourceID)
            ).count
                == renderedTasks.count
        )
    }

    @Test("Fails closed when rendered and indexed task sequences disagree")
    func taskSourceIdentityMismatch() async throws {
        let source = "- [ ] Visible"
        let document =
            try await GitLabMarkdownParser.parse(
                makeRequest(source: source)
            )
        let indexed =
            try await GitLabMarkdownTaskSourceIndex
                .tasks(in: source)
        let task = try #require(
            indexed.first
        )
        let mismatched = [
            GitLabMarkdownIndexedTask(
                sourceID: task.sourceID,
                state: .complete
            )
        ]

        let remapped =
            GitLabMarkdownTaskSourceMapper
                .attaching(
                    mismatched,
                    to: document
                )

        #expect(
            tasks(in: remapped.blocks)
                .allSatisfy {
                    $0.sourceID == nil
                }
        )
        #expect(
            !remapped.hasMappedMutableTask
        )
    }

    @Test("Raw HTML cannot shift a visible task onto the wrong source marker")
    func rawHTMLTaskIdentityAmbiguity() async throws {
        let document =
            try await GitLabMarkdownParser.parse(
                makeRequest(
                    source:
                        GitLabMarkdownFixtures
                        .taskSourceRawHTMLAmbiguity
                )
            )
        let renderedTasks =
            tasks(in: document.blocks)

        #expect(
            renderedTasks.map(\.state)
                == [.incomplete]
        )
        #expect(
            renderedTasks
                .allSatisfy {
                    $0.sourceID == nil
                }
        )
        #expect(!document.hasMappedMutableTask)
    }

    @Test("Indented code cannot shift a visible task source identity")
    func indentedCodeTaskIdentityAmbiguity() async throws {
        let document =
            try await GitLabMarkdownParser.parse(
                makeRequest(
                    source:
                        GitLabMarkdownFixtures
                        .taskSourceIndentedCodeAmbiguity
                )
            )
        let renderedTasks =
            tasks(in: document.blocks)

        #expect(
            renderedTasks.map(\.state)
                == [.incomplete]
        )
        #expect(
            renderedTasks
                .allSatisfy {
                    $0.sourceID == nil
                }
        )
        #expect(!document.hasMappedMutableTask)
    }

    @Test("Parent task control text excludes nested child tasks")
    func nestedTaskControlText() async throws {
        let document =
            try await GitLabMarkdownParser.parse(
                makeRequest(
                    source: """
                    - [ ] Parent task
                      - [x] Child task
                    """
                )
            )

        #expect(
            taskControlTexts(
                in: document.blocks
            ) == [
                "Parent task",
                "Child task",
            ]
        )
    }

    @Test("Malformed task markers remain static")
    func malformedTaskMarkerBoundary() async throws {
        let document =
            try await GitLabMarkdownParser.parse(
                makeRequest(
                    source:
                        "- [ ]No separating whitespace"
                )
            )
        let renderedTasks =
            tasks(in: document.blocks)

        #expect(
            renderedTasks.map(\.state)
                == [.incomplete]
        )
        #expect(
            renderedTasks
                .allSatisfy {
                    $0.sourceID == nil
                }
        )
        #expect(!document.hasMappedMutableTask)
    }

    @Test("Preserves quote, code, table, image, and rule structure")
    func structuredBlocks() async throws {
        let request = try makeRequest(
            source:
                GitLabMarkdownFixtures
                    .mixedSection
        )
        let document = try await GitLabMarkdownParser.parse(
            request
        )

        let quote = try #require(
            document.blocks.compactMap(\.quote).first
        )
        #expect(quote.plainText.contains("rollout"))

        let code = try #require(
            document.blocks.compactMap(\.code).first
        )
        #expect(code.language == "swift")
        #expect(code.text.contains("struct Release"))
        #expect(code.accessibilityLabel == "swift code block")

        let table = try #require(
            document.blocks.compactMap(\.table).first
        )
        #expect(table.alignments == [.left, .center, .right])
        #expect(table.header.map(\.plainText) == ["Item", "Owner", "State"])
        #expect(table.rows.count == 2)
        #expect(
            table.rows[0].map(\.plainText)
                == ["Parser", "iOS", "Ready"]
        )

        let image = try #require(
            document.blocks.compactMap(\.image).first
        )
        #expect(image.accountID == request.accountID)
        #expect(image.altText == "GitLab mark")
        #expect(
            image.url.absoluteString
                == "https://gitlab.example.com/uploads/gitlab-mark.png"
        )
        #expect(image.accessibilityLabel == "GitLab mark")
        #expect(
            document.blocks.contains(where: {
                if case .thematicBreak = $0 {
                    true
                } else {
                    false
                }
            })
        )
    }

    @Test("Resolves safe links against exact resource context")
    func safeLinks() async throws {
        let source = """
        [external](https://example.com/docs)
        [root](/help)
        [fragment](#activity)
        [relative](docs/readme.md)
        """
        let request = try makeRequest(source: source)
        let document = try await GitLabMarkdownParser.parse(request)
        let links = document.allLinks.map(\.absoluteString)

        #expect(links.contains("https://example.com/docs"))
        #expect(links.contains("https://gitlab.example.com/help"))
        #expect(
            links.contains(
                "https://gitlab.example.com/group/project/-/issues/42"
                    + "#activity"
            )
        )
        #expect(
            links.contains(
                "https://gitlab.example.com/group/project/docs/readme.md"
            )
        )
    }

    @Test("Resolves repository links and images from the file directory")
    func repositoryRelativeResources() async throws {
        let source = """
        [guide](../Guide.md)
        ![diagram](images/diagram%20one.png)
        [escape](../../../../outside.md)
        [encoded escape](%2E%2E/%2E%2E/private.md)
        ![encoded escape](%2E%2E/private.png)
        """
        let request = try makeRepositoryRequest(
            source: source
        )
        let document = try await GitLabMarkdownParser
            .parse(request)
        let links = document.allLinks
            .map(\.absoluteString)
        let image = try #require(
            document.blocks.compactMap(\.image).first
        )

        #expect(
            links.contains(
                "https://gitlab.example.com/group/project/-/blob/main/Guide.md"
            )
        )
        #expect(
            links.contains(where: {
                $0.contains("outside.md")
                    || $0.contains("private.md")
            }) == false
        )
        #expect(
            document.blocks.compactMap(\.image)
                .count == 1
        )
        #expect(
            image.url.absoluteString
                == "https://gitlab.example.com/api/v4/projects/10/repository/files/docs%2Fimages%2Fdiagram%20one.png/raw?ref=main"
        )
    }

    @Test("Leaves unsafe links readable and noninteractive")
    func unsafeLinks() async throws {
        let source = """
        [script](javascript:alert(1))
        [insecure](http://example.com)
        [credentials](https://user:secret@example.com)
        [network path](//evil.example/path)
        """
        let document = try await GitLabMarkdownParser.parse(
            makeRequest(source: source)
        )

        #expect(document.plainText.contains("script"))
        #expect(document.plainText.contains("insecure"))
        #expect(document.plainText.contains("credentials"))
        #expect(document.plainText.contains("network path"))
        #expect(document.allLinks.isEmpty)
    }

    @Test("Links same-project GitLab references only in plain text")
    func gitLabReferences() async throws {
        let source = """
        Open #12, !34, and ask @reviewer.
        Keep `#56 !78 @inside_code` literal.
        Keep [#90](https://example.com/already-linked) unchanged.
        Keep group/project#91 readable without guessing its project.
        Keep \\#92 escaped.
        """
        let document = try await GitLabMarkdownParser.parse(
            makeRequest(source: source)
        )
        let links = document.allLinks.map(\.absoluteString)

        #expect(
            links.contains(
                "https://gitlab.example.com/group/project/-/issues/12"
            )
        )
        #expect(
            links.contains(
                "https://gitlab.example.com/group/project/-/merge_requests/34"
            )
        )
        #expect(
            links.contains("https://gitlab.example.com/reviewer")
        )
        #expect(links.contains("https://example.com/already-linked"))
        #expect(links.count == 4)
    }

    @Test("Uses readable fallbacks for malformed and unsupported content")
    func unsupportedFallback() async throws {
        let document = try await GitLabMarkdownParser.parse(
            makeRequest(
                source: GitLabMarkdownFixtures.malformedAndUnsupported
            )
        )
        let unsupported = document.blocks.compactMap(\.unsupported)

        #expect(document.plainText.contains("Visible heading"))
        #expect(
            document.plainText.contains("issue template instructions")
                == false
        )
        #expect(
            unsupported.contains(where: {
                $0.kind == .diagram
                    && $0.source.contains("graph TD")
            })
        )
        #expect(
            unsupported.contains(where: {
                $0.kind == .rawHTML
                    && $0.source.contains("Server-only layout")
            })
        )
        #expect(
            unsupported.allSatisfy {
                $0.accessibilityLabel
                    == "Unsupported GitLab formatting"
            }
        )
    }

    @Test("Rejects a mismatched resource web origin for relative links")
    func mismatchedOrigin() async throws {
        let source = "[relative](/help) and #12"
        let document = try await GitLabMarkdownParser.parse(
            makeRequest(
                source: source,
                webURL:
                    "https://attacker.example/group/project/-/issues/42"
            )
        )

        #expect(document.plainText.contains("relative"))
        #expect(document.allLinks.isEmpty)
    }

    private func makeRequest(
        source: String,
        webURL: String =
            "https://gitlab.example.com/group/project/-/issues/42"
    ) throws -> GitLabMarkdownRequest {
        let host = try GitLabHost("https://gitlab.example.com")
        return GitLabMarkdownRequest(
            accountID: GitLabAccountID(
                host: host,
                userID: 7
            ),
            resource: .issue(
                projectID: 10,
                issueIID: 42
            ),
            source: source,
            webURL: URL(string: webURL)
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

    private typealias ParsedTask = (
        state: GitLabMarkdownTaskState,
        sourceID: GitLabMarkdownTaskSourceID?
    )

    private func tasks(
        in blocks: [GitLabMarkdownBlock]
    ) -> [ParsedTask] {
        var result: [ParsedTask] = []

        for block in blocks {
            switch block {
            case let .list(list):
                for item in list.items {
                    if let state = item.taskState {
                        result.append(
                            (
                                state: state,
                                sourceID:
                                    item.taskSourceID
                            )
                        )
                    }
                    result.append(
                        contentsOf:
                            tasks(
                                in: item.blocks
                            )
                    )
                }
            case let .quote(quote):
                result.append(
                    contentsOf:
                        tasks(
                            in: quote.blocks
                        )
                )
            case .heading,
                 .paragraph,
                 .code,
                 .table,
                 .image,
                 .imageGroup,
                 .richText,
                 .thematicBreak,
                 .unsupported:
                break
            }
        }

        return result
    }

    private func taskControlTexts(
        in blocks: [GitLabMarkdownBlock]
    ) -> [String] {
        var result: [String] = []

        for block in blocks {
            switch block {
            case let .list(list):
                for item in list.items {
                    if item.taskState != nil {
                        result.append(
                            item.taskControlText
                        )
                    }
                    result.append(
                        contentsOf:
                            taskControlTexts(
                                in: item.blocks
                            )
                    )
                }
            case let .quote(quote):
                result.append(
                    contentsOf:
                        taskControlTexts(
                            in: quote.blocks
                        )
                )
            case .heading,
                 .paragraph,
                 .code,
                 .table,
                 .image,
                 .imageGroup,
                 .richText,
                 .thematicBreak,
                 .unsupported:
                break
            }
        }

        return result
    }
}
