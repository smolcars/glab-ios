import Foundation
import Testing
@testable import Glab

@Suite("GitLab response metadata")
struct GitLabResponseMetadataTests {
    @Test("Parses a reliable total item count")
    func parsesTotalCount() throws {
        let metadata = GitLabResponseMetadata(
            response: try makeResponse(
                headers: ["X-Total": "42"]
            )
        )

        #expect(metadata.totalCount == 42)
    }

    @Test(
        "Ignores an unavailable or invalid total item count",
        arguments: [
            (nil, nil),
            ("", nil),
            ("many", nil),
            ("-1", nil),
        ] as [(String?, Int?)]
    )
    func ignoresInvalidTotalCount(
        header: String?,
        expected: Int?
    ) throws {
        let headers = header.map {
            ["X-Total": $0]
        }
        let metadata = GitLabResponseMetadata(
            response: try makeResponse(headers: headers)
        )

        #expect(metadata.totalCount == expected)
    }
}

private extension GitLabResponseMetadataTests {
    func makeResponse(
        headers: [String: String]?
    ) throws -> HTTPURLResponse {
        let url = try #require(
            URL(string: "https://gitlab.example.com/api/v4/todos")
        )

        return try #require(
            HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: "HTTP/2",
                headerFields: headers
            )
        )
    }
}
