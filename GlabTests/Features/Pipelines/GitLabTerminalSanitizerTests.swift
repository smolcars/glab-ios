import Foundation
import Testing
@testable import Glab

@Suite("GitLab terminal sanitizer")
struct GitLabTerminalSanitizerTests {
    @Test("Strips ANSI color and cursor sequences")
    func stripsCSISequences() {
        let source =
            Data(
                "\u{1B}[31mError\u{1B}[0m"
                    .utf8
            )

        #expect(
            GitLabTerminalSanitizer
                .sanitize(source)
                == "Error"
        )
    }

    @Test("Strips hyperlinks, clipboard content, and terminal titles")
    func stripsOSCSequences() {
        let source =
            Data(
                (
                    "\u{1B}]8;;https://host.invalid/private\u{7}"
                        + "Open"
                        + "\u{1B}]8;;\u{7}"
                        + "\u{1B}]52;c;c2VjcmV0\u{7}"
                        + "\u{1B}]0;private title\u{7}"
                        + " safe"
                ).utf8
            )

        #expect(
            GitLabTerminalSanitizer
                .sanitize(source)
                == "Open safe"
        )
    }

    @Test("Strips DCS, APC, PM, and SOS payloads")
    func stripsStringControlSequences() {
        let source =
            Data(
                (
                    "a"
                        + "\u{1B}Pprivate\u{1B}\\"
                        + "\u{1B}_command\u{1B}\\"
                        + "\u{1B}^message\u{1B}\\"
                        + "\u{1B}Xpayload\u{1B}\\"
                        + "b"
                ).utf8
            )

        #expect(
            GitLabTerminalSanitizer
                .sanitize(source)
                == "ab"
        )
    }

    @Test("Incomplete and nested control sequences never leak payloads")
    func stripsMalformedAndIncompleteSequences() {
        let nested =
            Data(
                (
                    "before"
                        + "\u{1B}]hidden"
                        + "\u{1B}[31mstill hidden\u{7}"
                        + "after"
                ).utf8
            )
        let incomplete =
            Data(
                (
                    "visible"
                        + "\u{1B}]52;c;private"
                ).utf8
            )

        #expect(
            GitLabTerminalSanitizer
                .sanitize(nested)
                == "beforeafter"
        )
        #expect(
            GitLabTerminalSanitizer
                .sanitize(incomplete)
                == "visible"
        )
    }

    @Test("Strips terminal controls and expands tabs deterministically")
    func stripsControlsAndExpandsTabs() {
        let source = Data([
            0x61,
            0x09,
            0x62,
            0x00,
            0x08,
            0x0D,
            0x7F,
            0x63,
        ])

        #expect(
            GitLabTerminalSanitizer
                .sanitize(source)
                == "a   bc"
        )
    }

    @Test("Preserves Unicode and replaces invalid UTF-8")
    func handlesUnicodeAndInvalidUTF8() {
        var source =
            Data("héllo ".utf8)
        source.append(contentsOf: [
            0xF0,
            0x28,
            0x8C,
            0x28,
        ])

        #expect(
            GitLabTerminalSanitizer
                .sanitize(source)
                == "héllo �(�("
        )
    }

    @Test("Strips UTF-8 encoded C1 terminal sequences")
    func stripsC1Sequences() {
        let source =
            "a\u{009D}52;c;private\u{009C}b"

        #expect(
            GitLabTerminalSanitizer
                .sanitize(
                    Data(source.utf8)
                )
                == "ab"
        )
    }
}
