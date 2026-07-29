import Foundation
import Testing
@testable import Glab

@Suite("GitLab pipeline stage projection")
struct GitLabPipelineStageTests {
    @Test("Preserves stage and server order while labeling attempts")
    func projectsStableStages() async throws {
        let jobs = try [
            job(
                id: 900,
                name: "ios-tests",
                stage: "test",
                status: "running"
            ),
            job(
                id: 850,
                name: "lint",
                stage: "test",
                status: "success"
            ),
            job(
                id: 800,
                name: "ios-tests",
                stage: "test",
                status: "failed"
            ),
        ]
        let triggers = try [
            trigger(
                id: 700,
                name: "mobile child",
                stage: "deploy"
            ),
        ]

        let stages =
            await GitLabPipelineStageProjector
                .project(
                    jobs: jobs,
                    triggerJobs: triggers
                )

        #expect(
            stages.map(\.name)
                == ["test", "deploy"]
        )
        #expect(
            stages[0].rows.map(\.id)
                == [
                    .job(900),
                    .job(850),
                    .job(800),
                ]
        )
        #expect(
            stages[0].rows
                .map(\.attempt)
                == [
                    .latest,
                    .only,
                    .earlier,
                ]
        )
        #expect(
            stages[1].rows.map(\.id)
                == [.triggerJob(700)]
        )
        #expect(
            stages[1].rows[0].attempt
                == .only
        )
        #expect(
            stages[0].statusCounts[
                GitLabCIStatus(
                    rawValue: "running"
                )
            ] == 1
        )
        #expect(stages[0].hasAnimatingRows)
        #expect(stages[1].hasWaitingRows)
    }

    @Test("Keeps unknown and manual states visible")
    func preservesFailClosedStatuses() async throws {
        let stages =
            await GitLabPipelineStageProjector
                .project(
                    jobs: try [
                        job(
                            id: 1,
                            name: "future",
                            stage: "verify",
                            status:
                                "future_job_state"
                        ),
                        job(
                            id: 2,
                            name: "deploy",
                            stage: "deploy",
                            status: "manual"
                        ),
                    ],
                    triggerJobs: []
                )

        #expect(
            stages.flatMap(\.rows)
                .map(\.status.title)
                == ["Unknown", "Manual"]
        )
        #expect(
            !stages.flatMap(\.rows)
                .contains {
                    $0.status
                        .isActivelyChanging
                }
        )
        #expect(
            stages.allSatisfy {
                !$0.hasAnimatingRows
                    && !$0.hasWaitingRows
            }
        )
    }

    @Test("Separates waiting stages from executing stages")
    func classifiesStageActivity() async throws {
        let stages =
            await GitLabPipelineStageProjector
                .project(
                    jobs: try [
                        job(
                            id: 1,
                            name: "apply",
                            stage: "deploy",
                            status: "created"
                        ),
                        job(
                            id: 2,
                            name: "release",
                            stage: "deploy",
                            status: "pending"
                        ),
                        job(
                            id: 3,
                            name: "tests",
                            stage: "verify",
                            status: "running"
                        ),
                    ],
                    triggerJobs: []
                )

        #expect(stages[0].hasWaitingRows)
        #expect(!stages[0].hasAnimatingRows)
        #expect(
            stages[0].rows[0].metadataSummary
                == "Waiting for prerequisites"
        )
        #expect(
            stages[0].rows[1].metadataSummary
                == "Waiting for runner"
        )
        #expect(!stages[1].hasWaitingRows)
        #expect(stages[1].hasAnimatingRows)
    }

    @Test("Projects 5,000 rows within a generous budget")
    func projectsLargePipelineQuickly() async throws {
        let jobs = try (1...5_000).map {
            try job(
                id: $0,
                name: "job-\($0 % 250)",
                stage: "stage-\($0 % 25)",
                status: "success"
            )
        }
        let clock = ContinuousClock()
        let start = clock.now

        let stages =
            await GitLabPipelineStageProjector
                .project(
                    jobs: jobs,
                    triggerJobs: []
                )
        let elapsed = start.duration(
            to: clock.now
        )

        #expect(stages.count == 25)
        #expect(
            stages.reduce(0) {
                $0 + $1.rows.count
            } == 5_000
        )
        #expect(
            elapsed < .seconds(2)
        )
    }

    private func job(
        id: Int,
        name: String,
        stage: String,
        status: String
    ) throws -> GitLabPipelineJob {
        try decode(
            """
            {
              "id": \(id),
              "name": "\(name)",
              "stage": "\(stage)",
              "status": "\(status)"
            }
            """
        )
    }

    private func trigger(
        id: Int,
        name: String,
        stage: String
    ) throws -> GitLabPipelineTriggerJob {
        try decode(
            """
            {
              "id": \(id),
              "name": "\(name)",
              "stage": "\(stage)",
              "status": "pending"
            }
            """
        )
    }

    private func decode<Value>(
        _ json: String
    ) throws -> Value
    where Value: Decodable & Sendable {
        try JSONDecoder().decode(
            Value.self,
            from: Data(json.utf8)
        )
    }
}
