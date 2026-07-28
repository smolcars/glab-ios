import Foundation

nonisolated enum GitLabHostError: Error, Equatable, Sendable, CustomStringConvertible {
    case empty
    case invalidURL
    case missingHost
    case unsupportedScheme(String)
    case credentialsNotAllowed
    case queryOrFragmentNotAllowed

    var description: String {
        switch self {
        case .empty:
            "The GitLab host is empty."
        case .invalidURL:
            "The GitLab host is not a valid URL."
        case .missingHost:
            "The GitLab URL does not include a host."
        case let .unsupportedScheme(scheme):
            "GitLab hosts must use HTTPS, not \(scheme)."
        case .credentialsNotAllowed:
            "Credentials cannot be included in a GitLab host URL."
        case .queryOrFragmentNotAllowed:
            "A GitLab host URL cannot include a query or fragment."
        }
    }
}

nonisolated struct GitLabHost: Codable, Equatable, Sendable {
    let siteURL: URL
    let apiBaseURL: URL
    let graphQLURL: URL

    init(_ input: String) throws(GitLabHostError) {
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            throw .empty
        }

        let inputWithScheme = if trimmedInput.contains("://") {
            trimmedInput
        } else {
            "https://\(trimmedInput)"
        }

        guard var components = URLComponents(string: inputWithScheme) else {
            throw .invalidURL
        }

        let scheme = components.scheme?.lowercased() ?? ""
        guard scheme == "https" else {
            throw .unsupportedScheme(scheme)
        }
        guard let host = components.host, !host.isEmpty else {
            throw .missingHost
        }
        guard components.user == nil, components.password == nil else {
            throw .credentialsNotAllowed
        }
        guard components.query == nil, components.fragment == nil else {
            throw .queryOrFragmentNotAllowed
        }

        components.scheme = "https"
        components.percentEncodedPath = Self.normalizedSitePath(components.percentEncodedPath)
        let sitePath =
            components.percentEncodedPath

        guard let siteURL = components.url else {
            throw .invalidURL
        }

        components.percentEncodedPath =
            sitePath + "/api/v4"
        guard let apiBaseURL = components.url else {
            throw .invalidURL
        }

        components.percentEncodedPath =
            sitePath + "/api/graphql"
        guard let graphQLURL = components.url else {
            throw .invalidURL
        }

        self.siteURL = siteURL
        self.apiBaseURL = apiBaseURL
        self.graphQLURL = graphQLURL
    }

    private static func normalizedSitePath(_ path: String) -> String {
        var components = path.split(separator: "/", omittingEmptySubsequences: true)

        if
            components.count >= 2,
            components[components.count - 2] == "api",
            components[components.count - 1] == "v4"
        {
            components.removeLast(2)
        }

        return components.isEmpty ? "" : "/" + components.joined(separator: "/")
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)

        do {
            try self.init(value)
        } catch {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: error.description
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(siteURL.absoluteString)
    }
}
