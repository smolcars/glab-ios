import Foundation

nonisolated enum GitLabContentLink {
    static func targetURL(
        from incomingURL: URL
    ) -> URL? {
        guard
            let components = URLComponents(
                url: incomingURL,
                resolvingAgainstBaseURL: false
            ),
            let scheme =
                components.scheme?.lowercased()
        else {
            return nil
        }

        if scheme == "https" {
            return GitLabWebURL.validated(
                incomingURL
            )
        }

        guard
            scheme == "glab",
            components.host?
                .lowercased() == "open",
            components.port == nil,
            components.user == nil,
            components.password == nil,
            components.percentEncodedPath.isEmpty,
            components.fragment == nil,
            let queryItems =
                components.queryItems,
            queryItems.count == 1,
            queryItems[0].name == "url",
            let targetValue =
                queryItems[0].value,
            let targetURL = URL(
                string: targetValue
            )
        else {
            return nil
        }

        return GitLabWebURL.validated(
            targetURL
        )
    }
}
