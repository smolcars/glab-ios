import Foundation

nonisolated enum GitLabMarkdownResourceID:
    Equatable,
    Hashable,
    Sendable
{
    case issue(projectID: Int, issueIID: Int)
    case issueNote(
        projectID: Int,
        issueIID: Int,
        noteID: Int
    )
    case mergeRequest(
        projectID: Int,
        mergeRequestIID: Int
    )
    case mergeRequestNote(
        projectID: Int,
        mergeRequestIID: Int,
        noteID: Int
    )
    case repositoryFile(
        projectID: Int,
        ref: String,
        path: String,
        blobID: String?
    )

    fileprivate var webPathSuffix: String {
        switch self {
        case let .issue(_, issueIID),
             let .issueNote(_, issueIID, _):
            "/-/issues/\(issueIID)"
        case let .mergeRequest(_, mergeRequestIID),
             let .mergeRequestNote(
                _,
                mergeRequestIID,
                _
             ):
            "/-/merge_requests/\(mergeRequestIID)"
        case let .repositoryFile(
            _,
            ref,
            path,
            _
        ):
            "/-/blob/\(ref)/\(path)"
        }
    }

    fileprivate var repositoryFileContext:
        (
            projectID: Int,
            ref: String
        )?
    {
        guard
            case let .repositoryFile(
                projectID,
                ref,
                _,
                _
            ) = self
        else {
            return nil
        }
        return (projectID, ref)
    }

    fileprivate var projectID: Int {
        switch self {
        case let .issue(projectID, _),
             let .issueNote(projectID, _, _),
             let .mergeRequest(projectID, _),
             let .mergeRequestNote(projectID, _, _),
             let .repositoryFile(projectID, _, _, _):
            projectID
        }
    }
}

nonisolated struct GitLabMarkdownRequest:
    Equatable,
    Hashable,
    Sendable
{
    let accountID: GitLabAccountID
    let resource: GitLabMarkdownResourceID
    let source: String
    let webURL: URL?
}

nonisolated struct GitLabMarkdownText:
    Equatable,
    Sendable
{
    let attributedString: AttributedString

    var plainText: String {
        String(attributedString.characters)
    }

    var links: [URL] {
        attributedString.runs.compactMap(\.link)
    }
}

nonisolated struct GitLabMarkdownRichText:
    Equatable,
    @unchecked Sendable
{
    // Keep the stored value immutable. The defensive copy prevents a mutable
    // attributed string from crossing the renderer actor boundary.
    let attributedString: NSAttributedString

    init(_ attributedString: NSAttributedString) {
        self.attributedString = NSAttributedString(
            attributedString: attributedString
        )
    }

    static func == (
        lhs: GitLabMarkdownRichText,
        rhs: GitLabMarkdownRichText
    ) -> Bool {
        lhs.attributedString.isEqual(
            to: rhs.attributedString
        )
    }

    var plainText: String {
        attributedString.string
    }

    var links: [URL] {
        var result: [URL] = []
        attributedString.enumerateAttribute(
            .link,
            in: NSRange(
                location: 0,
                length: attributedString.length
            )
        ) { value, _, _ in
            if let url = value as? URL {
                result.append(url)
            } else if
                let rawValue = value as? String,
                let url = URL(string: rawValue)
            {
                result.append(url)
            }
        }
        return result
    }
}

nonisolated struct GitLabMarkdownHeading:
    Equatable,
    Sendable
{
    let level: Int
    let content: GitLabMarkdownText

    var accessibilityLabel: String {
        "Heading level \(level), \(content.plainText)"
    }
}

nonisolated enum GitLabMarkdownListKind:
    Equatable,
    Sendable
{
    case ordered
    case unordered
}

nonisolated enum GitLabMarkdownTaskState:
    Equatable,
    Sendable
{
    case complete
    case incomplete
    case inapplicable

    var accessibilityTitle: String {
        switch self {
        case .complete:
            "Complete task"
        case .incomplete:
            "Incomplete task"
        case .inapplicable:
            "Inapplicable task"
        }
    }
}

nonisolated struct GitLabMarkdownListItem:
    Equatable,
    Sendable
{
    let ordinal: Int
    let taskState: GitLabMarkdownTaskState?
    let taskSourceID:
        GitLabMarkdownTaskSourceID?
    let blocks: [GitLabMarkdownBlock]

    var plainText: String {
        blocks.map(\.plainText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var accessibilityLabel: String {
        guard let taskState else {
            return plainText
        }
        return "\(taskState.accessibilityTitle), \(plainText)"
    }

    var taskControlText: String {
        blocks.lazy
            .compactMap(\.paragraph)
            .first?
            .plainText
            ?? ""
    }

    var indexedTask:
        GitLabMarkdownIndexedTask?
    {
        guard
            let taskState,
            let taskSourceID
        else {
            return nil
        }
        return GitLabMarkdownIndexedTask(
            sourceID: taskSourceID,
            state: taskState
        )
    }
}

nonisolated struct GitLabMarkdownList:
    Equatable,
    Sendable
{
    let kind: GitLabMarkdownListKind
    let items: [GitLabMarkdownListItem]
}

nonisolated struct GitLabMarkdownQuote:
    Equatable,
    Sendable
{
    let blocks: [GitLabMarkdownBlock]

    var plainText: String {
        blocks.map(\.plainText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }
}

nonisolated struct GitLabMarkdownCodeBlock:
    Equatable,
    Sendable
{
    let language: String?
    let text: String

    var accessibilityLabel: String {
        if let language, !language.isEmpty {
            return "\(language) code block"
        }
        return "Code block"
    }
}

nonisolated enum GitLabMarkdownTableAlignment:
    Equatable,
    Sendable
{
    case left
    case center
    case right
}

nonisolated struct GitLabMarkdownTable:
    Equatable,
    Sendable
{
    let alignments: [GitLabMarkdownTableAlignment]
    let header: [GitLabMarkdownText]
    let rows: [[GitLabMarkdownText]]
    let columnCharacterCounts: [Int]
}

nonisolated enum GitLabMarkdownMediaKind:
    Equatable,
    Sendable
{
    case image
    case video
    case audio

    init(url: URL) {
        let fileExtension = url.pathExtension.lowercased()
        if Self.videoFileExtensions.contains(fileExtension) {
            self = .video
        } else if Self.audioFileExtensions.contains(fileExtension) {
            self = .audio
        } else {
            self = .image
        }
    }

    func normalizedFileExtension(
        _ value: String?
    ) -> String? {
        guard let value else {
            return nil
        }
        let normalized = value.lowercased()
        let isAllowed = switch self {
        case .image:
            false
        case .video:
            Self.videoFileExtensions.contains(normalized)
        case .audio:
            Self.audioFileExtensions.contains(normalized)
        }
        return isAllowed ? normalized : nil
    }

    private static let videoFileExtensions = [
        "mp4", "m4v", "mov", "webm", "ogv",
    ]
    private static let audioFileExtensions = [
        "mp3", "oga", "ogg", "spx", "wav",
    ]
}

nonisolated struct GitLabMarkdownMediaDimension:
    Equatable,
    Sendable
{
    enum Unit: Equatable, Sendable {
        case pixels
        case percent
    }

    let value: Double
    let unit: Unit
}

nonisolated struct GitLabMarkdownMediaDimensions:
    Equatable,
    Sendable
{
    let width: GitLabMarkdownMediaDimension?
    let height: GitLabMarkdownMediaDimension?
}

nonisolated struct GitLabMarkdownImage:
    Equatable,
    Sendable
{
    let accountID: GitLabAccountID
    let url: URL
    let fallbackURLs: [URL]
    let altText: String
    let linkURL: URL?
    let browserURL: URL?
    let kind: GitLabMarkdownMediaKind
    let dimensions: GitLabMarkdownMediaDimensions?

    init(
        accountID: GitLabAccountID,
        url: URL,
        fallbackURLs: [URL] = [],
        altText: String,
        linkURL: URL? = nil,
        browserURL: URL? = nil,
        kind: GitLabMarkdownMediaKind? = nil,
        dimensions:
            GitLabMarkdownMediaDimensions? = nil
    ) {
        self.accountID = accountID
        self.url = url
        self.fallbackURLs = fallbackURLs
        self.altText = altText
        self.linkURL = linkURL
        self.browserURL = browserURL
        self.kind = kind ?? GitLabMarkdownMediaKind(
            url: url
        )
        self.dimensions = dimensions
    }

    var candidateURLs: [URL] {
        [url] + fallbackURLs.filter { $0 != url }
    }

    func applying(
        dimensions: GitLabMarkdownMediaDimensions
    ) -> Self {
        Self(
            accountID: accountID,
            url: url,
            fallbackURLs: fallbackURLs,
            altText: altText,
            linkURL: linkURL,
            browserURL: browserURL,
            kind: kind,
            dimensions: dimensions
        )
    }

    var accessibilityLabel: String {
        guard altText.isEmpty else {
            return altText
        }
        switch kind {
        case .image:
            return "Markdown image"
        case .video:
            return "Markdown video"
        case .audio:
            return "Markdown audio"
        }
    }
}

nonisolated enum GitLabMarkdownMediaAttributeParser {
    struct Result: Equatable, Sendable {
        let dimensions: GitLabMarkdownMediaDimensions
        let remainder: String
    }

    static func parsePrefix(
        in source: String
    ) -> Result? {
        guard
            source.first == "{",
            let closingIndex = source.firstIndex(of: "}")
        else {
            return nil
        }

        let attributes = source[
            source.index(after: source.startIndex)
                ..< closingIndex
        ]
        var width: GitLabMarkdownMediaDimension?
        var height: GitLabMarkdownMediaDimension?

        for token in attributes.split(
            whereSeparator: { $0.isWhitespace }
        ) {
            let components = token.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard components.count == 2 else {
                return nil
            }
            let name = components[0].lowercased()
            guard name == "width" || name == "height" else {
                return nil
            }
            guard
                let dimension = dimension(
                    from: String(components[1])
                )
            else {
                return nil
            }
            if name == "width" {
                width = dimension
            } else {
                height = dimension
            }
        }

        guard width != nil || height != nil else {
            return nil
        }
        return Result(
            dimensions: GitLabMarkdownMediaDimensions(
                width: width,
                height: height
            ),
            remainder: String(
                source[source.index(after: closingIndex)...]
            )
        )
    }

    private static func dimension(
        from source: String
    ) -> GitLabMarkdownMediaDimension? {
        let unit: GitLabMarkdownMediaDimension.Unit
        let number: Substring
        if source.hasSuffix("%") {
            unit = .percent
            number = source.dropLast()
        } else if source.lowercased().hasSuffix("px") {
            unit = .pixels
            number = source.dropLast(2)
        } else {
            unit = .pixels
            number = Substring(source)
        }
        guard
            let value = Double(number),
            value.isFinite,
            value > 0,
            unit != .percent || value <= 100
        else {
            return nil
        }
        return GitLabMarkdownMediaDimension(
            value: value,
            unit: unit
        )
    }
}

nonisolated enum GitLabMarkdownBlockAlignment:
    Equatable,
    Sendable
{
    case leading
    case center
}

nonisolated struct GitLabMarkdownImageGroup:
    Equatable,
    Sendable
{
    let images: [GitLabMarkdownImage]
    let alignment: GitLabMarkdownBlockAlignment
}

nonisolated enum GitLabMarkdownUnsupportedKind:
    Equatable,
    Sendable
{
    case diagram
    case math
    case multimedia
    case rawHTML
    case serverSpecific
}

nonisolated struct GitLabMarkdownUnsupported:
    Equatable,
    Sendable
{
    let kind: GitLabMarkdownUnsupportedKind
    let source: String

    var accessibilityLabel: String {
        "Unsupported GitLab formatting"
    }
}

nonisolated indirect enum GitLabMarkdownBlock:
    Equatable,
    Sendable
{
    case heading(GitLabMarkdownHeading)
    case paragraph(GitLabMarkdownText)
    case list(GitLabMarkdownList)
    case quote(GitLabMarkdownQuote)
    case code(GitLabMarkdownCodeBlock)
    case table(GitLabMarkdownTable)
    case image(GitLabMarkdownImage)
    case imageGroup(GitLabMarkdownImageGroup)
    case richText(GitLabMarkdownRichText)
    case thematicBreak
    case unsupported(GitLabMarkdownUnsupported)

    var heading: GitLabMarkdownHeading? {
        guard case let .heading(value) = self else {
            return nil
        }
        return value
    }

    var paragraph: GitLabMarkdownText? {
        guard case let .paragraph(value) = self else {
            return nil
        }
        return value
    }

    var list: GitLabMarkdownList? {
        guard case let .list(value) = self else {
            return nil
        }
        return value
    }

    var quote: GitLabMarkdownQuote? {
        guard case let .quote(value) = self else {
            return nil
        }
        return value
    }

    var code: GitLabMarkdownCodeBlock? {
        guard case let .code(value) = self else {
            return nil
        }
        return value
    }

    var table: GitLabMarkdownTable? {
        guard case let .table(value) = self else {
            return nil
        }
        return value
    }

    var image: GitLabMarkdownImage? {
        guard case let .image(value) = self else {
            return nil
        }
        return value
    }

    var imageGroup: GitLabMarkdownImageGroup? {
        guard case let .imageGroup(value) = self else {
            return nil
        }
        return value
    }

    var unsupported: GitLabMarkdownUnsupported? {
        guard case let .unsupported(value) = self else {
            return nil
        }
        return value
    }

    var plainText: String {
        switch self {
        case let .heading(value):
            value.content.plainText
        case let .paragraph(value):
            value.plainText
        case let .list(value):
            value.items.map(\.plainText)
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
        case let .quote(value):
            value.plainText
        case let .code(value):
            value.text
        case let .table(value):
            ([value.header] + value.rows)
                .map {
                    $0.map(\.plainText)
                        .joined(separator: " | ")
                }
                .joined(separator: "\n")
        case let .image(value):
            value.altText
        case let .imageGroup(value):
            value.images.map(\.altText)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case let .richText(value):
            value.plainText
        case .thematicBreak:
            ""
        case let .unsupported(value):
            value.source
        }
    }

    fileprivate var links: [URL] {
        switch self {
        case let .heading(value):
            value.content.links
        case let .paragraph(value):
            value.links
        case let .list(value):
            value.items.flatMap {
                $0.blocks.flatMap(\.links)
            }
        case let .quote(value):
            value.blocks.flatMap(\.links)
        case let .table(value):
            ([value.header] + value.rows)
                .flatMap { $0 }
                .flatMap(\.links)
        case .code, .thematicBreak, .unsupported:
            []
        case let .image(value):
            value.linkURL.map { [$0] } ?? []
        case let .imageGroup(value):
            value.images.compactMap(\.linkURL)
        case let .richText(value):
            value.links
        }
    }
}

nonisolated struct GitLabMarkdownDocument:
    Equatable,
    Sendable
{
    let blocks: [GitLabMarkdownBlock]
    let hasMappedMutableTask: Bool

    init(blocks: [GitLabMarkdownBlock]) {
        self.blocks = blocks
        hasMappedMutableTask =
            blocks.contains {
                $0.hasMappedMutableTask
            }
    }

    var plainText: String {
        blocks.map(\.plainText)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    var allLinks: [URL] {
        blocks.flatMap(\.links)
    }
}

private extension GitLabMarkdownBlock {
    nonisolated
    var hasMappedMutableTask: Bool {
        switch self {
        case let .list(list):
            list.items.contains {
                $0.hasMappedMutableTask
            }
        case let .quote(quote):
            quote.blocks.contains {
                $0.hasMappedMutableTask
            }
        case .heading,
             .paragraph,
             .code,
             .table,
             .image,
             .imageGroup,
             .richText,
             .thematicBreak,
             .unsupported:
            false
        }
    }
}

private extension GitLabMarkdownListItem {
    nonisolated
    var hasMappedMutableTask: Bool {
        if
            let indexedTask,
            indexedTask.state
                != .inapplicable
        {
            return true
        }
        return blocks.contains {
            $0.hasMappedMutableTask
        }
    }
}

nonisolated enum GitLabMarkdownParser {
    private static let commentExpression =
        try? NSRegularExpression(
            pattern: "<!--[\\s\\S]*?-->"
        )

    @concurrent
    static func parse(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        try Task.checkCancellation()
        async let indexedTasks =
            GitLabMarkdownTaskSourceIndex
                .tasks(in: request.source)
        let normalizedSource =
            GitLabMarkdownEscapedReference
            .protect(
                sourceWithoutComments(
                    request.source
                )
            )
        let parsed = try AttributedString(
            markdown: normalizedSource,
            options: .init(interpretedSyntax: .full)
        )
        try Task.checkCancellation()

        let context = GitLabMarkdownLinkContext(
            request: request
        )
        let root = GitLabMarkdownIntentNode.root()
        var fallbackIdentity = -1

        for (index, run) in parsed.runs.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let fragment = parsed[run.range]

            guard let intent = run.presentationIntent else {
                let node = GitLabMarkdownIntentNode(
                    identity: fallbackIdentity,
                    kind: nil
                )
                fallbackIdentity -= 1
                node.fragments.append(
                    .text(
                        AttributedString(
                            GitLabMarkdownEscapedReference
                                .restore(
                                    String(
                                        fragment.characters
                                    )
                                )
                        )
                    )
                )
                root.children.append(node)
                continue
            }

            var parent = root
            for component in intent.components.reversed() {
                parent = parent.child(
                    identity: component.identity,
                    kind: component.kind
                )
            }

            if let imageURL = run.imageURL {
                let altText =
                    GitLabMarkdownEscapedReference
                    .restore(
                        String(fragment.characters)
                    )
                parent.fragments.append(
                    .image(
                        rawURL: imageURL,
                        altText: altText
                    )
                )
            } else {
                parent.fragments.append(
                    GitLabMarkdownInlineProcessor.process(
                        fragment,
                        existingLink: run.link,
                        context: context
                    )
                )
            }
        }

        let blocks = try GitLabMarkdownTreeConverter
            .blocks(
                from: root.children,
                context: context
            )
        try Task.checkCancellation()
        return GitLabMarkdownTaskSourceMapper
            .attaching(
                try await indexedTasks,
                to:
                    GitLabMarkdownDocument(
                        blocks: blocks
                    )
            )
    }

    private static func sourceWithoutComments(
        _ source: String
    ) -> String {
        guard let commentExpression else {
            return source
        }

        return commentExpression.stringByReplacingMatches(
            in: source,
            range: NSRange(
                source.startIndex..<source.endIndex,
                in: source
            ),
            withTemplate: ""
        )
    }
}

nonisolated private enum GitLabMarkdownIntentFragment {
    case substring(AttributedSubstring)
    case text(AttributedString)
    case image(rawURL: URL, altText: String)
}

nonisolated private final class GitLabMarkdownIntentNode {
    let identity: Int
    let kind: PresentationIntent.Kind?
    var children: [GitLabMarkdownIntentNode] = []
    var fragments: [GitLabMarkdownIntentFragment] = []
    private var childrenByIdentity:
        [Int: GitLabMarkdownIntentNode] = [:]

    init(
        identity: Int,
        kind: PresentationIntent.Kind?
    ) {
        self.identity = identity
        self.kind = kind
    }

    static func root() -> GitLabMarkdownIntentNode {
        GitLabMarkdownIntentNode(
            identity: 0,
            kind: nil
        )
    }

    func child(
        identity: Int,
        kind: PresentationIntent.Kind
    ) -> GitLabMarkdownIntentNode {
        if let existing = childrenByIdentity[identity] {
            return existing
        }

        let child = GitLabMarkdownIntentNode(
            identity: identity,
            kind: kind
        )
        children.append(child)
        childrenByIdentity[identity] = child
        return child
    }
}

nonisolated private enum GitLabMarkdownTreeConverter {
    static func blocks(
        from nodes: [GitLabMarkdownIntentNode],
        context: GitLabMarkdownLinkContext
    ) throws -> [GitLabMarkdownBlock] {
        var result: [GitLabMarkdownBlock] = []

        for node in nodes {
            try Task.checkCancellation()
            result.append(
                contentsOf: try blocks(
                    from: node,
                    context: context
                )
            )
        }

        return result
    }

    private static func blocks(
        from node: GitLabMarkdownIntentNode,
        context: GitLabMarkdownLinkContext
    ) throws -> [GitLabMarkdownBlock] {
        guard let kind = node.kind else {
            let source = text(from: node.fragments)
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            guard !source.isEmpty else {
                return []
            }
            return [
                .unsupported(
                    GitLabMarkdownUnsupported(
                        kind: .rawHTML,
                        source: source
                    )
                ),
            ]
        }

        switch kind {
        case let .header(level):
            return textBlocks(
                from: node.fragments,
                context: context
            ) {
                .heading(
                    GitLabMarkdownHeading(
                        level: level,
                        content: $0
                    )
                )
            }
        case .paragraph:
            return textBlocks(
                from: node.fragments,
                context: context
            ) {
                .paragraph($0)
            }
        case .orderedList:
            return [
                .list(
                    try list(
                        from: node,
                        kind: .ordered,
                        context: context
                    )
                ),
            ]
        case .unorderedList:
            return [
                .list(
                    try list(
                        from: node,
                        kind: .unordered,
                        context: context
                    )
                ),
            ]
        case .blockQuote:
            return [
                .quote(
                    GitLabMarkdownQuote(
                        blocks: try blocks(
                            from: node.children,
                            context: context
                        )
                    )
                ),
            ]
        case let .codeBlock(languageHint):
            let code = text(from: node.fragments)
            if let unsupportedKind = unsupportedKind(
                for: languageHint
            ) {
                return [
                    .unsupported(
                        GitLabMarkdownUnsupported(
                            kind: unsupportedKind,
                            source: code
                        )
                    ),
                ]
            }
            return [
                .code(
                    GitLabMarkdownCodeBlock(
                        language: languageHint,
                        text: code
                    )
                ),
            ]
        case let .table(columns):
            return [
                .table(
                    table(
                        from: node,
                        columns: columns
                    )
                ),
            ]
        case .thematicBreak:
            return [.thematicBreak]
        case .listItem,
             .tableHeaderRow,
             .tableRow,
             .tableCell:
            return try blocks(
                from: node.children,
                context: context
            )
        @unknown default:
            return [
                .unsupported(
                    GitLabMarkdownUnsupported(
                        kind: .serverSpecific,
                        source: text(from: node.fragments)
                    )
                ),
            ]
        }
    }

    private static func textBlocks(
        from fragments: [GitLabMarkdownIntentFragment],
        context: GitLabMarkdownLinkContext,
        makeTextBlock: (GitLabMarkdownText) -> GitLabMarkdownBlock
    ) -> [GitLabMarkdownBlock] {
        var result: [GitLabMarkdownBlock] = []
        var text = AttributedString()

        func appendText(
            _ value: AttributedString
        ) {
            let source = String(value.characters)
            if
                case let .image(image)? = result.last,
                let attributes =
                    GitLabMarkdownMediaAttributeParser
                    .parsePrefix(in: source)
            {
                result[result.count - 1] = .image(
                    image.applying(
                        dimensions: attributes.dimensions
                    )
                )
                if !attributes.remainder.isEmpty {
                    text.append(
                        AttributedString(
                            attributes.remainder
                        )
                    )
                }
                return
            }
            text.append(value)
        }

        func flushText() {
            guard !text.characters.isEmpty else {
                return
            }
            result.append(
                makeTextBlock(
                    GitLabMarkdownText(
                        attributedString:
                            inlineText(text)
                    )
                )
            )
            text = AttributedString()
        }

        for fragment in fragments {
            switch fragment {
            case let .substring(value):
                appendText(AttributedString(value))
            case let .text(value):
                appendText(value)
            case let .image(rawURL, altText):
                flushText()
                let urls = context.resolveImageCandidates(
                    rawURL
                )
                if let url = urls.first {
                    result.append(
                        .image(
                            GitLabMarkdownImage(
                                accountID:
                                    context.accountID,
                                url: url,
                                fallbackURLs:
                                    Array(urls.dropFirst()),
                                altText: altText,
                                browserURL:
                                    context.resolveImageBrowserURL(
                                        rawURL
                                    ),
                                kind:
                                    GitLabMarkdownMediaKind(
                                        url: rawURL
                                    )
                            )
                        )
                    )
                } else if !altText.isEmpty {
                    result.append(
                        makeTextBlock(
                            GitLabMarkdownText(
                                attributedString:
                                    AttributedString(altText)
                            )
                        )
                    )
                }
            }
        }

        flushText()
        return result
    }

    private static func list(
        from node: GitLabMarkdownIntentNode,
        kind: GitLabMarkdownListKind,
        context: GitLabMarkdownLinkContext
    ) throws -> GitLabMarkdownList {
        let items = try node.children.compactMap {
            child -> GitLabMarkdownListItem? in
            guard case let .listItem(ordinal) = child.kind else {
                return nil
            }

            var itemBlocks = try blocks(
                from: child.children,
                context: context
            )
            let taskState = removeTaskMarker(
                from: &itemBlocks
            )
            return GitLabMarkdownListItem(
                ordinal: ordinal,
                taskState: taskState,
                taskSourceID: nil,
                blocks: itemBlocks
            )
        }

        return GitLabMarkdownList(
            kind: kind,
            items: items
        )
    }

    private static func removeTaskMarker(
        from blocks: inout [GitLabMarkdownBlock]
    ) -> GitLabMarkdownTaskState? {
        guard
            let index = blocks.firstIndex(
                where: { $0.paragraph != nil }
            ),
            let paragraph = blocks[index].paragraph,
            let marker = taskMarker(
                in: paragraph.plainText
            )
        else {
            return nil
        }

        var attributedString =
            paragraph.attributedString
        let endIndex = attributedString.characters.index(
            attributedString.startIndex,
            offsetBy: marker.characterCount
        )
        attributedString.removeSubrange(
            attributedString.startIndex..<endIndex
        )
        blocks[index] = .paragraph(
            GitLabMarkdownText(
                attributedString: attributedString
            )
        )
        return marker.state
    }

    private static func taskMarker(
        in text: String
    ) -> (
        state: GitLabMarkdownTaskState,
        characterCount: Int
    )? {
        let lowercased = text.lowercased()
        let state: GitLabMarkdownTaskState

        if lowercased.hasPrefix("[x]") {
            state = .complete
        } else if lowercased.hasPrefix("[ ]") {
            state = .incomplete
        } else if lowercased.hasPrefix("[~]") {
            state = .inapplicable
        } else {
            return nil
        }

        let whitespaceCount = text
            .dropFirst(3)
            .prefix { $0.isWhitespace }
            .count
        return (
            state,
            3 + whitespaceCount
        )
    }

    private static func table(
        from node: GitLabMarkdownIntentNode,
        columns: [PresentationIntent.TableColumn]
    ) -> GitLabMarkdownTable {
        var header: [GitLabMarkdownText] = []
        var rows: [[GitLabMarkdownText]] = []

        for row in node.children {
            let cells = row.children.map {
                GitLabMarkdownText(
                    attributedString:
                        attributedText(from: $0.fragments)
                )
            }

            switch row.kind {
            case .tableHeaderRow:
                header = cells
            case .tableRow:
                rows.append(cells)
            default:
                continue
            }
        }

        return GitLabMarkdownTable(
            alignments: columns.map {
                switch $0.alignment {
                case .left:
                    .left
                case .center:
                    .center
                case .right:
                    .right
                @unknown default:
                    .left
                }
            },
            header: header,
            rows: rows,
            columnCharacterCounts:
                columnCharacterCounts(
                    header: header,
                    rows: rows,
                    columnCount: columns.count
                )
        )
    }

    private static func columnCharacterCounts(
        header: [GitLabMarkdownText],
        rows: [[GitLabMarkdownText]],
        columnCount: Int
    ) -> [Int] {
        (0..<columnCount).map { columnIndex in
            ([header] + rows)
                .compactMap { row in
                    guard row.indices.contains(columnIndex) else {
                        return nil
                    }
                    return row[columnIndex]
                        .plainText.count
                }
                .max()
                ?? 0
        }
    }

    private static func unsupportedKind(
        for languageHint: String?
    ) -> GitLabMarkdownUnsupportedKind? {
        switch languageHint?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
        {
        case "mermaid", "plantuml", "kroki":
            .diagram
        case "math", "latex":
            .math
        case "video", "audio":
            .multimedia
        default:
            nil
        }
    }

    private static func text(
        from fragments: [GitLabMarkdownIntentFragment]
    ) -> String {
        String(
            attributedText(from: fragments).characters
        )
    }

    private static func attributedText(
        from fragments: [GitLabMarkdownIntentFragment]
    ) -> AttributedString {
        var result = AttributedString()
        for fragment in fragments {
            switch fragment {
            case let .substring(value):
                result.append(value)
            case let .text(value):
                result.append(value)
            case let .image(_, altText):
                result.append(AttributedString(altText))
            }
        }
        return inlineText(result)
    }

    private static func inlineText(
        _ source: AttributedString
    ) -> AttributedString {
        var result = source
        result.presentationIntent = nil
        result.imageURL = nil
        result.alternateDescription = nil
        return result
    }
}

nonisolated struct GitLabMarkdownLinkContext {
    let accountID: GitLabAccountID
    let resource: GitLabMarkdownResourceID
    let resourceURL: URL?
    let projectURL: URL?

    init(request: GitLabMarkdownRequest) {
        accountID = request.accountID
        resource = request.resource
        resourceURL = Self.validatedResourceURL(
            request.webURL,
            accountID: request.accountID,
            resource: request.resource
        )
        projectURL = resourceURL.flatMap {
            Self.projectURL(
                from: $0,
                resource: request.resource
            )
        }
    }

    func resolve(_ url: URL) -> URL? {
        let rawValue = url.relativeString
        guard
            !rawValue.isEmpty,
            !rawValue.hasPrefix("//")
        else {
            return nil
        }

        if url.scheme != nil {
            return GitLabWebURL.validated(url)
        }

        guard let resourceURL else {
            return nil
        }

        if rawValue.hasPrefix("#") {
            guard
                var components = URLComponents(
                    url: resourceURL,
                    resolvingAgainstBaseURL: false
                ),
                let relativeComponents =
                    URLComponents(string: rawValue)
            else {
                return nil
            }
            components.fragment =
                relativeComponents.fragment
            return GitLabWebURL.validated(
                components.url
            )
        }

        if rawValue.hasPrefix("/") {
            return resolveRootRelative(rawValue)
        }

        guard
            let baseURL = relativeBaseURL,
            let resolved = URL(
                string: rawValue,
                relativeTo: baseURL
            )?.absoluteURL,
            Self.matchesAccountOrigin(
                resolved,
                accountID: accountID
            ),
            isAllowedRepositoryRelativeURL(
                resolved
            )
        else {
            return nil
        }

        return GitLabWebURL.validated(resolved)
    }

    func resolveImage(_ url: URL) -> URL? {
        resolveImageCandidates(url).first
    }

    func resolveImageCandidates(
        _ url: URL
    ) -> [URL] {
        let rawValue = url.relativeString
        if
            url.scheme == nil,
            rawValue.hasPrefix("/uploads/"),
            let uploadURLs = projectUploadURLs(
                rawValue
            ),
            !uploadURLs.isEmpty
        {
            return uploadURLs
        }
        guard
            resource.repositoryFileContext != nil,
            url.scheme == nil,
            !rawValue.hasPrefix("/"),
            !rawValue.hasPrefix("#"),
            let resolved = resolve(url)
        else {
            return resolve(url).map { [$0] } ?? []
        }

        return repositoryRawFileURL(
            from: resolved
        ).map { [$0] } ?? []
    }

    func resolveImageBrowserURL(
        _ url: URL
    ) -> URL? {
        let rawValue = url.relativeString
        if
            url.scheme == nil,
            rawValue.hasPrefix("/uploads/")
        {
            return projectUploadWebURLs(rawValue)?.first
        }
        return resolve(url)
    }

    func referenceURL(
        marker: Character,
        value: String
    ) -> URL? {
        switch marker {
        case "#":
            projectURL?
                .appendingPathComponent("-")
                .appendingPathComponent("issues")
                .appendingPathComponent(value)
        case "!":
            projectURL?
                .appendingPathComponent("-")
                .appendingPathComponent("merge_requests")
                .appendingPathComponent(value)
        case "@":
            accountID.host.siteURL
                .appendingPathComponent(value)
        default:
            nil
        }
    }

    private func resolveRootRelative(
        _ rawValue: String
    ) -> URL? {
        guard
            let relativeComponents =
                URLComponents(string: rawValue),
            var baseComponents = URLComponents(
                url: accountID.host.siteURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }

        let sitePath =
            baseComponents.percentEncodedPath
        let relativePath =
            relativeComponents.percentEncodedPath
        baseComponents.percentEncodedPath =
            sitePath + relativePath
        baseComponents.query =
            relativeComponents.query
        baseComponents.fragment =
            relativeComponents.fragment
        return GitLabWebURL.validated(
            baseComponents.url
        )
    }

    private func projectUploadURLs(
        _ rawValue: String
    ) -> [URL]? {
        guard
            let webURLs = projectUploadWebURLs(rawValue),
            let relativeComponents = URLComponents(
                string: rawValue
            ),
            let decodedPath = relativeComponents
                .percentEncodedPath
                .removingPercentEncoding
        else {
            return nil
        }

        let pathSegments = decodedPath.split(
            separator: "/",
            omittingEmptySubsequences: true
        )
        guard
            pathSegments.count == 3,
            pathSegments.first == "uploads",
            var apiComponents = URLComponents(
                url: accountID.host.apiBaseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return webURLs
        }

        apiComponents.percentEncodedPath +=
            "/projects/\(resource.projectID)"
            + relativeComponents.percentEncodedPath
        apiComponents.query = relativeComponents.query
        apiComponents.fragment = relativeComponents.fragment

        guard
            let apiURL = GitLabWebURL.validated(
                apiComponents.url
            )
        else {
            return webURLs
        }
        return [apiURL] + webURLs
    }

    private func projectUploadWebURLs(
        _ rawValue: String
    ) -> [URL]? {
        guard
            let relativeComponents = URLComponents(
                string: rawValue
            ),
            let decodedPath = relativeComponents
                .percentEncodedPath
                .removingPercentEncoding,
            Self.hasSafePathSegments(decodedPath)
        else {
            return nil
        }

        let modernBase = accountID.host.siteURL
            .appendingPathComponent("-")
            .appendingPathComponent("project")
            .appendingPathComponent(
                String(resource.projectID)
            )
        let bases = [modernBase]
            + (projectURL.map { [$0] } ?? [])
        let candidates = bases
            .compactMap { base -> URL? in
                guard
                    var components = URLComponents(
                        url: base,
                        resolvingAgainstBaseURL: false
                    )
                else {
                    return nil
                }
                components.percentEncodedPath +=
                    relativeComponents.percentEncodedPath
                components.query =
                    relativeComponents.query
                components.fragment =
                    relativeComponents.fragment
                return GitLabWebURL.validated(
                    components.url
                )
            }
        return candidates.reduce(into: []) {
            result, candidate in
            if !result.contains(candidate) {
                result.append(candidate)
            }
        }
    }

    private var relativeBaseURL: URL? {
        guard let resourceURL else {
            return nil
        }
        if resource.repositoryFileContext != nil {
            return resourceURL
                .deletingLastPathComponent()
                .appendingPathComponent("")
        }
        return projectURL?
            .appendingPathComponent("")
    }

    private func isAllowedRepositoryRelativeURL(
        _ url: URL
    ) -> Bool {
        guard
            let context =
                resource.repositoryFileContext,
            let projectURL,
            let resolvedPath = Self.decodedPath(
                of: url
            ),
            let projectPath = Self.decodedPath(
                of: projectURL
            )
        else {
            return resource.repositoryFileContext
                == nil
        }

        let blobPrefix = projectPath
            + "/-/blob/"
            + context.ref
            + "/"
        guard resolvedPath.hasPrefix(blobPrefix) else {
            return false
        }
        return Self.hasSafePathSegments(
            String(
                resolvedPath.dropFirst(
                    blobPrefix.count
                )
            )
        )
    }

    private func repositoryRawFileURL(
        from blobURL: URL
    ) -> URL? {
        guard
            let context =
                resource.repositoryFileContext,
            let projectURL,
            let blobPath = Self.decodedPath(
                of: blobURL
            ),
            let projectPath = Self.decodedPath(
                of: projectURL
            )
        else {
            return nil
        }

        let blobPrefix = projectPath
            + "/-/blob/"
            + context.ref
            + "/"
        guard blobPath.hasPrefix(blobPrefix) else {
            return nil
        }

        let path = String(
            blobPath.dropFirst(blobPrefix.count)
        )
        guard
            !path.isEmpty,
            Self.hasSafePathSegments(path),
            let encodedPath = path.addingPercentEncoding(
                withAllowedCharacters:
                    Self.pathComponentAllowedCharacters
            ),
            var components = URLComponents(
                url: accountID.host.apiBaseURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return nil
        }

        components.percentEncodedPath +=
            "/projects/\(context.projectID)"
            + "/repository/files/\(encodedPath)/raw"
        components.queryItems = [
            URLQueryItem(
                name: "ref",
                value: context.ref
            ),
        ]
        return GitLabWebURL.validated(
            components.url
        )
    }

    private static func validatedResourceURL(
        _ url: URL?,
        accountID: GitLabAccountID,
        resource: GitLabMarkdownResourceID
    ) -> URL? {
        guard
            let url = GitLabWebURL.validated(url),
            matchesAccountOrigin(
                url,
                accountID: accountID
            ),
            let components = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let decodedPath =
                components.percentEncodedPath
                    .removingPercentEncoding,
            decodedPath.hasSuffix(
                resource.webPathSuffix
            ),
            decodedPath.hasPrefix(
                accountID.host.siteURL.path
            )
        else {
            return nil
        }

        return url
    }

    private static func projectURL(
        from resourceURL: URL,
        resource: GitLabMarkdownResourceID
    ) -> URL? {
        guard
            var components = URLComponents(
                url: resourceURL,
                resolvingAgainstBaseURL: false
            ),
            let decodedPath =
                components.percentEncodedPath
                    .removingPercentEncoding,
            decodedPath.hasSuffix(
                resource.webPathSuffix
            )
        else {
            return nil
        }

        let projectPath = String(
            decodedPath.dropLast(
                resource.webPathSuffix.count
            )
        )
        components.path = projectPath
        components.query = nil
        components.fragment = nil
        return GitLabWebURL.validated(
            components.url
        )
    }

    private static func matchesAccountOrigin(
        _ url: URL,
        accountID: GitLabAccountID
    ) -> Bool {
        guard
            let urlComponents = URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            ),
            let hostComponents = URLComponents(
                url: accountID.host.siteURL,
                resolvingAgainstBaseURL: false
            )
        else {
            return false
        }

        return
            urlComponents.scheme?.lowercased() == "https"
            && urlComponents.host?.lowercased()
                == hostComponents.host?.lowercased()
            && effectivePort(urlComponents)
                == effectivePort(hostComponents)
    }

    private static func decodedPath(
        of url: URL
    ) -> String? {
        URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        )?
        .percentEncodedPath
        .removingPercentEncoding
    }

    private static func hasSafePathSegments(
        _ path: String
    ) -> Bool {
        !path.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).contains {
            $0 == "." || $0 == ".."
        }
    }

    private static func effectivePort(
        _ components: URLComponents
    ) -> Int {
        components.port ?? 443
    }

    private static let pathComponentAllowedCharacters =
        CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/?#%")
        )
}

nonisolated private enum GitLabMarkdownInlineProcessor {
    private static let referenceExpression =
        try? NSRegularExpression(
            pattern:
                GitLabUserReferenceSyntax
                    .leadingBoundaryPattern
                + "(#([1-9][0-9]*)"
                + "|!([1-9][0-9]*)"
                + "|@("
                + GitLabUserReferenceSyntax
                    .usernamePattern
                + "))"
        )

    static func process(
        _ source: AttributedSubstring,
        existingLink: URL?,
        context: GitLabMarkdownLinkContext
    ) -> GitLabMarkdownIntentFragment {
        if let existingLink {
            var value = AttributedString(source)
            value.link = context.resolve(existingLink)
            return .text(
                restoreProtectedReferences(
                    in: value
                )
            )
        }

        let containsProtectedReference =
            source.characters.contains {
                $0 == "\u{E000}"
                    || $0 == "\u{E001}"
                    || $0 == "\u{E002}"
            }
        if
            source.runs.contains(where: {
                $0.inlinePresentationIntent?
                    .contains(.code) == true
            })
        {
            return containsProtectedReference
                ? .text(
                    restoreProtectedReferences(
                        in: AttributedString(source)
                    )
                )
                : .substring(source)
        }

        guard
            source.characters.contains(where: {
                $0 == "#" || $0 == "!" || $0 == "@"
            })
        else {
            return containsProtectedReference
                ? .text(
                    restoreProtectedReferences(
                        in: AttributedString(source)
                    )
                )
                : .substring(source)
        }

        let text = String(source.characters)
        return .text(
            restoreProtectedReferences(
                in: linkReferences(
                    in: AttributedString(source),
                    text: text,
                    context: context
                )
            )
        )
    }

    private static func linkReferences(
        in source: AttributedString,
        text: String,
        context: GitLabMarkdownLinkContext
    ) -> AttributedString {
        guard let referenceExpression else {
            return source
        }

        let matches = referenceExpression.matches(
            in: text,
            range: NSRange(
                text.startIndex..<text.endIndex,
                in: text
            )
        )
        guard !matches.isEmpty else {
            return source
        }

        let attributes =
            source.runs.first?.attributes
            ?? AttributeContainer()
        var result = AttributedString()
        var cursor = text.startIndex

        for match in matches {
            guard
                let matchRange = Range(
                    match.range,
                    in: text
                )
            else {
                continue
            }

            if cursor < matchRange.lowerBound {
                result.append(
                    AttributedString(
                        String(
                            text[
                                cursor
                                    ..< matchRange.lowerBound
                            ]
                        ),
                        attributes: attributes
                    )
                )
            }

            let matchedText = String(
                text[matchRange]
            )
            var linked = AttributedString(
                matchedText,
                attributes: attributes
            )
            if
                let marker = matchedText.first,
                let url = context.referenceURL(
                    marker: marker,
                    value: String(
                        matchedText.dropFirst()
                    )
                )
            {
                linked.link = url
            }
            result.append(linked)
            cursor = matchRange.upperBound
        }

        if cursor < text.endIndex {
            result.append(
                AttributedString(
                    String(text[cursor...]),
                    attributes: attributes
                )
            )
        }
        return result
    }

    private static func restoreProtectedReferences(
        in source: AttributedString
    ) -> AttributedString {
        let text = String(source.characters)
        guard
            text.contains("\u{E000}")
                || text.contains("\u{E001}")
                || text.contains("\u{E002}")
        else {
            return source
        }

        var result = AttributedString()

        for run in source.runs {
            result.append(
                AttributedString(
                    GitLabMarkdownEscapedReference
                        .restore(
                            String(
                                source.characters[
                                    run.range
                                ]
                            )
                        ),
                    attributes: run.attributes
                )
            )
        }
        return result
    }
}

nonisolated private enum GitLabMarkdownEscapedReference {
    private static let issuePlaceholder =
        "\u{E000}"
    private static let mergeRequestPlaceholder =
        "\u{E001}"
    private static let userPlaceholder =
        "\u{E002}"

    static func protect(_ source: String) -> String {
        source
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
            .reduce(
                into: (lines: [String](), isInFence: false)
            ) { state, line in
                let value = String(line)
                let trimmed = value.trimmingCharacters(
                    in: .whitespaces
                )
                let isFence =
                    trimmed.hasPrefix("```")
                    || trimmed.hasPrefix("~~~")

                if isFence {
                    state.lines.append(value)
                    state.isInFence.toggle()
                } else if state.isInFence {
                    state.lines.append(value)
                } else {
                    state.lines.append(
                        protectInline(value)
                    )
                }
            }
            .lines
            .joined(separator: "\n")
    }

    static func restore(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: issuePlaceholder,
                with: "#"
            )
            .replacingOccurrences(
                of: mergeRequestPlaceholder,
                with: "!"
            )
            .replacingOccurrences(
                of: userPlaceholder,
                with: "@"
            )
    }

    private static func protectInline(
        _ source: String
    ) -> String {
        var result = ""
        var index = source.startIndex
        var isInCode = false

        while index < source.endIndex {
            let character = source[index]
            if character == "`" {
                isInCode.toggle()
                result.append(character)
                index = source.index(after: index)
                continue
            }

            let nextIndex = source.index(
                after: index
            )
            if
                !isInCode,
                character == "\\",
                nextIndex < source.endIndex
            {
                let next = source[nextIndex]
                let placeholder: String? = switch next {
                case "#":
                    issuePlaceholder
                case "!":
                    mergeRequestPlaceholder
                case "@":
                    userPlaceholder
                default:
                    nil
                }
                if let placeholder {
                    result += placeholder
                    index = source.index(
                        after: nextIndex
                    )
                    continue
                }
            }

            result.append(character)
            index = nextIndex
        }
        return result
    }
}
