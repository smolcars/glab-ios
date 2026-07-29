import Foundation
import Testing
@testable import Glab

@Suite("GitLab pipeline endpoints")
struct GitLabPipelineEndpointTests {
    @Test("Builds a paginated merge request pipeline route")
    func buildsMergeRequestPipelines() throws {
        let endpoint = try #require(
            GitLabPipelineEndpoints
                .mergeRequestPipelines(
                    at:
                        GitLabMergeRequestRoute(
                            projectID: 42,
                            mergeRequestIID: 7
                        )
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
                    "pipelines",
                ]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "20"
                    ),
                ]
        )
    }

    @Test("Rejects invalid merge request pipeline route values")
    func rejectsInvalidMergeRequestRoute() {
        #expect(
            GitLabPipelineEndpoints
                .mergeRequestPipelines(
                    at:
                        GitLabMergeRequestRoute(
                            projectID: 0,
                            mergeRequestIID: 7
                        )
                ) == nil
        )
        #expect(
            GitLabPipelineEndpoints
                .mergeRequestPipelines(
                    at:
                        GitLabMergeRequestRoute(
                            projectID: 42,
                            mergeRequestIID: -1
                        )
                ) == nil
        )
    }

    @Test("Builds a pipeline detail route")
    func buildsPipelineDetail() throws {
        let route = try #require(
            GitLabPipelineRoute(
                projectID: 42,
                pipelineID: 501
            )
        )
        let endpoint =
            GitLabPipelineEndpoints.pipeline(
                at: route
            )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == [
                    "projects",
                    "42",
                    "pipelines",
                    "501",
                ]
        )
        #expect(endpoint.queryItems.isEmpty)
    }

    @Test("Builds paginated jobs with earlier attempts")
    func buildsPipelineJobs() throws {
        let endpoint =
            GitLabPipelineEndpoints.jobs(
                at: try route()
            )

        #expect(endpoint.method == .get)
        #expect(endpoint.requiredAccess == .read)
        #expect(
            endpoint.pathComponents
                == pipelinePath + ["jobs"]
        )
        #expect(
            endpoint.queryItems
                == [
                    URLQueryItem(
                        name: "include_retried",
                        value: "true"
                    ),
                    URLQueryItem(
                        name: "per_page",
                        value: "50"
                    ),
                ]
        )
    }

    @Test("Builds current and legacy trigger job routes")
    func buildsTriggerJobs() throws {
        let preferred =
            GitLabPipelineEndpoints
                .triggerJobs(
                    at: try route()
                )
        let legacy =
            GitLabPipelineEndpoints
                .legacyTriggerJobs(
                    at: try route()
                )

        #expect(
            preferred.pathComponents
                == pipelinePath
                + ["trigger_jobs"]
        )
        #expect(
            legacy.pathComponents
                == pipelinePath
                + ["bridges"]
        )
        #expect(
            preferred.queryItems
                == [
                    URLQueryItem(
                        name: "per_page",
                        value: "50"
                    ),
                ]
        )
        #expect(
            legacy.queryItems
                == preferred.queryItems
        )
        #expect(preferred.requiredAccess == .read)
        #expect(legacy.requiredAccess == .read)
    }

    @Test("Pipeline route requires positive project and pipeline IDs")
    func validatesPipelineRoute() {
        #expect(
            GitLabPipelineRoute(
                projectID: 42,
                pipelineID: 501
            ) != nil
        )
        #expect(
            GitLabPipelineRoute(
                projectID: 0,
                pipelineID: 501
            ) == nil
        )
        #expect(
            GitLabPipelineRoute(
                projectID: 42,
                pipelineID: 0
            ) == nil
        )
    }

    private var pipelinePath: [String] {
        [
            "projects",
            "42",
            "pipelines",
            "501",
        ]
    }

    private func route()
        throws -> GitLabPipelineRoute
    {
        try #require(
            GitLabPipelineRoute(
                projectID: 42,
                pipelineID: 501
            )
        )
    }
}
