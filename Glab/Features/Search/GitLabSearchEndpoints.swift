import Foundation

nonisolated enum GitLabSearchEndpoints {
    static func search(
        scope: GitLabSearchScope,
        query: String
    ) -> GitLabAPIRequest<[GitLabSearchResult]> {
        .get(
            requires: .read,
            path: ["search"],
            query: [
                URLQueryItem(
                    name: "scope",
                    value: scope.apiValue
                ),
                URLQueryItem(
                    name: "search",
                    value: query
                ),
                URLQueryItem(
                    name: "search_type",
                    value: "basic"
                ),
                URLQueryItem(
                    name: "per_page",
                    value: "20"
                ),
            ]
        )
    }
}
