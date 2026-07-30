import Foundation
import Testing
@testable import Glab

@Suite("GitLab commit contract")
struct GitLabCommitTests {
    @Test("Decodes commit history fields")
    func decodesCommit() throws {
        let data = Data(
            """
            {
              "id": "ed899a2f4b50b4370feeea94676502b42383c746",
              "short_id": "ed899a2f4b5",
              "title": "Replace sanitize with escape once",
              "author_name": "Example User",
              "author_email": "user@example.com",
              "authored_date": "2026-07-29T11:50:22.001Z",
              "committer_name": "Example Maintainer",
              "committer_email": "maintainer@example.com",
              "committed_date": "2026-07-29T12:02:00.001Z",
              "message": "Replace sanitize with escape once\\n\\nKeep output safe.",
              "parent_ids": ["parent-sha"],
              "web_url": "https://gitlab.example.com/group/project/-/commit/ed899"
            }
            """.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let commit = try decoder.decode(
            GitLabCommit.self,
            from: data
        )

        #expect(
            commit.id
                == "ed899a2f4b50b4370feeea94676502b42383c746"
        )
        #expect(commit.shortID == "ed899a2f4b5")
        #expect(
            commit.title
                == "Replace sanitize with escape once"
        )
        #expect(commit.authorName == "Example User")
        #expect(commit.authorMark == "EU")
        #expect(commit.parentIDs == ["parent-sha"])
        #expect(commit.safeWebURL?.scheme == "https")
    }

    @Test("Counts only changed lines inside diff hunks")
    func countsLineChanges() {
        let first = GitLabDiffFile(
            oldPath: "Sources/File.swift",
            newPath: "Sources/File.swift",
            diff:
                """
                --- a/Sources/File.swift
                +++ b/Sources/File.swift
                @@ -1,3 +1,4 @@
                 context
                -removed
                +added
                ++code beginning with plus
                """
        )
        let second = GitLabDiffFile(
            oldPath: "README.md",
            newPath: "README.md",
            diff:
                """
                @@ -1,2 +1 @@
                -first
                -second
                +replacement
                """
        )

        #expect(
            first.lineChanges
                == GitLabLineChanges(
                    additions: 2,
                    deletions: 1
                )
        )
        #expect(
            [first, second].lineChanges
                == GitLabLineChanges(
                    additions: 3,
                    deletions: 3
                )
        )
    }

    @Test("Commit diff cache entries are isolated by resource")
    func isolatesCommitDiffCacheEntries()
        throws
    {
        let accountID = GitLabAccountID(
            host: try GitLabHost(
                "https://gitlab.example.com"
            ),
            userID: 1
        )
        let commitRequest = GitLabDiffRequest(
            accountID: accountID,
            projectID: 42,
            commitSHA: "head-sha",
            oldPath: "README.md",
            newPath: "README.md",
            source: "patch"
        )
        let mergeRequest = GitLabDiffRequest(
            accountID: accountID,
            route: GitLabMergeRequestRoute(
                projectID: 42,
                mergeRequestIID: 7
            ),
            headSHA: "head-sha",
            oldPath: "README.md",
            newPath: "README.md",
            source: "patch"
        )
        let otherCommit = GitLabDiffRequest(
            accountID: accountID,
            projectID: 42,
            commitSHA: "other-sha",
            oldPath: "README.md",
            newPath: "README.md",
            source: "patch"
        )
        let key = GitLabDiffCacheKey(
            request: commitRequest,
            parserVersion: 1
        )

        #expect(
            key
                != GitLabDiffCacheKey(
                    request: mergeRequest,
                    parserVersion: 1
                )
        )
        #expect(
            key
                != GitLabDiffCacheKey(
                    request: otherCommit,
                    parserVersion: 1
                )
        )
    }
}
