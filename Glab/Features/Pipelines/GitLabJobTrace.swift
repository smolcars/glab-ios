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
