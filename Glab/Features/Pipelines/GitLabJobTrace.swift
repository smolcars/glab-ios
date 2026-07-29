import Foundation

nonisolated struct GitLabJobTraceRoute:
    Equatable,
    Hashable,
    Sendable
{
    let projectID: Int
    let jobID: Int

    init?(
        projectID: Int,
        jobID: Int
    ) {
        guard
            projectID > 0,
            jobID > 0
        else {
            return nil
        }

        self.projectID = projectID
        self.jobID = jobID
    }
}

nonisolated struct GitLabJobTraceContext:
    Equatable,
    Sendable
{
    let route: GitLabJobTraceRoute
    let jobName: String
    let status: GitLabCIStatus
    let archived: Bool?
    let erasedAt: Date?
    let webURL: URL?

    init?(
        route: GitLabJobTraceRoute,
        jobName: String,
        status: GitLabCIStatus,
        archived: Bool?,
        erasedAt: Date?,
        webURL: URL?
    ) {
        let jobName =
            jobName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard !jobName.isEmpty else {
            return nil
        }

        self.route = route
        self.jobName = jobName
        self.status = status
        self.archived = archived
        self.erasedAt = erasedAt
        self.webURL =
            GitLabWebURL.validated(webURL)
    }
}

nonisolated enum GitLabJobTraceEndpoints {
    static func trace(
        at route: GitLabJobTraceRoute
    ) -> GitLabRawAPIRequest {
        .get(
            path: [
                "projects",
                String(route.projectID),
                "jobs",
                String(route.jobID),
                "trace",
            ]
        )
    }
}

extension GitLabPipelineStageRow {
    func jobTraceContext(
        projectID: Int
    ) -> GitLabJobTraceContext? {
        guard
            case let .job(job) = content,
            let route = GitLabJobTraceRoute(
                projectID: projectID,
                jobID: job.id
            )
        else {
            return nil
        }

        return GitLabJobTraceContext(
            route: route,
            jobName: job.name,
            status: job.status,
            archived: job.archived,
            erasedAt: job.erasedAt,
            webURL: job.safeWebURL
        )
    }
}
