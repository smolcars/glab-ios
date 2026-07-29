import Foundation

nonisolated enum GitLabHTTPFileRedirectError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case unsafeDestination
    case redirectLoop
    case tooManyRedirects

    var errorDescription: String? {
        switch self {
        case .unsafeDestination:
            "The download redirect was not safe."
        case .redirectLoop:
            "The download entered a redirect loop."
        case .tooManyRedirects:
            "The download exceeded the redirect limit."
        }
    }
}

nonisolated struct GitLabHTTPFileRedirectState:
    Equatable,
    Sendable
{
    let redirectCount: Int
    let canForwardCredentials: Bool
    fileprivate let visitedDestinations:
        Set<String>
}

nonisolated struct GitLabHTTPFileRedirectDecision:
    Sendable
{
    let request: URLRequest
    let state: GitLabHTTPFileRedirectState
}

nonisolated struct GitLabHTTPFileRedirectPolicy:
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    private static let maximumRedirectCount = 5
    private static let sensitiveHeaderNames = [
        "Authorization",
        "PRIVATE-TOKEN",
        "JOB-TOKEN",
        "Sudo",
        "Cookie",
        "Proxy-Authorization",
    ]

    let initialState:
        GitLabHTTPFileRedirectState

    private let originalOrigin:
        Origin
    private let originalSensitiveHeaders:
        [String: String]

    var description: String {
        "GitLabHTTPFileRedirectPolicy("
        + "credentials: redacted)"
    }

    var debugDescription: String {
        description
    }

    init(initialRequest: URLRequest) throws {
        let destination = try Self.destination(
            from: initialRequest
        )
        originalOrigin = destination.origin
        initialState =
            GitLabHTTPFileRedirectState(
                redirectCount: 0,
                canForwardCredentials: true,
                visitedDestinations: [
                    destination.identity
                ]
            )
        originalSensitiveHeaders =
            Dictionary(
                uniqueKeysWithValues:
                    Self.sensitiveHeaderNames
                    .compactMap { name in
                        initialRequest.value(
                            forHTTPHeaderField:
                                name
                        )
                        .map { (name, $0) }
                    }
            )
    }

    func redirect(
        _ proposedRequest: URLRequest,
        from state:
            GitLabHTTPFileRedirectState
    ) throws -> GitLabHTTPFileRedirectDecision {
        guard
            state.redirectCount
                < Self.maximumRedirectCount
        else {
            throw GitLabHTTPFileRedirectError
                .tooManyRedirects
        }

        let destination = try Self.destination(
            from: proposedRequest
        )
        guard
            !state.visitedDestinations
                .contains(destination.identity)
        else {
            throw GitLabHTTPFileRedirectError
                .redirectLoop
        }

        let canForwardCredentials =
            state.canForwardCredentials
            && destination.origin
                == originalOrigin
        var request = proposedRequest
        Self.removeSensitiveHeaders(
            from: &request
        )
        if canForwardCredentials {
            for
                (
                    name,
                    value
                ) in originalSensitiveHeaders
            {
                request.setValue(
                    value,
                    forHTTPHeaderField: name
                )
            }
        }

        var visited =
            state.visitedDestinations
        visited.insert(destination.identity)
        return GitLabHTTPFileRedirectDecision(
            request: request,
            state:
                GitLabHTTPFileRedirectState(
                    redirectCount:
                        state.redirectCount + 1,
                    canForwardCredentials:
                        canForwardCredentials,
                    visitedDestinations:
                        visited
                )
        )
    }

    private static func destination(
        from request: URLRequest
    ) throws -> Destination {
        guard
            let url = request.url,
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?
                .lowercased() == "https",
            let host = components.host?
                .lowercased(),
            !host.isEmpty,
            components.user == nil,
            components.password == nil,
            components.fragment == nil
        else {
            throw GitLabHTTPFileRedirectError
                .unsafeDestination
        }

        let port = components.port ?? 443
        let query = components
            .percentEncodedQuery
            .map { "?\($0)" } ?? ""
        return Destination(
            origin:
                Origin(
                    host: host,
                    port: port
                ),
            identity:
                "https://\(host):\(port)"
                + components.percentEncodedPath
                + query
        )
    }

    private static func removeSensitiveHeaders(
        from request: inout URLRequest
    ) {
        let sensitiveNames =
            Set(
                sensitiveHeaderNames.map {
                    $0.lowercased()
                }
            )
        let existingNames =
            request.allHTTPHeaderFields?
            .keys
            .map(\.self) ?? []
        for name in existingNames
        where
            sensitiveNames.contains(
                name.lowercased()
            )
        {
            request.setValue(
                nil,
                forHTTPHeaderField: name
            )
        }
        for name in sensitiveHeaderNames {
            request.setValue(
                nil,
                forHTTPHeaderField: name
            )
        }
    }
}

private extension GitLabHTTPFileRedirectPolicy {
    nonisolated struct Origin:
        Equatable,
        Sendable
    {
        let host: String
        let port: Int
    }

    nonisolated struct Destination:
        Sendable
    {
        let origin: Origin
        let identity: String
    }
}
