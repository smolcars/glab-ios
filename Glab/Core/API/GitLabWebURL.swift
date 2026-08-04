import Foundation

nonisolated enum GitLabWebURL {
    static func validated(
        _ url: URL?
    ) -> URL? {
        guard
            let url,
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?.lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil
        else {
            return nil
        }

        return url
    }

    static func projectURL(
        from resourceURL: URL?,
        matchingPathSuffixes:
            [String]
    ) -> URL? {
        guard
            let resourceURL = validated(
                resourceURL
            ),
            var components = URLComponents(
                url: resourceURL,
                resolvingAgainstBaseURL: false
            ),
            let decodedPath =
                components.percentEncodedPath
                    .removingPercentEncoding,
            let suffix =
                matchingPathSuffixes.first(
                    where:
                        decodedPath.hasSuffix
                )
        else {
            return nil
        }

        components.path = String(
            decodedPath.dropLast(
                suffix.count
            )
        )
        components.query = nil
        components.fragment = nil
        return validated(components.url)
    }
}
