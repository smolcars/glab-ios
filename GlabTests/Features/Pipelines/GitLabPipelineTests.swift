import Foundation
import Testing
@testable import Glab

@Suite("GitLab pipeline contracts")
struct GitLabPipelineTests {
    @Test(
        "Maps known and future CI statuses without inventing success",
        arguments: [
            ("created", "Created", true, false),
            (
                "waiting_for_resource",
                "Waiting for resources",
                true,
                false
            ),
            ("preparing", "Preparing", true, false),
            (
                "waiting_for_callback",
                "Waiting for callback",
                true,
                false
            ),
            ("pending", "Pending", true, false),
            ("running", "Running", true, false),
            ("canceling", "Canceling", true, false),
            ("scheduled", "Scheduled", true, false),
            ("manual", "Manual", false, false),
            ("success", "Passed", false, true),
            ("failed", "Failed", false, true),
            ("canceled", "Canceled", false, true),
            ("skipped", "Skipped", false, true),
            (
                "future_pipeline_state",
                "Unknown",
                false,
                false
            ),
        ]
    )
    func mapsStatuses(
        rawValue: String,
        title: String,
        isActivelyChanging: Bool,
        isTerminal: Bool
    ) {
        let status = GitLabCIStatus(
            rawValue: rawValue
        )

        #expect(status.rawValue == rawValue)
        #expect(status.title == title)
        #expect(
            status.isActivelyChanging
                == isActivelyChanging
        )
        #expect(status.isTerminal == isTerminal)
    }

    @Test(
        "Distinguishes waiting jobs from animated activity",
        arguments: [
            (
                "created",
                "Waiting for prerequisites",
                false,
                true
            ),
            (
                "waiting_for_resource",
                "Waiting for resource",
                false,
                true
            ),
            (
                "waiting_for_callback",
                "Waiting for callback",
                false,
                true
            ),
            (
                "pending",
                "Waiting for runner",
                false,
                true
            ),
            (
                "scheduled",
                "Scheduled",
                false,
                true
            ),
            ("preparing", "Preparing", true, false),
            ("running", "Running", true, false),
            ("canceling", "Canceling", true, false),
            ("manual", "Manual", false, false),
            ("success", "Passed", false, false),
            (
                "future_pipeline_state",
                "Unknown",
                false,
                false
            ),
        ]
    )
    func mapsJobPresentation(
        rawValue: String,
        jobTitle: String,
        showsActivityAnimation: Bool,
        showsWaitingIndicator: Bool
    ) {
        let status = GitLabCIStatus(
            rawValue: rawValue
        )

        #expect(status.jobTitle == jobTitle)
        #expect(
            status.showsActivityAnimation
                == showsActivityAnimation
        )
        #expect(
            status.showsWaitingIndicator
                == showsWaitingIndicator
        )
    }

    @Test(
        "Maps every CI state to a nonempty status icon",
        arguments: [
            "created",
            "waiting_for_resource",
            "preparing",
            "waiting_for_callback",
            "pending",
            "running",
            "canceling",
            "scheduled",
            "manual",
            "success",
            "failed",
            "canceled",
            "skipped",
            "future_pipeline_state",
        ]
    )
    func mapsStatusIcons(
        rawValue: String
    ) {
        #expect(
            !GitLabCIStatus(
                rawValue: rawValue
            )
            .systemImage.isEmpty
        )
    }

    @Test("Decodes a minimal merge request pipeline")
    func decodesMinimalPipeline() throws {
        let pipeline: GitLabPipeline =
            try decode(
                """
                {
                  "id": 77,
                  "sha": "959e04d7c7a30600c894bd3c0cd0e1ce7f42c11d",
                  "ref": "refs/merge-requests/7/head",
                  "status": "future_pipeline_state"
                }
                """
            )

        #expect(pipeline.id == 77)
        #expect(pipeline.iid == nil)
        #expect(pipeline.projectID == nil)
        #expect(pipeline.name == nil)
        #expect(
            pipeline.status.rawValue
                == "future_pipeline_state"
        )
        #expect(pipeline.user == nil)
        #expect(pipeline.detailedStatus == nil)
        #expect(pipeline.duration == nil)
        #expect(pipeline.safeWebURL == nil)
    }

    @Test("Decodes authoritative pipeline metadata")
    func decodesPipelineDetail() throws {
        let pipeline: GitLabPipeline =
            try decode(
                """
                {
                  "id": 501,
                  "iid": 144,
                  "project_id": 42,
                  "name": "Build pipeline",
                  "sha": "50f0acb76a40e34a4ff304f7347dcc6587da8a14",
                  "ref": "main",
                  "status": "success",
                  "source": "merge_request_event",
                  "created_at": "2026-07-29T01:05:07Z",
                  "updated_at": "2026-07-29T01:05:50Z",
                  "started_at": "2026-07-29T01:05:14Z",
                  "finished_at": "2026-07-29T01:05:50Z",
                  "duration": 34.5,
                  "queued_duration": 6,
                  "coverage": "91.4",
                  "archived": false,
                  "web_url": "https://gitlab.example.com/group/project/-/pipelines/501",
                  "user": {
                    "id": 9,
                    "username": "octocat",
                    "name": "Octo Cat",
                    "avatar_url": "https://gitlab.example.com/avatar.png",
                    "web_url": "https://gitlab.example.com/octocat"
                  },
                  "detailed_status": {
                    "text": "passed",
                    "label": "passed",
                    "group": "success",
                    "tooltip": "passed",
                    "has_details": true,
                    "details_path": "/group/project/-/pipelines/501"
                  }
                }
                """
            )

        #expect(pipeline.iid == 144)
        #expect(pipeline.projectID == 42)
        #expect(pipeline.name == "Build pipeline")
        #expect(pipeline.status.title == "Passed")
        #expect(pipeline.duration == 34.5)
        #expect(pipeline.queuedDuration == 6)
        #expect(pipeline.coverage == "91.4")
        #expect(pipeline.user?.id == 9)
        #expect(
            pipeline.user?.displayName
                == "Octo Cat"
        )
        #expect(
            pipeline.user?.summary
                .avatarURL?
                .absoluteString
                == "https://gitlab.example.com/avatar.png"
        )
        #expect(
            pipeline.detailedStatus?
                .hasDetails == true
        )
        #expect(
            pipeline.safeWebURL?
                .absoluteString
                == "https://gitlab.example.com/group/project/-/pipelines/501"
        )
    }

    @Test("Drops malformed optional pipeline metadata")
    func toleratesMalformedOptionalPipelineData()
        throws
    {
        let pipeline: GitLabPipeline =
            try decode(
                """
                {
                  "id": 501,
                  "iid": "bad",
                  "project_id": [],
                  "name": 7,
                  "sha": "abc123",
                  "ref": "main",
                  "status": "running",
                  "duration": -2,
                  "queued_duration": -3,
                  "web_url": {"unsafe": true},
                  "user": "bad",
                  "detailed_status": 4
                }
                """
            )

        #expect(pipeline.iid == nil)
        #expect(pipeline.projectID == nil)
        #expect(pipeline.name == nil)
        #expect(pipeline.duration == nil)
        #expect(pipeline.queuedDuration == nil)
        #expect(pipeline.webURL == nil)
        #expect(pipeline.user == nil)
        #expect(pipeline.detailedStatus == nil)
    }

    @Test("Rejects malformed required pipeline identity")
    func rejectsMalformedPipeline() {
        #expect(
            throws: GitLabAPIError.decoding
        ) {
            let _: GitLabPipeline =
                try decode(
                    """
                    {
                      "id": 0,
                      "sha": "abc123",
                      "ref": "main",
                      "status": "success"
                    }
                    """
                )
        }
        #expect(
            throws: GitLabAPIError.decoding
        ) {
            let _: GitLabPipeline =
                try decode(
                    """
                    {
                      "id": 501,
                      "sha": " ",
                      "ref": "main",
                      "status": "success"
                    }
                    """
                )
        }
    }

    @Test("Rejects unsafe pipeline web destinations")
    func rejectsUnsafeWebURL() throws {
        let pipeline: GitLabPipeline =
            try decode(
                """
                {
                  "id": 501,
                  "sha": "abc123",
                  "ref": "main",
                  "status": "success",
                  "web_url": "http://gitlab.example.com/pipelines/501"
                }
                """
            )

        #expect(pipeline.webURL != nil)
        #expect(pipeline.safeWebURL == nil)
    }

    @Test("Decodes a full pipeline job and artifact summary")
    func decodesPipelineJob() throws {
        let job: GitLabPipelineJob =
            try decode(
                """
                {
                  "id": 800,
                  "name": "ios-tests",
                  "stage": "test",
                  "status": "failed",
                  "allow_failure": true,
                  "archived": true,
                  "failure_reason": "script_failure",
                  "created_at": "2026-07-29T01:05:07Z",
                  "started_at": "2026-07-29T01:05:14Z",
                  "finished_at": "2026-07-29T01:05:50Z",
                  "duration": 36,
                  "queued_duration": 7,
                  "ref": "main",
                  "web_url": "https://gitlab.example.com/group/project/-/jobs/800",
                  "pipeline": {
                    "id": 501,
                    "project_id": 42,
                    "ref": "main",
                    "sha": "abc123",
                    "status": "failed"
                  },
                  "user": {
                    "id": 9,
                    "username": "octocat",
                    "name": "Octo Cat"
                  },
                  "runner": {
                    "id": 32,
                    "description": "iOS runner",
                    "runner_type": "project_type",
                    "online": true,
                    "paused": false,
                    "is_shared": false,
                    "status": "online"
                  },
                  "runner_manager": {
                    "id": 4,
                    "system_id": "runner-system",
                    "platform": "darwin",
                    "architecture": "arm64",
                    "status": "online"
                  },
                  "artifacts": [
                    {
                      "file_type": "archive",
                      "size": 1000,
                      "filename": "artifacts.zip",
                      "file_format": "zip"
                    },
                    {
                      "file_type": "trace",
                      "size": 1500,
                      "filename": "job.log",
                      "file_format": "raw"
                    },
                    {
                      "file_type": "junit",
                      "size": -5,
                      "filename": "junit.xml",
                      "file_format": "xml"
                    }
                  ]
                }
                """
            )

        #expect(job.id == 800)
        #expect(job.name == "ios-tests")
        #expect(job.stage == "test")
        #expect(job.status.title == "Failed")
        #expect(job.allowFailure)
        #expect(job.archived == true)
        #expect(job.pipeline?.id == 501)
        #expect(job.pipeline?.projectID == 42)
        #expect(job.runner?.id == 32)
        #expect(job.runnerManager?.platform == "darwin")
        #expect(job.artifactSummary.artifacts.count == 3)
        #expect(job.artifactSummary.totalSize == 2500)
        #expect(job.artifactSummary.hasArchive)
        #expect(
            job.safeWebURL?
                .absoluteString
                == "https://gitlab.example.com/group/project/-/jobs/800"
        )
    }

    @Test("Decodes a minimal job with missing optional data")
    func decodesMinimalPipelineJob() throws {
        let job: GitLabPipelineJob =
            try decode(
                """
                {
                  "id": 801,
                  "name": "manual deploy",
                  "stage": "deploy",
                  "status": "manual"
                }
                """
            )

        #expect(job.status.title == "Manual")
        #expect(!job.allowFailure)
        #expect(job.duration == nil)
        #expect(job.archived == nil)
        #expect(job.user == nil)
        #expect(job.runner == nil)
        #expect(job.artifactSummary.artifacts.isEmpty)
    }

    @Test("Decodes a trigger job and downstream pipeline")
    func decodesTriggerJob() throws {
        let trigger: GitLabPipelineTriggerJob =
            try decode(
                """
                {
                  "id": 802,
                  "name": "mobile child",
                  "stage": "test",
                  "status": "pending",
                  "allow_failure": false,
                  "downstream_pipeline": {
                    "id": 601,
                    "project_id": 84,
                    "sha": "def456",
                    "ref": "child-main",
                    "status": "running",
                    "web_url": "https://gitlab.example.com/group/child/-/pipelines/601"
                  }
                }
                """
            )

        #expect(trigger.id == 802)
        #expect(trigger.stage == "test")
        #expect(trigger.status.title == "Pending")
        #expect(
            trigger.downstreamPipeline?
                .projectID == 84
        )
        #expect(
            trigger.downstreamPipeline?
                .id == 601
        )
        #expect(
            trigger.downstreamRoute
                == GitLabPipelineRoute(
                    projectID: 84,
                    pipelineID: 601
                )
        )
    }

    @Test("Decodes a manual trigger before its child exists")
    func decodesManualTriggerJob() throws {
        let trigger: GitLabPipelineTriggerJob =
            try decode(
                """
                {
                  "id": 803,
                  "name": "optional deployment",
                  "stage": "deploy",
                  "status": "manual",
                  "allow_failure": true,
                  "pipeline": {
                    "id": 501,
                    "project_id": 42
                  },
                  "downstream_pipeline": null
                }
                """
            )

        #expect(trigger.status.rawValue == "manual")
        #expect(trigger.allowFailure)
        #expect(trigger.pipeline?.id == 501)
        #expect(trigger.pipeline?.projectID == 42)
        #expect(trigger.downstreamPipeline == nil)
        #expect(trigger.downstreamRoute == nil)
    }

    @Test("Rejects malformed required job fields")
    func rejectsMalformedJob() {
        #expect(
            throws: GitLabAPIError.decoding
        ) {
            let _: GitLabPipelineJob =
                try decode(
                    """
                    {
                      "id": 801,
                      "name": " ",
                      "stage": "test",
                      "status": "success"
                    }
                    """
                )
        }
        #expect(
            throws: GitLabAPIError.decoding
        ) {
            let _: GitLabPipelineJob =
                try decode(
                    """
                    {
                      "id": 801,
                      "name": "tests",
                      "stage": "",
                      "status": "success"
                    }
                    """
                )
        }
    }

    private func decode<Value>(
        _ json: String
    ) throws(GitLabAPIError) -> Value
    where Value: Decodable & Sendable {
        try GitLabAPIResponseDecoder.decode(
            GitLabRawAPIResponse(
                body: Data(json.utf8),
                metadata:
                    GitLabResponseMetadata(),
                entityTag: nil,
                lastModified: nil
            )
        )
        .value
    }
}
