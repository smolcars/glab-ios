import Foundation

nonisolated enum GitLabHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

nonisolated enum GitLabAPIRequestAccess:
    Equatable,
    Sendable
{
    case read
    case write
}

nonisolated enum GitLabAPIRequestTarget:
    Equatable,
    Sendable
{
    case restV4
    case graphQL
}

nonisolated struct GitLabAPIRequest<Response>: Sendable where Response: Decodable & Sendable {
    let target: GitLabAPIRequestTarget
    let method: GitLabHTTPMethod
    let requiredAccess: GitLabAPIRequestAccess
    let pathComponents: [String]
    let queryItems: [URLQueryItem]
    let body: Data?
    let cacheVariant: String?

    static func get(
        requires access: GitLabAPIRequestAccess,
        path: [String],
        query: [URLQueryItem] = [],
        cacheVariant: String? = nil
    ) -> Self {
        Self(
            target: .restV4,
            method: .get,
            requiredAccess: access,
            pathComponents: path,
            queryItems: query,
            body: nil,
            cacheVariant: cacheVariant
        )
    }

    static func post(
        requires access: GitLabAPIRequestAccess,
        path: [String],
        query: [URLQueryItem] = []
    ) -> Self {
        Self(
            target: .restV4,
            method: .post,
            requiredAccess: access,
            pathComponents: path,
            queryItems: query,
            body: nil,
            cacheVariant: nil
        )
    }

    static func post<Body: Encodable & Sendable>(
        requires access: GitLabAPIRequestAccess,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) throws -> Self {
        return Self(
            target: .restV4,
            method: .post,
            requiredAccess: access,
            pathComponents: path,
            queryItems: query,
            body: try encodeJSONBody(body),
            cacheVariant: nil
        )
    }

    static func put(
        path: [String],
        query: [URLQueryItem] = []
    ) -> Self {
        Self(
            target: .restV4,
            method: .put,
            requiredAccess: .write,
            pathComponents: path,
            queryItems: query,
            body: nil,
            cacheVariant: nil
        )
    }

    static func put<Body: Encodable & Sendable>(
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) throws -> Self {
        Self(
            target: .restV4,
            method: .put,
            requiredAccess: .write,
            pathComponents: path,
            queryItems: query,
            body: try encodeJSONBody(body),
            cacheVariant: nil
        )
    }

    static func graphQL<Body: Encodable & Sendable>(
        requires access: GitLabAPIRequestAccess,
        body: Body
    ) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        return Self(
            target: .graphQL,
            method: .post,
            requiredAccess: access,
            pathComponents: [],
            queryItems: [],
            body: try encoder.encode(body),
            cacheVariant: nil
        )
    }

    static func delete(
        requires access: GitLabAPIRequestAccess,
        path: [String],
        query: [URLQueryItem] = []
    ) -> Self {
        Self(
            target: .restV4,
            method: .delete,
            requiredAccess: access,
            pathComponents: path,
            queryItems: query,
            body: nil,
            cacheVariant: nil
        )
    }

    private static func encodeJSONBody<
        Body: Encodable & Sendable
    >(
        _ body: Body
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(body)
    }
}

nonisolated struct GitLabRawAPIRequest:
    Equatable,
    Sendable
{
    let requiredAccess: GitLabAPIRequestAccess
    let pathComponents: [String]
    let queryItems: [URLQueryItem]

    static func get(
        path: [String],
        query: [URLQueryItem] = []
    ) -> Self {
        Self(
            requiredAccess: .read,
            pathComponents: path,
            queryItems: query
        )
    }
}

nonisolated enum GitLabAPIPageRequest<Response>: Sendable
where Response: Decodable & Sendable {
    case initial(GitLabAPIRequest<Response>)
    case next(URL)

    var requiredAccess: GitLabAPIRequestAccess {
        switch self {
        case let .initial(request):
            request.requiredAccess
        case .next:
            .read
        }
    }
}

nonisolated enum GitLabRequestConstructionError: Error, Equatable, Sendable, CustomStringConvertible {
    case emptyPathComponent
    case invalidPathComponent(String)
    case invalidURL
    case untrustedPaginationURL

    var description: String {
        switch self {
        case .emptyPathComponent:
            "GitLab API paths cannot contain an empty component."
        case let .invalidPathComponent(component):
            "The GitLab API path component could not be encoded: \(component)"
        case .invalidURL:
            "The GitLab API request URL could not be constructed."
        case .untrustedPaginationURL:
            "GitLab returned an untrusted pagination URL."
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
        let baseURL = switch endpoint.target {
        case .restV4:
            host.apiBaseURL
        case .graphQL:
            host.graphQLURL
        }
        guard var components = URLComponents(
            url: baseURL,
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

    func build(
        _ endpoint: GitLabRawAPIRequest
    ) throws(GitLabRequestConstructionError)
        -> URLRequest
    {
        let jsonRequest =
            GitLabAPIRequest<
                GitLabEmptyResponse
            >
            .get(
                requires:
                    endpoint.requiredAccess,
                path:
                    endpoint.pathComponents,
                query:
                    endpoint.queryItems
            )
        var request = try build(jsonRequest)
        request.setValue(
            "text/plain, application/octet-stream, */*",
            forHTTPHeaderField: "Accept"
        )
        return request
    }

    func build<Response>(
        _ page: GitLabAPIPageRequest<Response>
    ) throws(GitLabRequestConstructionError) -> URLRequest {
        switch page {
        case let .initial(endpoint):
            try build(endpoint)
        case let .next(url):
            try buildPaginationRequest(url)
        }
    }

    private func buildPaginationRequest(
        _ url: URL
    ) throws(GitLabRequestConstructionError) -> URLRequest {
        guard isTrustedPaginationURL(url) else {
            throw .untrustedPaginationURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = GitLabHTTPMethod.get.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        authorization.apply(to: &request)
        return request
    }

    private func isTrustedPaginationURL(_ url: URL) -> Bool {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let baseComponents = URLComponents(
                url: host.apiBaseURL,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?.lowercased() == "https",
            components.host?.lowercased()
                == baseComponents.host?.lowercased(),
            effectivePort(in: components)
                == effectivePort(in: baseComponents),
            components.user == nil,
            components.password == nil,
            components.fragment == nil,
            let path = components.percentEncodedPath.removingPercentEncoding,
            let basePath =
                baseComponents.percentEncodedPath.removingPercentEncoding,
            path == basePath || path.hasPrefix("\(basePath)/"),
            !path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0 == "." || $0 == ".." })
        else {
            return false
        }

        return true
    }

    private func effectivePort(
        in components: URLComponents
    ) -> Int? {
        components.port
            ?? (components.scheme?.lowercased() == "https" ? 443 : nil)
    }

    private static let pathComponentAllowedCharacters = CharacterSet.urlPathAllowed
        .subtracting(CharacterSet(charactersIn: "/?#%"))
}
