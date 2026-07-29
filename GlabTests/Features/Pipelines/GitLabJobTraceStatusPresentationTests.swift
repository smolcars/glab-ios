import Testing
@testable import Glab

@Suite("GitLab job trace status presentation")
struct GitLabJobTraceStatusPresentationTests {
    @Test("Search failures are warnings instead of zero matches")
    func presentsSearchFailure() {
        let presentation =
            GitLabJobTraceStatusPresentation(
                refreshError: nil,
                searchError: .invalidFile,
                isSearching: false,
                searchText: "failure",
                searchResult: .empty,
                longLineCount: 0
            )

        #expect(
            presentation.text
                == "Search unavailable · The cached job log was invalid."
        )
        #expect(presentation.isWarning)
    }

    @Test("Whitespace alone does not report a search result")
    func ignoresWhitespaceQuery() {
        let presentation =
            GitLabJobTraceStatusPresentation(
                refreshError: nil,
                searchError: nil,
                isSearching: false,
                searchText: "   ",
                searchResult: .empty,
                longLineCount: 2
            )

        #expect(
            presentation.text
                == "2 long lines truncated for display"
        )
        #expect(!presentation.isWarning)
    }

    @Test("A retained-cache refresh failure has priority")
    func prioritizesRefreshFailure() {
        let presentation =
            GitLabJobTraceStatusPresentation(
                refreshError: .noTrace,
                searchError: .invalidFile,
                isSearching: false,
                searchText: "failure",
                searchResult: .empty,
                longLineCount: 0
            )

        #expect(
            presentation.text
                == "Cached log kept · GitLab no longer returned a log"
        )
        #expect(presentation.isWarning)
    }
}
