import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab pipeline action service")
struct LiveGitLabPipelineActionServiceTests {
    @Test("Sends every pipeline action once and invalidates focused reads")
    func sendsPipelineActions() async throws {
        let client =
            RecordingPipelineActionClient()
        let service =
            LiveGitLabPipelineActionService(
                client: client
            )

        _ = try await service.retryPipeline(
            at: pipelineRoute
        )
        _ = try await service.cancelPipeline(
            at: pipelineRoute
        )

        #expect(
            await client.sentKeys
                == [
                    "\(pipelineKey)/retry",
                    "\(pipelineKey)/cancel",
                ]
        )
        #expect(
            await client.invalidatedKeys
                == pipelineInvalidationKeys
                    + pipelineInvalidationKeys
        )
    }

    @Test("Sends every ordinary job action once and invalidates its pipeline reads")
    func sendsJobActions() async throws {
        let client =
            RecordingPipelineActionClient()
        let service =
            LiveGitLabPipelineActionService(
                client: client
            )

        _ = try await service.retryJob(
            at: jobRoute
        )
        _ = try await service.cancelJob(
            at: jobRoute
        )
        _ = try await service.playJob(
            at: jobRoute
        )

        #expect(
            await client.sentKeys
                == [
                    "\(jobKey)/retry",
                    "\(jobKey)/cancel",
                    "\(jobKey)/play",
                ]
        )
        #expect(
            await client.invalidatedKeys
                == jobInvalidationKeys
                    + jobInvalidationKeys
                    + jobInvalidationKeys
        )
    }

    @Test("Creates one MR pipeline and invalidates only its history")
    func createsMergeRequestPipeline()
        async throws
    {
        let client =
            RecordingPipelineActionClient()
        let service =
            LiveGitLabPipelineActionService(
                client: client
            )

        let response =
            try await service
                .createMergeRequestPipeline(
                    at: mergeRequestRoute
                )

        #expect(response.id == 501)
        #expect(
            await client.sentKeys
                == [
                    "\(mergeRequestKey)/pipelines"
                ]
        )
        #expect(
            await client.invalidatedKeys
                == [
                    "GET:projects/42/merge_requests/7/pipelines"
                ]
        )
    }

    @Test(
        "Invalidates uncertain actions but not rejected actions",
        arguments: [
            (
                GitLabSessionClientError.api(
                    .server(statusCode: 503)
                ),
                true
            ),
            (
                .api(.forbidden),
                false
            ),
        ]
    )
    func invalidatesByDeliveryCertainty(
        error: GitLabSessionClientError,
        shouldInvalidate: Bool
    ) async {
        let client =
            RecordingPipelineActionClient(
                error: error
            )
        let service =
            LiveGitLabPipelineActionService(
                client: client
            )

        await #expect(throws: error) {
            _ = try await service
                .retryPipeline(
                    at: pipelineRoute
                )
        }

        #expect(
            await client.invalidatedKeys
                == (
                    shouldInvalidate
                        ? pipelineInvalidationKeys
                        : []
                )
        )
    }

    @Test(
        "Uncertain job delivery invalidates no trigger-job reads"
    )
    func uncertainJobInvalidationIsFocused()
        async
    {
        let error =
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            )
        let client =
            RecordingPipelineActionClient(
                error: error
            )
        let service =
            LiveGitLabPipelineActionService(
                client: client
            )

        await #expect(throws: error) {
            _ = try await service
                .playJob(at: jobRoute)
        }

        #expect(
            await client.invalidatedKeys
                == jobInvalidationKeys
        )
    }

    @Test("Rejects contradictory action responses")
    func rejectsMismatchedResponses() async {
        let client =
            RecordingPipelineActionClient(
                responseProjectID: 99
            )
        let service =
            LiveGitLabPipelineActionService(
                client: client
            )

        await #expect(
            throws:
                GitLabSessionClientError
                .api(.invalidResponse)
        ) {
            _ = try await service
                .cancelPipeline(
                    at: pipelineRoute
                )
        }
        await #expect(
            throws:
                GitLabSessionClientError
                .api(.invalidResponse)
        ) {
            _ = try await service
                .playJob(at: jobRoute)
        }
    }

    private var pipelineRoute:
        GitLabPipelineRoute
    {
        GitLabPipelineRoute(
            projectID: 42,
            pipelineID: 501
        )!
    }

    private var jobRoute: GitLabJobRoute {
        GitLabJobRoute(
            projectID: 42,
            pipelineID: 501,
            jobID: 800
        )!
    }

    private var mergeRequestRoute:
        GitLabMergeRequestRoute
    {
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 7
        )
    }

    private var pipelineKey: String {
        "POST:projects/42/pipelines/501"
    }

    private var jobKey: String {
        "POST:projects/42/jobs/800"
    }

    private var mergeRequestKey: String {
        "POST:projects/42/merge_requests/7"
    }

    private var pipelineInvalidationKeys:
        [String]
    {
        [
            "GET:projects/42/pipelines/501",
            "GET:projects/42/pipelines/501/jobs",
            "GET:projects/42/pipelines/501/trigger_jobs",
            "GET:projects/42/pipelines/501/bridges",
        ]
    }

    private var jobInvalidationKeys:
        [String]
    {
        [
            "GET:projects/42/pipelines/501",
            "GET:projects/42/pipelines/501/jobs",
        ]
    }
}

private actor RecordingPipelineActionClient:
    GitLabPaginatedSessionRequestSending
{
    private let error:
        GitLabSessionClientError?
    private let responseProjectID: Int
    private(set) var sentKeys: [String] = []
    private(set) var invalidatedKeys:
        [String] = []

    init(
        error: GitLabSessionClientError? = nil,
        responseProjectID: Int = 42
    ) {
        self.error = error
        self.responseProjectID =
            responseProjectID
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sentKeys.append(Self.key(endpoint))
        if let error {
            throw error
        }

        let value: any Sendable
        do {
            value =
                if endpoint.pathComponents
                    .contains("jobs")
                {
                    try decodeJob(
                        projectID:
                            responseProjectID
                    )
                } else {
                    try decodePipeline(
                        projectID:
                            responseProjectID
                    )
                }
        } catch {
            throw .api(.decoding)
        }
        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }
        return response
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
    ) async {
        invalidatedKeys.append(
            Self.key(endpoint)
        )
    }

    private func decodePipeline(
        projectID: Int
    ) throws -> GitLabPipeline {
        try JSONDecoder().decode(
            GitLabPipeline.self,
            from:
                Data(
                    """
                    {
                      "id": 501,
                      "project_id": \(projectID),
                      "sha": "abc123",
                      "ref": "main",
                      "status": "pending"
                    }
                    """.utf8
                )
        )
    }

    private func decodeJob(
        projectID: Int
    ) throws -> GitLabPipelineJob {
        try JSONDecoder().decode(
            GitLabPipelineJob.self,
            from:
                Data(
                    """
                    {
                      "id": 800,
                      "name": "ios-tests",
                      "stage": "test",
                      "status": "pending",
                      "pipeline": {
                        "id": 501,
                        "project_id": \(projectID)
                      }
                    }
                    """.utf8
                )
        )
    }

    nonisolated private static func key<
        Response
    >(
        _ endpoint:
            GitLabAPIRequest<Response>
    ) -> String {
        endpoint.method.rawValue
            + ":"
            + endpoint.pathComponents
            .joined(separator: "/")
    }
}
