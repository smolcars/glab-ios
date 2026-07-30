import Foundation

nonisolated enum GitLabCommitEndpoints {
    static func commits(
        projectID: Int,
        refName: String?
    ) -> GitLabAPIRequest<[GitLabCommit]> {
        var query = [
            URLQueryItem(
                name: "per_page",
                value: "20"
            ),
        ]
        if
            let refName =
                refName?.trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !refName.isEmpty
        {
            query.append(
                URLQueryItem(
                    name: "ref_name",
                    value: refName
                )
            )
        }

        return .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "repository",
                "commits",
            ],
            query: query
        )
    }

    static func diff(
        projectID: Int,
        commitSHA: String
    ) -> GitLabAPIRequest<[GitLabDiffFile]> {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "repository",
                "commits",
                commitSHA,
                "diff",
            ]
        )
    }
}
