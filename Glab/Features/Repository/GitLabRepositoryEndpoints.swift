import Foundation

nonisolated enum GitLabRepositoryEndpoints {
    static let treePageSize = 100
    static let branchPageSize = 100
    static let searchPageSize = 20

    static func tree(
        projectID: Int,
        ref: String,
        path: String
    ) -> GitLabAPIRequest<
        [GitLabRepositoryEntry]
    > {
        var query = [
            URLQueryItem(
                name: "ref",
                value: ref
            ),
            URLQueryItem(
                name: "per_page",
                value: String(treePageSize)
            ),
        ]
        if !path.isEmpty {
            query.insert(
                URLQueryItem(
                    name: "path",
                    value: path
                ),
                at: 0
            )
        }

        return .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "repository",
                "tree",
            ],
            query: query
        )
    }

    static func branches(
        projectID: Int,
        search: String? = nil
    ) -> GitLabAPIRequest<
        [GitLabRepositoryBranch]
    > {
        var query = [
            URLQueryItem(
                name: "per_page",
                value: String(branchPageSize)
            ),
        ]
        if
            let search = search?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                ),
            !search.isEmpty
        {
            query.insert(
                URLQueryItem(
                    name: "search",
                    value: search
                ),
                at: 0
            )
        }

        return .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "repository",
                "branches",
            ],
            query: query
        )
    }

    static func search(
        projectID: Int,
        ref: String,
        query search: String
    ) -> GitLabAPIRequest<
        [GitLabRepositorySearchResult]
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "search",
            ],
            query: [
                URLQueryItem(
                    name: "scope",
                    value: "blobs"
                ),
                URLQueryItem(
                    name: "search",
                    value: search
                ),
                URLQueryItem(
                    name: "ref",
                    value: ref
                ),
                URLQueryItem(
                    name: "per_page",
                    value: String(searchPageSize)
                ),
            ]
        )
    }

    static func rawFile(
        at route: GitLabRepositoryFileRoute
    ) -> GitLabRawAPIRequest {
        .get(
            path: [
                "projects",
                String(route.projectID),
                "repository",
                "files",
                route.path,
                "raw",
            ],
            query: [
                URLQueryItem(
                    name: "ref",
                    value: route.ref
                ),
            ]
        )
    }
}
