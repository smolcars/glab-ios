import Foundation

nonisolated enum GitLabPipelineEndpoints {
    static func mergeRequestPipelines(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<
        [GitLabPipeline]
    >? {
        guard
            route.projectID > 0,
            route.mergeRequestIID > 0
        else {
            return nil
        }

        return .get(
            requires: .read,
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
                "pipelines",
            ],
            query: [
                .init(
                    name: "per_page",
                    value: "20"
                ),
            ]
        )
    }

    static func pipeline(
        at route: GitLabPipelineRoute
    ) -> GitLabAPIRequest<
        GitLabPipeline
    > {
        .get(
            requires: .read,
            path: pipelinePath(route)
        )
    }

    static func jobs(
        at route: GitLabPipelineRoute
    ) -> GitLabAPIRequest<
        [GitLabPipelineJob]
    > {
        .get(
            requires: .read,
            path: pipelinePath(route) + ["jobs"],
            query: [
                .init(
                    name: "include_retried",
                    value: "true"
                ),
                .init(
                    name: "per_page",
                    value: "50"
                ),
            ]
        )
    }

    static func triggerJobs(
        at route: GitLabPipelineRoute
    ) -> GitLabAPIRequest<
        [GitLabPipelineTriggerJob]
    > {
        .get(
            requires: .read,
            path:
                pipelinePath(route)
                + ["trigger_jobs"],
            query: triggerJobsQuery
        )
    }

    static func legacyTriggerJobs(
        at route: GitLabPipelineRoute
    ) -> GitLabAPIRequest<
        [GitLabPipelineTriggerJob]
    > {
        .get(
            requires: .read,
            path:
                pipelinePath(route)
                + ["bridges"],
            query: triggerJobsQuery
        )
    }

    static func retryPipeline(
        at route: GitLabPipelineRoute
    ) -> GitLabAPIRequest<GitLabPipeline> {
        .post(
            requires: .write,
            path:
                pipelinePath(route)
                + ["retry"]
        )
    }

    static func cancelPipeline(
        at route: GitLabPipelineRoute
    ) -> GitLabAPIRequest<GitLabPipeline> {
        .post(
            requires: .write,
            path:
                pipelinePath(route)
                + ["cancel"]
        )
    }

    static func retryJob(
        at route: GitLabJobRoute
    ) -> GitLabAPIRequest<
        GitLabPipelineJob
    > {
        .post(
            requires: .write,
            path: jobPath(route) + ["retry"]
        )
    }

    static func cancelJob(
        at route: GitLabJobRoute
    ) -> GitLabAPIRequest<
        GitLabPipelineJob
    > {
        .post(
            requires: .write,
            path: jobPath(route) + ["cancel"]
        )
    }

    static func playJob(
        at route: GitLabJobRoute
    ) -> GitLabAPIRequest<
        GitLabPipelineJob
    > {
        .post(
            requires: .write,
            path: jobPath(route) + ["play"]
        )
    }

    static func createMergeRequestPipeline(
        at route: GitLabMergeRequestRoute
    ) -> GitLabAPIRequest<
        GitLabPipeline
    >? {
        guard
            route.projectID > 0,
            route.mergeRequestIID > 0
        else {
            return nil
        }

        return .post(
            requires: .write,
            path: [
                "projects",
                String(route.projectID),
                "merge_requests",
                String(route.mergeRequestIID),
                "pipelines",
            ]
        )
    }

    private static func pipelinePath(
        _ route: GitLabPipelineRoute
    ) -> [String] {
        [
            "projects",
            String(route.projectID),
            "pipelines",
            String(route.pipelineID),
        ]
    }

    private static func jobPath(
        _ route: GitLabJobRoute
    ) -> [String] {
        [
            "projects",
            String(route.projectID),
            "jobs",
            String(route.jobID),
        ]
    }

    private static var triggerJobsQuery:
        [URLQueryItem]
    {
        [
            .init(
                name: "per_page",
                value: "50"
            ),
        ]
    }
}
