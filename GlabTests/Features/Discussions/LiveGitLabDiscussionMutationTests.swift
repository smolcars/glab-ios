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

        await #expect(throws: failure) {
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
            )
    ) {
        self.discussionResult =
            discussionResult
        self.noteResult = noteResult
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
