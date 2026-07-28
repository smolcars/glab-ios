import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab discussion mutations")
struct LiveGitLabDiscussionMutationTests {
    private let issue:
        GitLabDiscussionResource =
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 7
                )
            )
    private let mergeRequestRoute =
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 9
        )

    @Test("Creates a discussion and invalidates only its discussion cache")
    func createsDiscussion() async throws {
        let created = makeTestDiscussion(
            id: "created"
        )
        let client =
            RecordingDiscussionMutationClient(
                discussionResult:
                    .success(created)
            )
        let service =
            LiveGitLabDiscussionService(
                client: client
            )
        let body =
            try GitLabDiscussionCommentBody(
                "New comment"
            )

        let result =
            try await service
                .createDiscussion(
                    for: issue,
                    body: body
                )

        #expect(result == created)
        #expect(
            await client.sentPaths
                == [
                    "projects/42/issues/7/discussions",
                ]
        )
        #expect(
            await client.invalidatedPaths
                == [
                    "projects/42/issues/7/discussions",
                ]
        )
    }

    @Test("Creates a reply and invalidates only its discussion cache")
    func createsReply() async throws {
        let created =
            makeTestDiscussionNote(
                id: 909,
                body: "Created reply"
            )
        let client =
            RecordingDiscussionMutationClient(
                noteResult: .success(created)
            )
        let service =
            LiveGitLabDiscussionService(
                client: client
            )
        let body =
            try GitLabDiscussionCommentBody(
                "Created reply"
            )

        let result =
            try await service.reply(
                to: "thread-a",
                in: issue,
                body: body
            )

        #expect(result == created)
        #expect(
            await client.sentPaths
                == [
                    "projects/42/issues/7/discussions/thread-a/notes",
                ]
        )
        #expect(
            await client.invalidatedPaths
                == [
                    "projects/42/issues/7/discussions",
                ]
        )
    }

    @Test("Validates the latest version before a positional POST")
    func createsDiffDiscussion() async throws {
        let version = try diffVersionIdentity()
        let created = makeTestDiscussion(
            id: "diff-created"
        )
        let client =
            RecordingDiscussionMutationClient(
                discussionResult:
                    .success(created),
                versionResult:
                    .success([
                        diffVersion(
                            identity: version
                        ),
                    ])
            )
        let service =
            LiveGitLabDiscussionService(
                client: client
            )
        let position = try #require(
            GitLabDiffLinePosition(
                version: version,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: nil,
                newLine: 21
            )
        )

        let result = try await service
            .createDiffDiscussion(
                for: mergeRequestRoute,
                body:
                    GitLabDiscussionCommentBody(
                        "Review this line"
                    ),
                position: position
            )

        #expect(result == created)
        #expect(
            await client.sentPaths
                == [
                    "projects/42/merge_requests/9/versions",
                    "projects/42/merge_requests/9/discussions",
                ]
        )
        #expect(
            await client.invalidatedPaths
                == [
                    "projects/42/merge_requests/9/discussions",
                ]
        )
    }

    @Test(
        "Rejects changed version identities before a positional POST",
        arguments: [
            (
                baseSHA: "different-base",
                startSHA: "start",
                headSHA: "head"
            ),
            (
                baseSHA: "base",
                startSHA: "different-start",
                headSHA: "head"
            ),
            (
                baseSHA: "base",
                startSHA: "start",
                headSHA: "different-head"
            ),
        ]
    )
    func rejectsStaleDiffVersion(
        baseSHA: String,
        startSHA: String,
        headSHA: String
    ) async throws {
        let positionVersion =
            try diffVersionIdentity()
        let latestVersion = try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: baseSHA,
                startSHA: startSHA,
                headSHA: headSHA
            )
        )
        let client =
            RecordingDiscussionMutationClient(
                versionResult:
                    .success([
                        diffVersion(
                            identity:
                                latestVersion
                        ),
                    ])
            )
        let service =
            LiveGitLabDiscussionService(
                client: client
            )
        let position = try #require(
            GitLabDiffLinePosition(
                version: positionVersion,
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: 20,
                newLine: 21
            )
        )

        await #expect(
            throws:
                GitLabDiscussionMutationError
                    .staleDiffVersion
        ) {
            try await service
                .createDiffDiscussion(
                    for: mergeRequestRoute,
                    body:
                        GitLabDiscussionCommentBody(
                            "Do not post"
                        ),
                    position: position
                )
        }

        #expect(
            await client.sentPaths
                == [
                    "projects/42/merge_requests/9/versions",
                ]
        )
        #expect(
            await client.invalidatedPaths
                .isEmpty
        )
    }

    @Test("Rejects a missing latest diff version without posting")
    func rejectsMissingDiffVersion() async throws {
        let client =
            RecordingDiscussionMutationClient(
                versionResult: .success([])
            )
        let service =
            LiveGitLabDiscussionService(
                client: client
            )
        let position = try #require(
            GitLabDiffLinePosition(
                version:
                    diffVersionIdentity(),
                oldPath: "Sources/File.swift",
                newPath: "Sources/File.swift",
                oldLine: 20,
                newLine: 21
            )
        )

        await #expect(
            throws:
                GitLabDiscussionMutationError
                    .latestDiffVersionUnavailable
        ) {
            try await service
                .createDiffDiscussion(
                    for: mergeRequestRoute,
                    body:
                        GitLabDiscussionCommentBody(
                            "Do not post"
                        ),
                    position: position
                )
        }

        #expect(
            await client.sentPaths.count == 1
        )
        #expect(
            await client.invalidatedPaths
                .isEmpty
        )
    }

    @Test(
        "Does not invalidate after a failed or cancelled POST",
        arguments: [
            GitLabSessionClientError.api(
                .validation(
                    statusCode: 400
                )
            ),
            GitLabSessionClientError.api(
                .cancelled
            ),
        ]
    )
    func leavesCacheAfterFailure(
        failure: GitLabSessionClientError
    ) async throws {
        let client =
            RecordingDiscussionMutationClient(
                discussionResult:
                    .failure(failure)
            )
        let service =
            LiveGitLabDiscussionService(
                client: client
            )
        let body =
            try GitLabDiscussionCommentBody(
                "Preserve cache"
            )

        await #expect(
            throws:
                GitLabDiscussionMutationError
                    .request(failure)
        ) {
            try await service
                .createDiscussion(
                    for: issue,
                    body: body
                )
        }

        #expect(
            await client.invalidatedPaths
                .isEmpty
        )
    }

    private func diffVersionIdentity()
        throws
        -> GitLabMergeRequestDiffVersionIdentity
    {
        try #require(
            GitLabMergeRequestDiffVersionIdentity(
                baseSHA: "base",
                startSHA: "start",
                headSHA: "head"
            )
        )
    }

    private func diffVersion(
        identity:
            GitLabMergeRequestDiffVersionIdentity
    ) -> GitLabMergeRequestDiffVersion {
        GitLabMergeRequestDiffVersion(
            id: 81,
            baseCommitSHA: identity.baseSHA,
            startCommitSHA: identity.startSHA,
            headCommitSHA: identity.headSHA,
            state: "collected"
        )
    }
}

private actor RecordingDiscussionMutationClient:
    GitLabPaginatedSessionRequestSending
{
    let discussionResult:
        Result<
            GitLabDiscussion,
            GitLabSessionClientError
        >
    let noteResult:
        Result<
            GitLabDiscussionNote,
            GitLabSessionClientError
        >
    let versionResult:
        Result<
            [GitLabMergeRequestDiffVersion],
            GitLabSessionClientError
        >

    private(set) var sentPaths: [String] = []
    private(set) var invalidatedPaths:
        [String] = []

    init(
        discussionResult:
            Result<
                GitLabDiscussion,
                GitLabSessionClientError
            > = .success(
                makeTestDiscussion()
            ),
        noteResult:
            Result<
                GitLabDiscussionNote,
                GitLabSessionClientError
            > = .success(
                makeTestDiscussionNote()
            ),
        versionResult:
            Result<
                [GitLabMergeRequestDiffVersion],
                GitLabSessionClientError
            > = .success(
                []
            )
    ) {
        self.discussionResult =
            discussionResult
        self.noteResult = noteResult
        self.versionResult = versionResult
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sentPaths.append(
            endpoint.pathComponents
                .joined(separator: "/")
        )

        if Response.self
            == GitLabDiscussion.self
        {
            return try discussionResult
                .get() as! Response
        }
        if Response.self
            == GitLabDiscussionNote.self
        {
            return try noteResult
                .get() as! Response
        }
        if Response.self
            == [GitLabMergeRequestDiffVersion]
            .self
        {
            return try versionResult
                .get() as! Response
        }
        throw .api(.invalidResponse)
    }

    func sendPage<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        throw .api(.invalidResponse)
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) {
        invalidatedPaths.append(
            endpoint.pathComponents
                .joined(separator: "/")
        )
    }
}
