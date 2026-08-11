import Foundation
import Testing
@testable import Glab

@Suite("GitLab source document")
struct GitLabSourceDocumentTests {
    @Test("Preserves empty lines and normalizes line endings")
    func normalizesLines() throws {
        let document = try GitLabSourceDocument
            .decode(
                Data("first\r\n\r\nthird\r".utf8),
                fileName: "File.swift"
            )

        #expect(
            document.lines
                == ["first", "", "third", ""]
        )
        #expect(document.lineCount == 4)
        #expect(document.language == .swift)
    }

    @Test("Decodes UTF-16 content with a byte-order mark")
    func decodesUTF16() throws {
        var data = Data([0xFF, 0xFE])
        data.append(
            "hello"
                .data(
                    using: .utf16LittleEndian
                )!
        )

        let document = try GitLabSourceDocument
            .decode(
                data,
                fileName: "notes.txt"
            )

        #expect(document.source == "hello")
        #expect(document.language == .plainText)
    }

    @Test("Rejects binary data")
    func rejectsBinary() {
        #expect {
            try GitLabSourceDocument.decode(
                Data([0x89, 0x50, 0x4E, 0x47, 0, 1]),
                fileName: "image.png"
            )
        } throws: { error in
            error as?
                GitLabRepositorySourceLoadError
                == .binary
        }
    }

    @Test("Caps pathological source lines for rendering")
    func capsLongLines() throws {
        let source = String(
            repeating: "x",
            count:
                GitLabSourceDocument
                .maximumRenderedLineLength
                + 20
        )
        let document = try GitLabSourceDocument
            .decode(
                Data(source.utf8),
                fileName: "large.json"
            )

        #expect(document.truncatedLineCount == 1)
        #expect(document.lines[0].hasSuffix(" …"))
        #expect(document.language == .json)
    }

    @Test("Rejects pathological line counts")
    func rejectsExcessiveLineCounts() {
        let source = String(
            repeating: "\n",
            count:
                GitLabSourceDocument
                .maximumLineCount
        )

        #expect {
            try GitLabSourceDocument.decode(
                Data(source.utf8),
                fileName: "generated.txt"
            )
        } throws: { error in
            error as?
                GitLabRepositorySourceLoadError
                == .tooManyLines
        }
    }
}
