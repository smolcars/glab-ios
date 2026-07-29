import Foundation
import Testing
@testable import Glab

@Suite("Live GitLab merge request merge service")
struct LiveGitLabMergeRequestMergeServiceTests {
    @Test("Loads an authoritative merge preflight")
    func loadsPreflight() async throws {
        let client =
            RecordingMergeRequestMergeClient()
        let service =
            LiveGitLabMergeRequestMergeService(
                client: client
            )

        let preflight =
            try await service.preflight(
                at: route
            )

        #expect(
            preflight.mergeRequest.route
                == route
        )
        #expect(
            preflight.approvalSummary.approved
                == true
        )
        #expect(
            await client.sentKeys
                == [
                    "GET:projects/42/merge_requests/7",
                    "GET:projects/42/merge_requests/7/approvals",
                ]
        )
    }

    @Test("Sends an immediate merge once and invalidates affected reads")
    func sendsImmediateMerge() async throws {
        let client =
            RecordingMergeRequestMergeClient()
        let service =
            LiveGitLabMergeRequestMergeService(
                client: client
            )

        let response = try await service.merge(
            at: route,
            sha: "fresh-head-sha",
            action: .mergeNow
        )

        #expect(response.stateKind == .merged)
        #expect(
            await client.sentKeys
                == [
                    "PUT:projects/42/merge_requests/7/merge"
                ]
        )
        await expectFocusedInvalidation(
            from: client
        )
    }

    @Test("Sends auto-merge once and preserves its authoritative state")
    func sendsAutoMerge() async throws {
        let client =
            RecordingMergeRequestMergeClient(
                mergedResponse: false
            )
        let service =
            LiveGitLabMergeRequestMergeService(
                client: client
            )

        let response = try await service.merge(
            at: route,
            sha: "fresh-head-sha",
            action: .autoMerge
        )

        #expect(response.stateKind == .opened)
        #expect(
            response
                .mergeWhenPipelineSucceeds
                == true
        )
        #expect(
            await client.sentKeys.count == 1
        )
        await expectFocusedInvalidation(
            from: client
        )
    }

    @Test(
        "Invalidates uncertain and stale delivery but not permission rejection",
        arguments: [
            (
                GitLabSessionClientError.api(
                    .server(statusCode: 503)
                ),
                true
            ),
            (
                .api(
                    .validation(statusCode: 409)
                ),
                true
            ),
            (
                .api(.forbidden),
                false
            ),
        ]
    )
    func invalidatesByFailure(
        error: GitLabSessionClientError,
        shouldInvalidate: Bool
    ) async {
        let client =
            RecordingMergeRequestMergeClient(
                mutationError: error
            )
        let service =
            LiveGitLabMergeRequestMergeService(
                client: client
            )

        await #expect(throws: error) {
            _ = try await service.merge(
                at: route,
                sha: "fresh-head-sha",
                action: .mergeNow
            )
        }

        let invalidated =
            await client.invalidatedKeys
        #expect(
            shouldInvalidate
                ? !invalidated.isEmpty
                : invalidated.isEmpty
        )
    }

    @Test("Rejects a contradictory merge response")
    func rejectsMismatchedResponse() async {
        let client =
            RecordingMergeRequestMergeClient(
                responseProjectID: 99
            )
        let service =
            LiveGitLabMergeRequestMergeService(
                client: client
            )

        await #expect(
            throws:
                GitLabSessionClientError
                .api(.invalidResponse)
        ) {
            _ = try await service.merge(
                at: route,
                sha: "fresh-head-sha",
                action: .mergeNow
            )
        }
    }

    private var route:
        GitLabMergeRequestRoute
    {
        GitLabMergeRequestRoute(
            projectID: 42,
            mergeRequestIID: 7
        )
    }

    private func expectFocusedInvalidation(
        from client:
            RecordingMergeRequestMergeClient
    ) async {
        let keys =
            await client.invalidatedKeys
        #expect(
            keys.contains(
                "GET:projects/42/merge_requests/7"
            )
        )
        #expect(
            keys.contains(
                "GET:projects/42/merge_requests/7/approvals"
            )
        )
        #expect(
            keys.contains(
                "GET:projects/42/merge_requests/7/approval_state"
            )
        )
        #expect(
            keys.contains(
                "GET:projects/42/merge_requests/7/pipelines"
            )
        )
        #expect(
            keys.contains(
                "GET:merge_requests"
            )
        )
        #expect(
            keys.contains(
                "GET:todos"
            )
        )
        #expect(
            !keys.contains {
                $0.contains("projects/99")
            }
        )
    }
}

private actor RecordingMergeRequestMergeClient:
    GitLabPaginatedSessionRequestSending
{
    private let mutationError:
        GitLabSessionClientError?
    private let responseProjectID: Int
    private let mergedResponse: Bool
    private(set) var sentKeys: [String] = []
    private(set) var invalidatedKeys:
        [String] = []

    init(
        mutationError:
            GitLabSessionClientError? = nil,
        responseProjectID: Int = 42,
        mergedResponse: Bool = true
    ) {
        self.mutationError =
            mutationError
        self.responseProjectID =
            responseProjectID
        self.mergedResponse =
            mergedResponse
    }

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        sentKeys.append(Self.key(endpoint))
        if
            endpoint.method == .put,
            let mutationError
        {
            throw mutationError
        }

        let value: any Sendable =
            if endpoint.pathComponents.last
                == "approvals"
            {
                GitLabMergeRequestApprovalSummary(
                    approved: true,
                    approvalsRequired: 1,
                    approvalsLeft: 0,
                    approvedBy: []
                )
            } else {
                makeTestMergeRequest(
                    projectID:
                        responseProjectID,
                    state:
                        mergedResponse
                        && endpoint.method == .put
                        ? "merged"
                        : "opened",
                    sha: "fresh-head-sha",
                    detailedMergeStatus:
                        mergedResponse
                        && endpoint.method == .put
                        ? "not_open"
                        : "ci_still_running",
                    hasConflicts: false,
                    blockingDiscussionsResolved:
                        true,
                    headPipeline:
                        GitLabMergeRequestHeadPipeline(
                            id: 501,
                            status: "running",
                            webURL: nil
                        ),
                    mergeWhenPipelineSucceeds:
                        endpoint.method == .put
                        && !mergedResponse,
                    userCanMerge: true
                )
            }
        guard let response = value as? Response else {
            throw .api(.invalidResponse)
        }
        return response
    }

    func sendPage<Response>(
        _ page:
            GitLabAPIPageRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> GitLabAPIResponse<Response>
    {
        throw .api(.invalidResponse)
    }

    func invalidateCachedResponse<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async {
        let key = Self.key(endpoint)
        if !invalidatedKeys.contains(key) {
            invalidatedKeys.append(key)
        }
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
