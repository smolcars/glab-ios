import CoreGraphics
import CoreText
import Foundation

nonisolated protocol GitLabMarkdownBadgeLoading:
    Sendable
{
    func image(
        for url: URL,
        targetPixelWidth: Int
    ) async throws -> GitLabMarkdownDecodedImage?
}

nonisolated struct UnavailableGitLabMarkdownBadgeLoader:
    GitLabMarkdownBadgeLoading
{
    func image(
        for url: URL,
        targetPixelWidth: Int
    ) async throws -> GitLabMarkdownDecodedImage? {
        nil
    }
}

nonisolated struct LiveGitLabMarkdownBadgeLoader:
    GitLabMarkdownBadgeLoading
{
    private let host: GitLabHost
    private let client:
        any GitLabSessionRequestSending

    init(
        host: GitLabHost,
        client: any GitLabSessionRequestSending
    ) {
        self.host = host
        self.client = client
    }

    func image(
        for url: URL,
        targetPixelWidth: Int
    ) async throws -> GitLabMarkdownDecodedImage? {
        guard
            let route = GitLabMarkdownBadgeRoute(
                url: url,
                siteURL: host.siteURL
            )
        else {
            return nil
        }

        let project = try await client.send(
            GitLabMarkdownBadgeEndpoints.project(
                pathWithNamespace:
                    route.projectPath
            )
        )
        let value = try await badgeValue(
            for: route,
            projectID: project.id
        )
        return try GitLabMarkdownBadgeRenderer
            .render(
                value,
                targetPixelWidth:
                    targetPixelWidth
            )
    }

    private func badgeValue(
        for route: GitLabMarkdownBadgeRoute,
        projectID: Int
    ) async throws -> GitLabMarkdownBadgeValue {
        switch route.kind {
        case let .pipeline(ref):
            let pipeline = try await client.send(
                GitLabMarkdownBadgeEndpoints
                    .latestPipeline(
                        projectID: projectID,
                        ref: ref
                    )
            )
            return .pipeline(
                status: pipeline.status
            )
        case let .coverage(ref):
            let pipeline = try await client.send(
                GitLabMarkdownBadgeEndpoints
                    .latestPipeline(
                        projectID: projectID,
                        ref: ref
                    )
            )
            return .coverage(
                value: pipeline.coverage,
                limits: route.coverageLimits,
                keyText: route.keyText
            )
        case .release:
            do {
                let release = try await client.send(
                    GitLabMarkdownBadgeEndpoints
                        .latestRelease(
                            projectID: projectID
                        )
                )
                return .release(
                    tag: release.tagName,
                    keyText: route.keyText
                )
            } catch let error {
                if error == .api(.notFound) {
                    return .release(
                        tag: nil,
                        keyText: route.keyText
                    )
                }
                throw error
            }
        }
    }
}

nonisolated struct GitLabMarkdownBadgeRoute:
    Equatable,
    Sendable
{
    enum Kind: Equatable, Sendable {
        case pipeline(ref: String)
        case coverage(ref: String)
        case release
    }

    let projectPath: String
    let kind: Kind
    let keyText: String?
    let coverageLimits:
        GitLabMarkdownCoverageLimits

    init?(url: URL, siteURL: URL) {
        guard
            Self.matchesOrigin(
                url,
                siteURL: siteURL
            ),
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }

        let siteComponents = siteURL
            .pathComponents
            .filter { $0 != "/" }
        var pathComponents = url
            .pathComponents
            .filter { $0 != "/" }
        guard
            pathComponents.starts(
                with: siteComponents
            )
        else {
            return nil
        }
        pathComponents.removeFirst(
            siteComponents.count
        )

        var query: [String: String] = [:]
        for item in components.queryItems ?? [] {
            guard let value = item.value else {
                continue
            }
            query[item.name.lowercased()] = value
        }
        keyText = Self.nonempty(
            query["key_text"]
        )
        coverageLimits =
            GitLabMarkdownCoverageLimits(
                query: query
            )

        if
            pathComponents.count >= 4,
            pathComponents[
                pathComponents.count - 3
            ] == "-",
            pathComponents[
                pathComponents.count - 2
            ] == "badges",
            pathComponents.last == "release.svg"
        {
            let project = pathComponents
                .dropLast(3)
            guard !project.isEmpty else {
                return nil
            }
            projectPath = project.joined(
                separator: "/"
            )
            kind = .release
            return
        }

        guard
            let badgesIndex = pathComponents
                .lastIndex(of: "badges"),
            badgesIndex > 0,
            badgesIndex
                < pathComponents.count - 2,
            let filename = pathComponents.last
        else {
            return nil
        }
        let project = pathComponents[..<badgesIndex]
        let ref = pathComponents[
            (badgesIndex + 1)..<(pathComponents.count - 1)
        ]
        .joined(separator: "/")
        guard
            !project.isEmpty,
            !ref.isEmpty
        else {
            return nil
        }
        projectPath = project.joined(
            separator: "/"
        )
        switch filename {
        case "pipeline.svg":
            kind = .pipeline(ref: ref)
        case "coverage.svg":
            kind = .coverage(ref: ref)
        default:
            return nil
        }
    }

    private static func matchesOrigin(
        _ url: URL,
        siteURL: URL
    ) -> Bool {
        guard
            let candidate = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let expected = URLComponents(
                url: siteURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return false
        }
        return
            candidate.scheme?.lowercased()
                == "https"
            && candidate.host?.lowercased()
                == expected.host?.lowercased()
            && (candidate.port ?? 443)
                == (expected.port ?? 443)
    }

    private static func nonempty(
        _ value: String?
    ) -> String? {
        let normalized = value?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return normalized?.isEmpty == false
            ? normalized
            : nil
    }
}

nonisolated struct GitLabMarkdownCoverageLimits:
    Equatable,
    Sendable
{
    let good: Double
    let acceptable: Double
    let medium: Double

    init(
        good: Double = 95,
        acceptable: Double = 90,
        medium: Double = 75
    ) {
        self.good = good
        self.acceptable = acceptable
        self.medium = medium
    }

    init(query: [String: String]) {
        let good = Self.bounded(
            query["min_good"],
            fallback: 95
        )
        let acceptable = min(
            Self.bounded(
                query["min_acceptable"],
                fallback: 90
            ),
            good
        )
        let medium = min(
            Self.bounded(
                query["min_medium"],
                fallback: 75
            ),
            acceptable
        )
        self.init(
            good: good,
            acceptable: acceptable,
            medium: medium
        )
    }

    private static func bounded(
        _ value: String?,
        fallback: Double
    ) -> Double {
        guard let parsed = value.flatMap(Double.init) else {
            return fallback
        }
        return min(max(parsed, 1), 100)
    }
}

nonisolated enum GitLabMarkdownBadgeValue:
    Equatable,
    Sendable
{
    case pipeline(status: GitLabCIStatus)
    case coverage(
        value: String?,
        limits: GitLabMarkdownCoverageLimits,
        keyText: String?
    )
    case release(tag: String?, keyText: String?)
}

nonisolated enum GitLabMarkdownBadgeEndpoints {
    static func project(
        pathWithNamespace: String
    ) -> GitLabAPIRequest<
        GitLabMarkdownBadgeProject
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                pathWithNamespace,
            ]
        )
    }

    static func latestPipeline(
        projectID: Int,
        ref: String
    ) -> GitLabAPIRequest<
        GitLabMarkdownBadgePipeline
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "pipelines",
                "latest",
            ],
            query: [
                .init(name: "ref", value: ref),
            ]
        )
    }

    static func latestRelease(
        projectID: Int
    ) -> GitLabAPIRequest<
        GitLabMarkdownBadgeRelease
    > {
        .get(
            requires: .read,
            path: [
                "projects",
                String(projectID),
                "releases",
                "permalink",
                "latest",
            ]
        )
    }
}

nonisolated struct GitLabMarkdownBadgeProject:
    Decodable,
    Equatable,
    Sendable
{
    let id: Int
}

nonisolated struct GitLabMarkdownBadgePipeline:
    Decodable,
    Equatable,
    Sendable
{
    let status: GitLabCIStatus
    let coverage: String?
}

nonisolated struct GitLabMarkdownBadgeRelease:
    Decodable,
    Equatable,
    Sendable
{
    let tagName: String?

    private enum CodingKeys:
        String,
        CodingKey
    {
        case tagName = "tag_name"
    }
}

nonisolated enum GitLabMarkdownBadgeRenderer {
    private struct Content {
        let key: String
        let value: String
        let valueColor: CGColor
    }

    static func render(
        _ value: GitLabMarkdownBadgeValue,
        targetPixelWidth: Int
    ) throws -> GitLabMarkdownDecodedImage {
        let content = content(for: value)
        let scale: CGFloat = targetPixelWidth >= 256
            ? 3
            : 2
        let font = CTFontCreateWithName(
            "Helvetica-Bold" as CFString,
            11 * scale,
            nil
        )
        let keyLine = line(
            content.key,
            font: font
        )
        let valueLine = line(
            content.value,
            font: font
        )
        let padding = 6 * scale
        let keyWidth = max(
            1,
            ceil(
                CGFloat(
                    CTLineGetTypographicBounds(
                        keyLine,
                        nil,
                        nil,
                        nil
                    )
                )
                + padding * 2
            )
        )
        let valueWidth = max(
            1,
            ceil(
                CGFloat(
                    CTLineGetTypographicBounds(
                        valueLine,
                        nil,
                        nil,
                        nil
                    )
                )
                + padding * 2
            )
        )
        let width = Int(keyWidth + valueWidth)
        let height = Int(20 * scale)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo:
                    CGImageAlphaInfo
                    .premultipliedLast
                    .rawValue
            )
        else {
            throw GitLabMarkdownImageError
                .invalidImage
        }

        let bounds = CGRect(
            x: 0,
            y: 0,
            width: width,
            height: height
        )
        context.saveGState()
        context.addPath(
            CGPath(
                roundedRect: bounds,
                cornerWidth: 3 * scale,
                cornerHeight: 3 * scale,
                transform: nil
            )
        )
        context.clip()
        context.setFillColor(
            color(0x555555)
        )
        context.fill(
            CGRect(
                x: 0,
                y: 0,
                width: keyWidth,
                height: CGFloat(height)
            )
        )
        context.setFillColor(
            content.valueColor
        )
        context.fill(
            CGRect(
                x: keyWidth,
                y: 0,
                width: valueWidth,
                height: CGFloat(height)
            )
        )
        context.restoreGState()

        draw(
            keyLine,
            centeredIn: CGRect(
                x: 0,
                y: 0,
                width: keyWidth,
                height: CGFloat(height)
            ),
            context: context
        )
        draw(
            valueLine,
            centeredIn: CGRect(
                x: keyWidth,
                y: 0,
                width: valueWidth,
                height: CGFloat(height)
            ),
            context: context
        )
        guard let image = context.makeImage() else {
            throw GitLabMarkdownImageError
                .invalidImage
        }
        return GitLabMarkdownDecodedImage(
            cgImage: image
        )
    }

    private static func content(
        for value: GitLabMarkdownBadgeValue
    ) -> Content {
        switch value {
        case let .pipeline(status):
            return Content(
                key: "pipeline",
                value: status.title.lowercased(),
                valueColor:
                    statusColor(status)
            )
        case let .coverage(
            value,
            limits,
            keyText
        ):
            guard
                let value,
                let coverage = Double(value)
            else {
                return Content(
                    key: keyText ?? "coverage",
                    value: "unknown",
                    valueColor: color(0x9F9F9F)
                )
            }
            let renderedValue = value
                .hasSuffix("%")
                ? value
                : value + "%"
            let valueColor: CGColor
            if coverage >= limits.good {
                valueColor = color(0x44CC11)
            } else if coverage >= limits.acceptable {
                valueColor = color(0xA3C51C)
            } else if coverage >= limits.medium {
                valueColor = color(0xDFB317)
            } else {
                valueColor = color(0xE05D44)
            }
            return Content(
                key: keyText ?? "coverage",
                value: renderedValue,
                valueColor: valueColor
            )
        case let .release(tag, keyText):
            return Content(
                key: keyText ?? "Latest Release",
                value: tag ?? "none",
                valueColor: tag == nil
                    ? color(0xE05D44)
                    : color(0x007EC6)
            )
        }
    }

    private static func statusColor(
        _ status: GitLabCIStatus
    ) -> CGColor {
        switch status.rawValue {
        case "success":
            color(0x44CC11)
        case "failed":
            color(0xE05D44)
        case "pending", "manual", "scheduled":
            color(0xDFB317)
        case "running":
            color(0x007EC6)
        default:
            color(0x9F9F9F)
        }
    }

    private static func line(
        _ text: String,
        font: CTFont
    ) -> CTLine {
        CTLineCreateWithAttributedString(
            NSAttributedString(
                string: text,
                attributes: [
                    .font: font,
                    .foregroundColor:
                        CGColor(
                            red: 1,
                            green: 1,
                            blue: 1,
                            alpha: 1
                        ),
                ]
            )
        )
    }

    private static func draw(
        _ line: CTLine,
        centeredIn rect: CGRect,
        context: CGContext
    ) {
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        let width = CGFloat(
            CTLineGetTypographicBounds(
                line,
                &ascent,
                &descent,
                nil
            )
        )
        context.textPosition = CGPoint(
            x: rect.minX
                + (rect.width - width) / 2,
            y: rect.minY
                + (rect.height - ascent - descent) / 2
                + descent
        )
        CTLineDraw(line, context)
    }

    private static func color(
        _ rgb: UInt32
    ) -> CGColor {
        CGColor(
            red: CGFloat((rgb >> 16) & 0xFF)
                / 255,
            green: CGFloat((rgb >> 8) & 0xFF)
                / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}
