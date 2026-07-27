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
}
