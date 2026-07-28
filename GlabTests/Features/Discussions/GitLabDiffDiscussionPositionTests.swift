import Foundation
import Testing
@testable import Glab

@Suite("GitLab diff discussion positions")
struct GitLabDiffDiscussionPositionTests {
    @Test("Maps added, deleted, and context lines exactly")
    func mapsDiffLines() throws {
        let version = try makeVersion()

        let addition = try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                line: GitLabDiffLine(
                    ordinal: 0,
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: 21,
                    text: "let added = true"
                )
            )
        )
        let deletion = try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                line: GitLabDiffLine(
                    ordinal: 1,
                    kind: .deletion,
                    oldLineNumber: 18,
                    newLineNumber: nil,
                    text: "let removed = true"
                )
            )
        )
        let context = try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                line: GitLabDiffLine(
                    ordinal: 2,
                    kind: .context,
                    oldLineNumber: 19,
                    newLineNumber: 22,
                    text: "let retained = true"
                )
            )
        )

        #expect(addition.oldLine == nil)
        #expect(addition.newLine == 21)
        #expect(deletion.oldLine == 18)
        #expect(deletion.newLine == nil)
        #expect(context.oldLine == 19)
        #expect(context.newLine == 22)
    }

    @Test("Preserves both paths for a renamed file")
    func preservesRenamedPaths() throws {
        let position = try #require(
            GitLabDiffLinePosition(
                version: makeVersion(),
                oldPath: "Sources/Old.swift",
                newPath: "Sources/New.swift",
                oldLine: 8,
                newLine: 11
            )
        )

        #expect(position.oldPath == "Sources/Old.swift")
        #expect(position.newPath == "Sources/New.swift")
    }

    @Test(
        "Rejects invalid exact positions",
        arguments: [
            (
                oldPath: "",
                newPath: "Sources/File.swift",
                oldLine: 1,
                newLine: 1
            ),
            (
                oldPath: "Sources/File.swift",
                newPath: "",
                oldLine: 1,
                newLine: 1
            ),
            (
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: 0,
                newLine: 1
            ),
            (
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: 1,
                newLine: -1
            ),
            (
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: nil,
                newLine: nil
            ),
        ]
    )
    func rejectsInvalidPosition(
        oldPath: String,
        newPath: String,
        oldLine: Int?,
        newLine: Int?
    ) throws {
        let version = try makeVersion()

        #expect(
            GitLabDiffLinePosition(
                version: version,
                oldPath: oldPath,
                newPath: newPath,
                oldLine: oldLine,
                newLine: newLine
            ) == nil
        )
    }

    @Test("Rejects empty version identifiers and redacts valid ones")
    func validatesAndRedactsVersion() throws {
        #expect(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "",
                startSHA: "start-secret",
                headSHA: "head-secret"
            ) == nil
        )

        let version = try makeVersion()
        let description = String(describing: version)
        let reflection = String(reflecting: version)

        #expect(!description.contains("base-secret"))
        #expect(!reflection.contains("head-secret"))
    }

    @Test("Decodes the latest merge request diff version")
    func decodesDiffVersion() throws {
        let data = try #require(
            """
            [
              {
                "id": 81,
                "head_commit_sha": "head-secret",
                "base_commit_sha": "base-secret",
                "start_commit_sha": "start-secret",
                "state": "collected",
                "future_field": true
              }
            ]
            """.data(using: .utf8)
        )

        let decoded = try JSONDecoder().decode(
            [GitLabMergeRequestDiffVersion].self,
            from: data
        )
        let version = try #require(decoded.first)
        let expectedIdentity = try makeVersion()

        #expect(version.id == 81)
        #expect(version.state == "collected")
        #expect(
            version.identity == expectedIdentity
        )
    }

    @Test("Builds the latest diff-version request")
    func buildsVersionRequest() {
        let endpoint =
            GitLabMergeRequestEndpoints
            .diffVersions(
                at: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                )
            )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "merge_requests",
                    "7",
                    "versions",
                ]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "1"
                    ),
                ]
        )
    }

    @Test(
        "Encodes exact positional POST bodies",
        arguments: [
            PositionLines(
                oldLine: nil,
                newLine: 21
            ),
            PositionLines(
                oldLine: 18,
                newLine: nil
            ),
            PositionLines(
                oldLine: 18,
                newLine: 21
            ),
        ]
    )
    func encodesPositionBody(
        lines: PositionLines
    ) throws {
        let position = try #require(
            GitLabDiffLinePosition(
                version: makeVersion(),
                oldPath: "Sources/Old.swift",
                newPath: "Sources/New.swift",
                oldLine: lines.oldLine,
                newLine: lines.newLine
            )
        )
        let endpoint =
            try GitLabDiscussionEndpoints
            .createDiffDiscussion(
                for: GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                ),
                body: GitLabDiscussionCommentBody(
                    "Review this line"
                ),
                position: position
            )
        let data = try #require(endpoint.body)
        let object = try #require(
            JSONSerialization
                .jsonObject(with: data)
                as? [String: Any]
        )
        let encodedPosition = try #require(
            object["position"]
                as? [String: Any]
        )

        #expect(endpoint.method == .post)
        #expect(endpoint.requiredAccess == .write)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "merge_requests",
                    "7",
                    "discussions",
                ]
        )
        #expect(
            object["body"] as? String
                == "Review this line"
        )
        #expect(
            encodedPosition["position_type"]
                as? String == "text"
        )
        #expect(
            encodedPosition["base_sha"]
                as? String == "base-secret"
        )
        #expect(
            encodedPosition["start_sha"]
                as? String == "start-secret"
        )
        #expect(
            encodedPosition["head_sha"]
                as? String == "head-secret"
        )
        #expect(
            encodedPosition["old_path"]
                as? String == "Sources/Old.swift"
        )
        #expect(
            encodedPosition["new_path"]
                as? String == "Sources/New.swift"
        )
        #expect(
            encodedPosition["old_line"]
                as? Int == lines.oldLine
        )
        #expect(
            encodedPosition["new_line"]
                as? Int == lines.newLine
        )
    }

    @Test("Separates line drafts by exact position and general comments")
    func separatesLineDrafts() throws {
        let accountID = try GitLabAccountID(
            host: GitLabHost(
                "https://gitlab.example.com"
            ),
            userID: 7
        )
        let resource =
            GitLabDiscussionResource
            .mergeRequest(
                GitLabMergeRequestRoute(
                    projectID: 42,
                    mergeRequestIID: 7
                )
            )
        let firstPosition = try #require(
            GitLabDiffLinePosition(
                version: makeVersion(),
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: nil,
                newLine: 21
            )
        )
        let secondPosition = try #require(
            GitLabDiffLinePosition(
                version: makeVersion(
                    headSHA: "other-head-secret"
                ),
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: nil,
                newLine: 21
            )
        )
        let comment = GitLabDiscussionDraftKey(
            accountID: accountID,
            resource: resource,
            target: .newDiscussion
        )
        let firstLine = GitLabDiscussionDraftKey(
            accountID: accountID,
            resource: resource,
            target:
                .newDiffDiscussion(
                    position: firstPosition
                )
        )
        let secondLine = GitLabDiscussionDraftKey(
            accountID: accountID,
            resource: resource,
            target:
                .newDiffDiscussion(
                    position: secondPosition
                )
        )

        #expect(comment != firstLine)
        #expect(firstLine != secondLine)
        #expect(
            !String(describing: firstLine)
                .contains("Sources/File.swift")
        )
        #expect(
            !String(reflecting: firstLine)
                .contains("head-secret")
        )
    }

    private func makeVersion(
        headSHA: String = "head-secret"
    ) throws -> GitLabMergeRequestDiffVersionIdentity {
        try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "base-secret",
                startSHA: "start-secret",
                headSHA: headSHA
            )
        )
    }
}

struct PositionLines: Sendable {
    let oldLine: Int?
    let newLine: Int?
}
