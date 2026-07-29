import Foundation

nonisolated enum GitLabPipelineStageRowID:
    Equatable,
    Hashable,
    Sendable
{
    case job(Int)
    case triggerJob(Int)
}

nonisolated enum GitLabPipelineJobAttempt:
    Equatable,
    Sendable
{
    case only
    case latest
    case earlier
}

nonisolated enum GitLabPipelineStageRowContent:
    Equatable,
    Sendable
{
    case job(GitLabPipelineJob)
    case triggerJob(
        GitLabPipelineTriggerJob
    )
}

nonisolated struct GitLabPipelineStageRow:
    Equatable,
    Identifiable,
    Sendable
{
    let id: GitLabPipelineStageRowID
    let name: String
    let status: GitLabCIStatus
    let attempt: GitLabPipelineJobAttempt
    let content:
        GitLabPipelineStageRowContent
}

nonisolated struct GitLabPipelineStage:
    Equatable,
    Identifiable,
    Sendable
{
    let id: String
    let name: String
    let rows: [GitLabPipelineStageRow]

    var statusCounts:
        [GitLabCIStatus: Int]
    {
        rows.reduce(into: [:]) {
            $0[$1.status, default: 0] += 1
        }
    }

    var hasAnimatingRows: Bool {
        rows.contains {
            $0.status
                .showsActivityAnimation
        }
    }

    var hasWaitingRows: Bool {
        rows.contains {
            $0.status
                .showsWaitingIndicator
        }
    }
}

nonisolated enum GitLabPipelineStageProjector {
    @concurrent
    static func project(
        jobs: [GitLabPipelineJob],
        triggerJobs:
            [GitLabPipelineTriggerJob]
    ) async -> [GitLabPipelineStage] {
        let inputs =
            jobs.map(Input.job)
            + triggerJobs.map(
                Input.triggerJob
            )
        var stageNames: [String] = []
        var stageRows:
            [String: [Input]] = [:]

        for input in inputs {
            let stageID =
                normalized(input.stage)
            if stageRows[stageID] == nil {
                stageNames.append(stageID)
                stageRows[stageID] = []
            }
            stageRows[stageID]?.append(input)
        }

        return stageNames.map { stageID in
            let inputs =
                stageRows[stageID] ?? []
            let counts = Dictionary(
                grouping: inputs,
                by: \.attemptKey
            )
            .mapValues(\.count)
            var seenCounts:
                [AttemptKey: Int] = [:]

            let rows = inputs.map { input in
                let key = input.attemptKey
                let occurrence =
                    seenCounts[key, default: 0]
                seenCounts[key] =
                    occurrence + 1
                let count = counts[key] ?? 1
                let attempt:
                    GitLabPipelineJobAttempt =
                    if count == 1 {
                        .only
                    } else if occurrence == 0 {
                        .latest
                    } else {
                        .earlier
                    }

                return input.row(
                    attempt: attempt
                )
            }

            return GitLabPipelineStage(
                id: stageID,
                name:
                    inputs.first?.stage
                    ?? stageID,
                rows: rows
            )
        }
    }

    private static func normalized(
        _ value: String
    ) -> String {
        value.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        .lowercased()
    }
}

private nonisolated extension
    GitLabPipelineStageProjector
{
    struct AttemptKey:
        Equatable,
        Hashable,
        Sendable
    {
        let kind: Kind
        let name: String
    }

    enum Kind:
        Equatable,
        Hashable,
        Sendable
    {
        case job
        case triggerJob
    }

    enum Input: Sendable {
        case job(GitLabPipelineJob)
        case triggerJob(
            GitLabPipelineTriggerJob
        )

        var stage: String {
            switch self {
            case let .job(job):
                job.stage
            case let .triggerJob(job):
                job.stage
            }
        }

        var attemptKey: AttemptKey {
            switch self {
            case let .job(job):
                AttemptKey(
                    kind: .job,
                    name: job.name
                )
            case let .triggerJob(job):
                AttemptKey(
                    kind: .triggerJob,
                    name: job.name
                )
            }
        }

        func row(
            attempt: GitLabPipelineJobAttempt
        ) -> GitLabPipelineStageRow {
            switch self {
            case let .job(job):
                GitLabPipelineStageRow(
                    id: .job(job.id),
                    name: job.name,
                    status: job.status,
                    attempt: attempt,
                    content: .job(job)
                )
            case let .triggerJob(job):
                GitLabPipelineStageRow(
                    id: .triggerJob(job.id),
                    name: job.name,
                    status: job.status,
                    attempt: attempt,
                    content:
                        .triggerJob(job)
                )
            }
        }
    }
}
