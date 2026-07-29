#if DEBUG
    import SwiftUI

    struct GitLabPipelineFixtureView: View {
        private let accountID =
            GitLabAccountID(
                host:
                    try! GitLabHost(
                        "gitlab.example.com"
                    ),
                userID: 7
            )
        private let loader =
            GitLabPipelineFixtureLoader()
        private let jobTraceLoader =
            GitLabPipelineFixtureJobTraceLoader()
        @State private var appSession =
            AppSession(
                credentialStore:
                    KeychainGitLabCredentialStore(),
                accountIndexStore:
                    UserDefaultsGitLabAccountIndexStore(),
                responseCache:
                    FileGitLabResponseCache(),
                discussionDraftStore:
                    FileGitLabDiscussionDraftStore(),
                resourceEditDraftStore:
                    FileGitLabResourceEditDraftStore(),
                issueCreationDraftStore:
                    FileGitLabIssueCreationDraftStore()
            )

        var body: some View {
            NavigationStack {
                GitLabMergeRequestPipelinesView(
                    route:
                        GitLabMergeRequestRoute(
                            projectID: 42,
                            mergeRequestIID: 7
                        ),
                    loader: loader,
                    accountID: accountID,
                    appSession: appSession,
                    apiAccess: .readWrite,
                    isAccountCurrent: {
                        true
                    },
                    isMergeRequestOpen: {
                        true
                    }
                )
            }
            .environment(
                \.gitLabJobTraceLoader,
                jobTraceLoader
            )
        }
    }

    private nonisolated struct
        GitLabPipelineFixtureLoader:
        GitLabPipelineLoading,
        Sendable
    {
        func loadMergeRequestPipelinesPage(
            at route: GitLabMergeRequestRoute,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabResourcePage<
                GitLabPipeline
            >
        {
            guard
                route.projectID == 42,
                route.mergeRequestIID == 7
            else {
                throw .api(.invalidResponse)
            }
            return GitLabResourcePage(
                items: Self.pipelines,
                nextPageURL: nil,
                totalCount:
                    Self.pipelines.count
            )
        }

        func loadMergeRequestPipelinesFirstPage(
            at route: GitLabMergeRequestRoute,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onPage:
                @escaping @Sendable (
                    GitLabResourcePageEvent<
                        GitLabPipeline
                    >
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            let page =
                try await loadMergeRequestPipelinesPage(
                    at: route,
                    after: nil
                )
            await onPage(
                GitLabResourcePageEvent(
                    page: page,
                    source: .network
                )
            )
        }

        func loadPipeline(
            at route: GitLabPipelineRoute,
            cacheLifetime:
                GitLabPipelineCacheLifetime,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<
                        GitLabPipeline
                    >
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            guard
                let pipeline =
                    Self.pipeline(
                        id: route.pipelineID
                    ),
                pipeline.projectID
                    == route.projectID
            else {
                throw .api(.notFound)
            }
            await onResponse(
                GitLabAPIResponseEvent(
                    value: pipeline,
                    metadata:
                        GitLabResponseMetadata(),
                    source: .network
                )
            )
        }

        func loadPipelineJobsPage(
            at route: GitLabPipelineRoute,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabResourcePage<
                GitLabPipelineJob
            >
        {
            guard
                route.projectID == 42,
                Self.pipeline(
                    id: route.pipelineID
                ) != nil
            else {
                throw .api(.notFound)
            }
            let jobs =
                route.pipelineID == 501
                ? Self.jobs
                : Self.childJobs
            return GitLabResourcePage(
                items: jobs,
                nextPageURL: nil,
                totalCount: jobs.count
            )
        }

        func loadPipelineJobsFirstPage(
            at route: GitLabPipelineRoute,
            cacheLifetime:
                GitLabPipelineCacheLifetime,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onPage:
                @escaping @Sendable (
                    GitLabResourcePageEvent<
                        GitLabPipelineJob
                    >
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            let page =
                try await loadPipelineJobsPage(
                    at: route,
                    after: nil
                )
            await onPage(
                GitLabResourcePageEvent(
                    page: page,
                    source: .network
                )
            )
        }

        func loadPipelineTriggerJobsPage(
            at route: GitLabPipelineRoute,
            capability:
                GitLabPipelineTriggerJobsCapability,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabPipelineTriggerJobsPage
        {
            guard route.projectID == 42 else {
                throw .api(.notFound)
            }
            let jobs:
                [GitLabPipelineTriggerJob] =
                switch route.pipelineID {
                case 501:
                    Self.triggerJobs
                case 601:
                    Self.childTriggerJobs
                default:
                    []
                }
            return GitLabPipelineTriggerJobsPage(
                page:
                    GitLabResourcePage(
                        items: jobs,
                        nextPageURL: nil,
                        totalCount:
                            jobs.count
                    ),
                capability: capability
            )
        }

        func loadPipelineTriggerJobsFirstPage(
            at route: GitLabPipelineRoute,
            capability:
                GitLabPipelineTriggerJobsCapability,
            cacheLifetime:
                GitLabPipelineCacheLifetime,
            refreshBehavior:
                GitLabCacheRefreshBehavior,
            onPage:
                @escaping @Sendable (
                    GitLabResourcePageEvent<
                        GitLabPipelineTriggerJob
                    >
                ) async -> Void
        ) async throws(GitLabSessionClientError)
            -> GitLabPipelineTriggerJobsCapability
        {
            let result =
                try await loadPipelineTriggerJobsPage(
                    at: route,
                    capability: capability,
                    after: nil
                )
            await onPage(
                GitLabResourcePageEvent(
                    page: result.page,
                    source: .network
                )
            )
            return result.capability
        }

        private static let pipelines:
            [GitLabPipeline] =
            decode(
                """
                [
                  {
                    "id": 501,
                    "iid": 91,
                    "project_id": 42,
                    "name": "Merge request validation",
                    "sha": "4f4c3e12a9bd349f812056112bed9c3b8c21aabc",
                    "ref": "refs/merge-requests/7/head",
                    "status": "running",
                    "source": "merge_request_event",
                    "duration": 94,
                    "web_url": "https://gitlab.example.com/group/project/-/pipelines/501",
                    "user": {
                      "id": 7,
                      "username": "nitesh",
                      "name": "Nitesh Balusu"
                    }
                  },
                  {
                    "id": 500,
                    "iid": 90,
                    "project_id": 42,
                    "sha": "3c2b1a09876543211234567890abcdef12345678",
                    "ref": "refs/merge-requests/7/head",
                    "status": "success"
                  },
                  {
                    "id": 499,
                    "iid": 89,
                    "project_id": 42,
                    "sha": "2b1a09876543211234567890abcdef1234567890",
                    "ref": "refs/merge-requests/7/head",
                    "status": "failed"
                  },
                  {
                    "id": 498,
                    "iid": 88,
                    "project_id": 42,
                    "sha": "1a09876543211234567890abcdef123456789012",
                    "ref": "refs/merge-requests/7/head",
                    "status": "manual"
                  }
                ]
                """
            )

        private static let childPipeline:
            GitLabPipeline =
            decode(
                """
                {
                  "id": 601,
                  "iid": 12,
                  "project_id": 42,
                  "name": "iOS child pipeline",
                  "sha": "6019876543211234567890abcdef123456789012",
                  "ref": "mobile",
                  "status": "success",
                  "web_url": "https://gitlab.example.com/group/project/-/pipelines/601"
                }
                """
            )

        private static let jobs:
            [GitLabPipelineJob] =
            decode(
                """
                [
                  {
                    "id": 910,
                    "name": "compile-ios-release",
                    "stage": "build",
                    "status": "success",
                    "duration": 73,
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/910",
                    "pipeline": {"id": 501, "project_id": 42}
                  },
                  {
                    "id": 909,
                    "name": "swiftlint",
                    "stage": "test",
                    "status": "success",
                    "duration": 12,
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/909",
                    "pipeline": {"id": 501, "project_id": 42}
                  },
                  {
                    "id": 908,
                    "name": "Unit tests on iPhone 17 Pro with an intentionally long configuration name",
                    "stage": "test",
                    "status": "running",
                    "allow_failure": false,
                    "duration": 41,
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/908",
                    "pipeline": {"id": 501, "project_id": 42}
                  },
                  {
                    "id": 907,
                    "name": "Unit tests on iPhone 17 Pro with an intentionally long configuration name",
                    "stage": "test",
                    "status": "failed",
                    "allow_failure": true,
                    "duration": 39,
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/907",
                    "pipeline": {"id": 501, "project_id": 42}
                  },
                  {
                    "id": 906,
                    "name": "security scan",
                    "stage": "verify",
                    "status": "manual",
                    "allow_failure": true,
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/906",
                    "pipeline": {"id": 501, "project_id": 42}
                  },
                  {
                    "id": 905,
                    "name": "publish",
                    "stage": "deploy",
                    "status": "pending",
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/905",
                    "pipeline": {"id": 501, "project_id": 42}
                  }
                ]
                """
            )

        private static let childJobs:
            [GitLabPipelineJob] =
            decode(
                """
                [
                  {
                    "id": 1001,
                    "name": "archive",
                    "stage": "package",
                    "status": "success",
                    "duration": 28,
                    "web_url": "https://gitlab.example.com/group/project/-/jobs/1001",
                    "pipeline": {"id": 601, "project_id": 42}
                  }
                ]
                """
            )

        private static let triggerJobs:
            [GitLabPipelineTriggerJob] =
            decode(
                """
                [
                  {
                    "id": 904,
                    "name": "mobile child",
                    "stage": "deploy",
                    "status": "running",
                    "pipeline": {"id": 501, "project_id": 42},
                    "downstream_pipeline": {
                      "id": 601,
                      "iid": 12,
                      "project_id": 42,
                      "name": "iOS child pipeline",
                      "sha": "6019876543211234567890abcdef123456789012",
                      "ref": "mobile",
                      "status": "success",
                      "web_url": "https://gitlab.example.com/group/project/-/pipelines/601"
                    }
                  },
                  {
                    "id": 903,
                    "name": "optional production deployment",
                    "stage": "deploy",
                    "status": "manual",
                    "allow_failure": true,
                    "pipeline": {"id": 501, "project_id": 42}
                  }
                ]
                """
            )

        private static let childTriggerJobs:
            [GitLabPipelineTriggerJob] =
            decode(
                """
                [
                  {
                    "id": 1002,
                    "name": "optional App Store deployment",
                    "stage": "release",
                    "status": "manual",
                    "allow_failure": true,
                    "pipeline": {"id": 601, "project_id": 42}
                  }
                ]
                """
            )

        private static func pipeline(
            id: Int
        ) -> GitLabPipeline? {
            (pipelines + [childPipeline]).first {
                $0.id == id
            }
        }

        private static func decode<Value>(
            _ json: String
        ) -> Value
        where Value: Decodable & Sendable {
            try! JSONDecoder().decode(
                Value.self,
                from: Data(json.utf8)
            )
        }
    }
#endif
