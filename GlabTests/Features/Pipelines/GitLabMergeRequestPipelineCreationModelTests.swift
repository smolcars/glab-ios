import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request pipeline creation model")
@MainActor
struct
    GitLabMergeRequestPipelineCreationModelTests
{
    @Test("Creates once, reconciles first, and refreshes")
    func createsPipeline() async throws {
        let fixture = try fixture()

        fixture.model.request()
        await fixture.model.confirm()

        #expect(
            await fixture.service
                .createCount == 1
        )
        #expect(
            fixture.state.pipeline?.id
                == 502
        )
        #expect(
            fixture.state.events
                == ["reconcile", "refresh"]
        )
    }

    @Test("Read-only, replaced, and closed MRs cannot create")
    func gatesCreation() throws {
        let readOnly = try fixture(
            apiAccess: .readOnly
        )
        let replaced = try fixture(
            isAccountCurrent: false
        )
        let closed = try fixture(
            isMergeRequestOpen: false
        )

        #expect(!readOnly.model.canCreate)
        #expect(!replaced.model.canCreate)
        #expect(!closed.model.canCreate)
    }

    @Test("A closed MR invalidates its pending confirmation")
    func rejectsStaleConfirmation() async throws {
        let fixture = try fixture()
        fixture.model.request()
        fixture.state.isMergeRequestOpen =
            false

        await fixture.model.confirm()

        #expect(
            fixture.model.failure == .stale
        )
        #expect(
            await fixture.service
                .createCount == 0
        )
    }

    @Test("Unknown delivery refreshes without optimistic insertion")
    func preservesUnknownDelivery() async throws {
        let error =
            GitLabSessionClientError.api(
                .connectivity(
                    .networkConnectionLost
                )
            )
        let fixture = try fixture(
            error: error
        )
        fixture.model.request()

        await fixture.model.confirm()

        #expect(fixture.state.pipeline == nil)
        #expect(
            fixture.state.events
                == ["refresh"]
        )
        #expect(
            fixture.model.failure
                == .mutation(
                    error,
                    .deliveryUnknown
                )
        )
    }

    private func fixture(
        apiAccess: GitLabAPIAccess =
            .readWrite,
        isAccountCurrent: Bool = true,
        isMergeRequestOpen: Bool = true,
        error:
            GitLabSessionClientError? = nil
    ) throws -> Fixture {
        let state =
            MergeRequestPipelineCreationState(
                isMergeRequestOpen:
                    isMergeRequestOpen
            )
        let service =
            RecordingMRPipelineCreationService(
                response:
                    try pipeline(),
                error: error
            )
        let model =
            GitLabMergeRequestPipelineCreationModel(
                accountID:
                    GitLabAccountID(
                        host:
                            try GitLabHost(
                                "gitlab.example.com"
                            ),
                        userID: 7
                    ),
                route:
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 7
                    ),
                apiAccess: apiAccess,
                service: service,
                isAccountCurrent: {
                    isAccountCurrent
                },
                isMergeRequestOpen: {
                    state.isMergeRequestOpen
                },
                reconcile: {
                    state.pipeline = $0
                    state.events.append(
                        "reconcile"
                    )
                },
                refresh: {
                    state.events.append(
                        "refresh"
                    )
                }
            )
        return Fixture(
            model: model,
            service: service,
            state: state
        )
    }

    private func pipeline()
        throws -> GitLabPipeline
    {
        try JSONDecoder().decode(
            GitLabPipeline.self,
            from:
                Data(
                    """
                    {
                      "id": 502,
                      "project_id": 42,
                      "sha": "new-sha",
                      "ref": "refs/merge-requests/7/head",
                      "status": "pending"
                    }
                    """.utf8
                )
        )
    }

    private struct Fixture {
        let model:
            GitLabMergeRequestPipelineCreationModel
        let service:
            RecordingMRPipelineCreationService
        let state:
            MergeRequestPipelineCreationState
    }
}

@MainActor
private final class
    MergeRequestPipelineCreationState
{
    var isMergeRequestOpen: Bool
    var pipeline: GitLabPipeline?
    var events: [String] = []

    init(
        isMergeRequestOpen: Bool
    ) {
        self.isMergeRequestOpen =
            isMergeRequestOpen
    }
}

private actor RecordingMRPipelineCreationService:
    GitLabPipelineActionServing
{
    let response: GitLabPipeline
    let error:
        GitLabSessionClientError?
    private(set) var createCount = 0

    init(
        response: GitLabPipeline,
        error:
            GitLabSessionClientError?
    ) {
        self.response = response
        self.error = error
    }

    func createMergeRequestPipeline(
        at route: GitLabMergeRequestRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        createCount += 1
        if let error {
            throw error
        }
        return response
    }

    func retryPipeline(
        at route: GitLabPipelineRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        throw .api(.invalidResponse)
    }

    func cancelPipeline(
        at route: GitLabPipelineRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipeline
    {
        throw .api(.invalidResponse)
    }

    func retryJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        throw .api(.invalidResponse)
    }

    func cancelJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        throw .api(.invalidResponse)
    }

    func playJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineJob
    {
        throw .api(.invalidResponse)
    }

    func playTriggerJob(
        at route: GitLabJobRoute
    ) throws(GitLabSessionClientError)
        -> GitLabPipelineTriggerJob
    {
        throw .api(.invalidResponse)
    }
}
