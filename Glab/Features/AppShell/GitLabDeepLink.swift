import Foundation

nonisolated enum GitLabDeepLinkTarget:
    Equatable,
    Sendable
{
    case project(
        pathWithNamespace: String
    )
    case issue(
        pathWithNamespace: String,
        iid: Int
    )
    case mergeRequest(
        pathWithNamespace: String,
        iid: Int
    )
}

nonisolated enum GitLabDeepLinkParseResult:
    Equatable,
    Sendable
{
    case supported(
        GitLabDeepLinkTarget
    )
    case unsupported(URL)
    case untrusted
}

nonisolated enum GitLabDeepLinkParser {
    static func parse(
        _ url: URL,
        for gitLabHost: GitLabHost
    ) -> GitLabDeepLinkParseResult {
        guard
            let sourceComponents =
                secureComponents(for: url),
            let siteComponents =
                secureComponents(
                    for: gitLabHost.siteURL
                ),
            sameOrigin(
                sourceComponents,
                siteComponents
            ),
            let sourceSegments =
                decodedPathSegments(
                    sourceComponents
                        .percentEncodedPath
                ),
            let siteSegments =
                decodedPathSegments(
                    siteComponents
                        .percentEncodedPath
                ),
            sourceSegments.starts(
                with: siteSegments
            )
        else {
            return .untrusted
        }

        let routeSegments = Array(
            sourceSegments.dropFirst(
                siteSegments.count
            )
        )

        return parseRoute(
            routeSegments,
            sourceURL: url
        )
    }

    static func originMatches(
        _ url: URL,
        gitLabHost: GitLabHost
    ) -> Bool {
        guard
            let sourceComponents =
                secureComponents(for: url),
            let siteComponents =
                secureComponents(
                    for: gitLabHost.siteURL
                )
        else {
            return false
        }

        return sameOrigin(
            sourceComponents,
            siteComponents
        )
    }

    private static func parseRoute(
        _ segments: [String],
        sourceURL: URL
    ) -> GitLabDeepLinkParseResult {
        let markerIndices = segments.indices
            .filter {
                segments[$0] == "-"
            }

        guard
            let markerIndex =
                markerIndices.first
        else {
            guard segments.count >= 2 else {
                return .unsupported(
                    sourceURL
                )
            }

            return .supported(
                .project(
                    pathWithNamespace:
                        segments.joined(
                            separator: "/"
                        )
                )
            )
        }

        guard
            markerIndices.count == 1,
            markerIndex >= 2
        else {
            return .unsupported(sourceURL)
        }

        let resourceSegments = Array(
            segments[
                segments.index(
                    after: markerIndex
                )...
            ]
        )
        guard
            resourceSegments.count == 2,
            let iid = positiveIID(
                resourceSegments[1]
            )
        else {
            return .unsupported(sourceURL)
        }

        let projectPath = segments[
            ..<markerIndex
        ].joined(separator: "/")

        switch resourceSegments[0] {
        case "issues":
            return .supported(
                .issue(
                    pathWithNamespace:
                        projectPath,
                    iid: iid
                )
            )
        case "merge_requests":
            return .supported(
                .mergeRequest(
                    pathWithNamespace:
                        projectPath,
                    iid: iid
                )
            )
        default:
            return .unsupported(sourceURL)
        }
    }

    private static func secureComponents(
        for url: URL
    ) -> URLComponents? {
        guard
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            components.scheme?
                .lowercased() == "https",
            components.host != nil,
            components.user == nil,
            components.password == nil
        else {
            return nil
        }

        return components
    }

    private static func sameOrigin(
        _ lhs: URLComponents,
        _ rhs: URLComponents
    ) -> Bool {
        lhs.host?.caseInsensitiveCompare(
            rhs.host ?? ""
        ) == .orderedSame
            && effectiveHTTPSPort(lhs)
                == effectiveHTTPSPort(rhs)
    }

    private static func effectiveHTTPSPort(
        _ components: URLComponents
    ) -> Int {
        components.port ?? 443
    }

    private static func decodedPathSegments(
        _ percentEncodedPath: String
    ) -> [String]? {
        guard
            percentEncodedPath.isEmpty
                || percentEncodedPath
                    .hasPrefix("/"),
            let decodedPath =
                percentEncodedPath
                    .removingPercentEncoding
        else {
            return nil
        }

        var segments = decodedPath
            .split(
                separator: "/",
                omittingEmptySubsequences:
                    false
            )
            .map(String.init)

        if segments.first == "" {
            segments.removeFirst()
        }
        if segments.last == "" {
            segments.removeLast()
        }

        guard segments.allSatisfy(
            isSafePathSegment
        ) else {
            return nil
        }

        return segments
    }

    private static func isSafePathSegment(
        _ segment: String
    ) -> Bool {
        !segment.isEmpty
            && segment != "."
            && segment != ".."
            && !segment.contains("%")
            && !segment.contains("\\")
            && !segment.contains("?")
            && !segment.contains("#")
            && !segment.unicodeScalars
                .contains {
                    CharacterSet
                        .controlCharacters
                        .contains($0)
                }
    }

    private static func positiveIID(
        _ value: String
    ) -> Int? {
        guard
            value.first != "0",
            value.unicodeScalars
                .allSatisfy({
                    $0.value >= 48
                        && $0.value <= 57
                }),
            let iid = Int(value),
            iid > 0
        else {
            return nil
        }

        return iid
    }
}

nonisolated enum GitLabDeepLinkDecision:
    Equatable,
    Sendable
{
    case open(
        accountID: GitLabAccountID,
        target: GitLabDeepLinkTarget,
        sourceURL: URL
    )
    case confirmSwitch(
        accountID: GitLabAccountID,
        target: GitLabDeepLinkTarget,
        sourceURL: URL
    )
    case chooseAccount(
        accountIDs: [GitLabAccountID],
        target: GitLabDeepLinkTarget,
        sourceURL: URL
    )
    case signedOut(sourceURL: URL)
    case addAccount(sourceURL: URL)
    case browserFallback(sourceURL: URL)
    case rejected
}

nonisolated enum GitLabDeepLinkAccountMatcher {
    private struct Match {
        let accountID: GitLabAccountID
        let result: GitLabDeepLinkParseResult
        let sitePathDepth: Int
    }

    static func decision(
        for incomingURL: URL,
        accounts: [GitLabAccountID],
        activeAccountID: GitLabAccountID?
    ) -> GitLabDeepLinkDecision {
        guard
            let sourceURL =
                GitLabContentLink.targetURL(
                    from: incomingURL
                )
        else {
            return .rejected
        }

        guard !accounts.isEmpty else {
            return .signedOut(
                sourceURL: sourceURL
            )
        }

        let matches = accounts.compactMap {
            accountID -> Match? in
            let result =
                GitLabDeepLinkParser.parse(
                    sourceURL,
                    for: accountID.host
                )
            guard result != .untrusted else {
                return nil
            }

            return Match(
                accountID: accountID,
                result: result,
                sitePathDepth:
                    sitePathDepth(
                        accountID.host
                    )
            )
        }

        guard
            let mostSpecificDepth =
                matches.map(
                    \.sitePathDepth
                ).max()
        else {
            let hasMatchingOrigin =
                accounts.contains {
                    GitLabDeepLinkParser
                        .originMatches(
                            sourceURL,
                            gitLabHost: $0.host
                        )
                }
            return hasMatchingOrigin
                ? .rejected
                : .addAccount(
                    sourceURL: sourceURL
                )
        }

        let mostSpecificMatches =
            matches.filter {
                $0.sitePathDepth
                    == mostSpecificDepth
            }

        guard
            case let .supported(target) =
                mostSpecificMatches[0].result
        else {
            return .browserFallback(
                sourceURL: sourceURL
            )
        }

        let matchingAccountIDs =
            mostSpecificMatches.compactMap {
                match -> GitLabAccountID? in
                guard
                    match.result
                        == .supported(target)
                else {
                    return nil
                }
                return match.accountID
            }

        if
            let activeAccountID,
            matchingAccountIDs.contains(
                activeAccountID
            )
        {
            return .open(
                accountID: activeAccountID,
                target: target,
                sourceURL: sourceURL
            )
        }

        if matchingAccountIDs.count == 1 {
            return .confirmSwitch(
                accountID:
                    matchingAccountIDs[0],
                target: target,
                sourceURL: sourceURL
            )
        }

        return .chooseAccount(
            accountIDs:
                matchingAccountIDs,
            target: target,
            sourceURL: sourceURL
        )
    }

    private static func sitePathDepth(
        _ host: GitLabHost
    ) -> Int {
        host.siteURL.pathComponents
            .filter { $0 != "/" }
            .count
    }
}
