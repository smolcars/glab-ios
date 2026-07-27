import Foundation

nonisolated enum GitLabHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
}

nonisolated struct GitLabAPIRequest<Response>: Sendable where Response: Decodable & Sendable {
    let method: GitLabHTTPMethod
    let pathComponents: [String]
    let queryItems: [URLQueryItem]
    let body: Data?

    static func get(
        path: [String],
        query: [URLQueryItem] = []
    ) -> Self {
        Self(
            method: .get,
            pathComponents: path,
            queryItems: query,
            body: nil
        )
    }

    static func post(
        path: [String],
        query: [URLQueryItem] = []
    ) -> Self {
        Self(
            method: .post,
            pathComponents: path,
            queryItems: query,
            body: nil
        )
    }

    static func post<Body: Encodable & Sendable>(
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) throws -> Self {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]

        return Self(
            method: .post,
            pathComponents: path,
            queryItems: query,
            body: try encoder.encode(body)
        )
    }
}

nonisolated enum GitLabRequestConstructionError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyPathComponent
    case invalidPathComponent(String)
    case invalidURL

    var description: String {
        switch self {
        case .emptyPathComponent:
            "GitLab API paths cannot contain an empty component."
        case let .invalidPathComponent(component):
            "The GitLab API path component could not be encoded: \(component)"
        case .invalidURL:
            "The GitLab API request URL could not be constructed."
        }
    }
}

nonisolated struct GitLabRequestBuilder: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    let host: GitLabHost
    private let authorization: GitLabAuthorization

    init(host: GitLabHost, authorization: GitLabAuthorization) {
        self.host = host
        self.authorization = authorization
    }

    var description: String {
        "GitLabRequestBuilder(host: \(host.siteURL.absoluteString), authorization: \(authorization))"
    }

    var debugDescription: String {
        description
    }

    func build<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) throws(GitLabRequestConstructionError) -> URLRequest {
        guard var components = URLComponents(
            url: host.apiBaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw .invalidURL
        }

        for pathComponent in endpoint.pathComponents {
            guard !pathComponent.isEmpty else {
                throw .emptyPathComponent
            }
            guard let encodedComponent = pathComponent.addingPercentEncoding(
                withAllowedCharacters: Self.pathComponentAllowedCharacters
            ) else {
                throw .invalidPathComponent(pathComponent)
            }

            components.percentEncodedPath += "/\(encodedComponent)"
        }

        components.queryItems = endpoint.queryItems.isEmpty ? nil : endpoint.queryItems

        guard let url = components.url else {
            throw .invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        authorization.apply(to: &request)
        return request
    }

    private static let pathComponentAllowedCharacters = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/?#%"))
}
