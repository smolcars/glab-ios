import Foundation
import MarkdownKit
import UIKit

nonisolated enum GitLabReadOnlyMarkdownParser {
    @concurrent
    static func parse(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        try Task.checkCancellation()
        let parsed = ExtendedMarkdownParser.standard
            .parse(request.source)
        let context = GitLabMarkdownLinkContext(
            request: request
        )
        let blocks = try GitLabReadOnlyMarkdownConverter
            .blocks(
                from: parsed,
                context: context
            )
        try Task.checkCancellation()
        return GitLabMarkdownDocument(
            blocks: blocks
        )
    }
}

nonisolated private enum GitLabReadOnlyMarkdownConverter {
    private struct ConversionState {
        var centeredContainerDepth = 0

        var alignment: GitLabMarkdownBlockAlignment {
            centeredContainerDepth > 0
                ? .center
                : .leading
        }
    }

    private enum InlineComponent {
        case text(AttributedString)
        case image(GitLabMarkdownImage)
    }

    static func blocks(
        from document: Block,
        context: GitLabMarkdownLinkContext
    ) throws -> [GitLabMarkdownBlock] {
        var state = ConversionState()
        return try blocks(
            from: document,
            context: context,
            state: &state
        )
    }

    private static func blocks(
        from block: Block,
        context: GitLabMarkdownLinkContext,
        state: inout ConversionState
    ) throws -> [GitLabMarkdownBlock] {
        try Task.checkCancellation()

        switch block {
        case let .document(children):
            return try blocks(
                from: children,
                context: context,
                state: &state
            )
        case let .blockquote(children):
            var nestedState = state
            return [
                .quote(
                    GitLabMarkdownQuote(
                        blocks: try blocks(
                            from: children,
                            context: context,
                            state: &nestedState
                        )
                    )
                ),
            ]
        case let .list(start, _, children):
            return [
                .list(
                    try list(
                        start: start,
                        children: children,
                        context: context,
                        state: state
                    )
                ),
            ]
        case let .listItem(_, _, children):
            return try blocks(
                from: children,
                context: context,
                state: &state
            )
        case let .paragraph(text):
            return textBlocks(
                from: text,
                context: context,
                alignment: state.alignment
            ) {
                .paragraph($0)
            }
        case let .heading(level, text):
            return textBlocks(
                from: text,
                context: context,
                alignment: state.alignment
            ) {
                .heading(
                    GitLabMarkdownHeading(
                        level: level,
                        content: $0
                    )
                )
            }
        case let .indentedCode(lines):
            return [
                .code(
                    GitLabMarkdownCodeBlock(
                        language: nil,
                        text: joinedCode(lines)
                    )
                ),
            ]
        case let .fencedCode(language, lines):
            return [
                .code(
                    GitLabMarkdownCodeBlock(
                        language: language,
                        text: joinedCode(lines)
                    )
                ),
            ]
        case let .htmlBlock(lines):
            return htmlBlocks(
                source: lines.map(String.init)
                    .joined(separator: "\n"),
                context: context,
                state: &state
            )
        case .referenceDef:
            return []
        case .thematicBreak:
            return [.thematicBreak]
        case let .table(header, alignments, rows):
            return [
                .table(
                    table(
                        header: header,
                        alignments: alignments,
                        rows: rows,
                        context: context
                    )
                ),
            ]
        case let .definitionList(definitions):
            var result: [GitLabMarkdownBlock] = []
            for definition in definitions {
                result.append(
                    .heading(
                        GitLabMarkdownHeading(
                            level: 5,
                            content: textOnly(
                                definition.item,
                                context: context
                            )
                        )
                    )
                )
                var nestedState = state
                result.append(
                    contentsOf: try blocks(
                        from: definition.descriptions,
                        context: context,
                        state: &nestedState
                    )
                )
            }
            return result
        case let .custom(custom):
            let source = custom.description
            guard !source.isEmpty else {
                return []
            }
            return [
                .unsupported(
                    GitLabMarkdownUnsupported(
                        kind: .serverSpecific,
                        source: source
                    )
                ),
            ]
        }
    }

    private static func blocks(
        from children: Blocks,
        context: GitLabMarkdownLinkContext,
        state: inout ConversionState
    ) throws -> [GitLabMarkdownBlock] {
        var result: [GitLabMarkdownBlock] = []
        for child in children {
            result.append(
                contentsOf: try blocks(
                    from: child,
                    context: context,
                    state: &state
                )
            )
        }
        return result
    }

    private static func list(
        start: Int?,
        children: Blocks,
        context: GitLabMarkdownLinkContext,
        state: ConversionState
    ) throws -> GitLabMarkdownList {
        var items: [GitLabMarkdownListItem] = []

        for (index, child) in children.enumerated() {
            guard
                case let .listItem(
                    listType,
                    _,
                    itemChildren
                ) = child
            else {
                continue
            }
            var nestedState = state
            var itemBlocks = try blocks(
                from: itemChildren,
                context: context,
                state: &nestedState
            )
            let taskState = removeTaskMarker(
                from: &itemBlocks
            )
            items.append(
                GitLabMarkdownListItem(
                    ordinal:
                        listType.startNumber
                        ?? start.map { $0 + index }
                        ?? index + 1,
                    taskState: taskState,
                    taskSourceID: nil,
                    blocks: itemBlocks
                )
            )
        }

        return GitLabMarkdownList(
            kind: start == nil
                ? .unordered
                : .ordered,
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
            let paragraph = blocks[index].paragraph
        else {
            return nil
        }

        let source = paragraph.plainText
        let state: GitLabMarkdownTaskState
        let markerLength: Int
        if source.hasPrefix("[ ]") {
            state = .incomplete
            markerLength = source.hasPrefix("[ ] ") ? 4 : 3
        } else if
            source.hasPrefix("[x]")
                || source.hasPrefix("[X]")
        {
            state = .complete
            markerLength =
                source.hasPrefix("[x] ")
                    || source.hasPrefix("[X] ")
                ? 4
                : 3
        } else if source.hasPrefix("[-]") {
            state = .inapplicable
            markerLength = source.hasPrefix("[-] ") ? 4 : 3
        } else {
            return nil
        }

        var value = paragraph.attributedString
        let end = value.characters.index(
            value.characters.startIndex,
            offsetBy: markerLength
        )
        value.removeSubrange(
            value.startIndex..<end
        )
        blocks[index] = .paragraph(
            GitLabMarkdownText(
                attributedString: value
            )
        )
        return state
    }

    private static func table(
        header: Row,
        alignments: Alignments,
        rows: Rows,
        context: GitLabMarkdownLinkContext
    ) -> GitLabMarkdownTable {
        let convertedHeader = header.map {
            textOnly($0, context: context)
        }
        let convertedRows = rows.map { row in
            row.map {
                textOnly($0, context: context)
            }
        }
        let columnCount = max(
            convertedHeader.count,
            convertedRows.map(\.count).max() ?? 0
        )
        let characterCounts = (0..<columnCount).map {
            column in
            ([convertedHeader] + convertedRows)
                .compactMap { row in
                    row.indices.contains(column)
                        ? row[column].plainText.count
                        : nil
                }
                .max() ?? 0
        }

        return GitLabMarkdownTable(
            alignments: alignments.map {
                switch $0 {
                case .center:
                    .center
                case .right:
                    .right
                case .undefined, .left:
                    .left
                }
            },
            header: Array(convertedHeader),
            rows: convertedRows.map(Array.init),
            columnCharacterCounts: characterCounts
        )
    }

    private static func textBlocks(
        from source: MarkdownKit.Text,
        context: GitLabMarkdownLinkContext,
        alignment: GitLabMarkdownBlockAlignment,
        makeTextBlock:
            (GitLabMarkdownText) -> GitLabMarkdownBlock
    ) -> [GitLabMarkdownBlock] {
        let components = inlineComponents(
            from: source,
            context: context
        )
        var result: [GitLabMarkdownBlock] = []
        var text = AttributedString()
        var images: [GitLabMarkdownImage] = []

        func flushText() {
            guard
                !String(text.characters)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
            else {
                text = AttributedString()
                return
            }
            result.append(
                makeTextBlock(
                    GitLabMarkdownText(
                        attributedString: text
                    )
                )
            )
            text = AttributedString()
        }

        func flushImages() {
            guard !images.isEmpty else {
                return
            }
            if
                images.count == 1,
                alignment == .leading
            {
                result.append(.image(images[0]))
            } else {
                result.append(
                    .imageGroup(
                        GitLabMarkdownImageGroup(
                            images: images,
                            alignment: alignment
                        )
                    )
                )
            }
            images = []
        }

        for component in components {
            switch component {
            case let .text(value):
                let isWhitespace =
                    String(value.characters)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .isEmpty
                if !images.isEmpty {
                    if isWhitespace {
                        continue
                    }
                    flushImages()
                }
                text.append(value)
            case let .image(image):
                flushText()
                images.append(image)
            }
        }

        flushText()
        flushImages()
        return result
    }

    private static func textOnly(
        _ source: MarkdownKit.Text,
        context: GitLabMarkdownLinkContext
    ) -> GitLabMarkdownText {
        var result = AttributedString()
        for component in inlineComponents(
            from: source,
            context: context
        ) {
            switch component {
            case let .text(value):
                result.append(value)
            case let .image(image):
                result.append(
                    AttributedString(image.altText)
                )
            }
        }
        return GitLabMarkdownText(
            attributedString: result
        )
    }

    private static func inlineComponents(
        from source: MarkdownKit.Text,
        context: GitLabMarkdownLinkContext,
        linkURL: URL? = nil
    ) -> [InlineComponent] {
        var result: [InlineComponent] = []

        for fragment in source {
            switch fragment {
            case let .text(value):
                var source = String(value)
                if
                    case let .image(image)? = result.last,
                    let attributes =
                        GitLabMarkdownMediaAttributeParser
                        .parsePrefix(in: source)
                {
                    result[result.count - 1] = .image(
                        image.applying(
                            dimensions:
                                attributes.dimensions
                        )
                    )
                    source = attributes.remainder
                }
                guard !source.isEmpty else {
                    continue
                }
                var text = linkReferences(
                    in: AttributedString(
                        source
                    ),
                    context: context
                )
                if let linkURL {
                    text.link = linkURL
                }
                result.append(.text(text))
            case let .code(value):
                var text = AttributedString(
                    String(value)
                )
                text.inlinePresentationIntent = .code
                if let linkURL {
                    text.link = linkURL
                }
                result.append(.text(text))
            case let .emph(text):
                result.append(
                    contentsOf: applying(
                        .emphasized,
                        to: inlineComponents(
                            from: text,
                            context: context,
                            linkURL: linkURL
                        )
                    )
                )
            case let .strong(text):
                result.append(
                    contentsOf: applying(
                        .stronglyEmphasized,
                        to: inlineComponents(
                            from: text,
                            context: context,
                            linkURL: linkURL
                        )
                    )
                )
            case let .link(text, rawURL, _):
                let resolved = rawURL
                    .flatMap(URL.init(string:))
                    .flatMap(context.resolve)
                result.append(
                    contentsOf: inlineComponents(
                        from: text,
                        context: context,
                        linkURL: resolved
                    )
                )
            case let .autolink(_, rawURL):
                let displayValue = String(rawURL)
                var text = AttributedString(displayValue)
                if
                    let url = URL(string: displayValue),
                    let resolved = context.resolve(url)
                {
                    text.link = resolved
                }
                result.append(.text(text))
            case let .image(text, rawURL, _):
                let altText = text.string
                guard
                    let rawURL,
                    let url = URL(string: rawURL),
                    let resolved = context
                        .resolveImageCandidates(url)
                        .first
                else {
                    if !altText.isEmpty {
                        result.append(
                            .text(
                                AttributedString(
                                    altText
                                )
                            )
                        )
                    }
                    continue
                }
                let urls = context.resolveImageCandidates(
                    url
                )
                result.append(
                    .image(
                        GitLabMarkdownImage(
                            accountID: context.accountID,
                            url: resolved,
                            fallbackURLs:
                                Array(urls.dropFirst()),
                            altText: altText,
                            linkURL: linkURL,
                            browserURL:
                                context.resolveImageBrowserURL(
                                    url
                                ),
                            kind:
                                GitLabMarkdownMediaKind(
                                    url: url
                                )
                        )
                    )
                )
            case let .html(value):
                let tag = String(value)
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    .lowercased()
                if
                    tag.hasPrefix("br")
                        || tag.hasPrefix("/p")
                {
                    result.append(
                        .text(AttributedString("\n"))
                    )
                }
            case let .delimiter(character, count, _):
                result.append(
                    .text(
                        AttributedString(
                            String(
                                repeating: character,
                                count: count
                            )
                        )
                    )
                )
            case .softLineBreak:
                result.append(
                    .text(AttributedString(" "))
                )
            case .hardLineBreak:
                result.append(
                    .text(AttributedString("\n"))
                )
            case let .custom(custom):
                result.append(
                    .text(
                        AttributedString(
                            custom.rawDescription
                        )
                    )
                )
            }
        }

        return result
    }

    private static func applying(
        _ intent: InlinePresentationIntent,
        to components: [InlineComponent]
    ) -> [InlineComponent] {
        components.map { component in
            guard case let .text(source) = component else {
                return component
            }
            var result = source
            let ranges = result.runs.map(\.range)
            for range in ranges {
                var combined =
                    result[range]
                    .inlinePresentationIntent
                    ?? []
                combined.formUnion(intent)
                result[range]
                    .inlinePresentationIntent = combined
            }
            return .text(result)
        }
    }

    private static func htmlBlocks(
        source: String,
        context: GitLabMarkdownLinkContext,
        state: inout ConversionState
    ) -> [GitLabMarkdownBlock] {
        let trimmed = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !trimmed.isEmpty else {
            return []
        }

        if isCenteredContainerOpening(trimmed) {
            state.centeredContainerDepth += 1
            return []
        }
        if isContainerClosing(trimmed) {
            state.centeredContainerDepth = max(
                0,
                state.centeredContainerDepth - 1
            )
            return []
        }
        if isTagOnly(trimmed) {
            return []
        }

        let sanitized = GitLabMarkdownHTMLSanitizer
            .sanitize(
                source: source,
                context: context
            )
        var result: [GitLabMarkdownBlock] = []
        if let richText = sanitized.richText {
            result.append(.richText(richText))
        }
        if !sanitized.images.isEmpty {
            result.append(
                .imageGroup(
                    GitLabMarkdownImageGroup(
                        images: sanitized.images,
                        alignment:
                            sanitized.isCentered
                                || state.alignment == .center
                            ? .center
                            : .leading
                    )
                )
            )
        }
        return result
    }

    private static func isCenteredContainerOpening(
        _ source: String
    ) -> Bool {
        source.range(
            of:
                #"(?is)^<div\b[^>]*\balign\s*=\s*[\"']?center[\"']?[^>]*>\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isContainerClosing(
        _ source: String
    ) -> Bool {
        source.range(
            of: #"(?is)^</div\s*>$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isTagOnly(
        _ source: String
    ) -> Bool {
        source.range(
            of: #"(?is)^<[^>]+>\s*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func joinedCode(
        _ lines: Lines
    ) -> String {
        lines.map(String.init)
            .joined(separator: "\n")
    }

    private static func linkReferences(
        in source: AttributedString,
        context: GitLabMarkdownLinkContext
    ) -> AttributedString {
        guard
            let expression = try? NSRegularExpression(
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
        else {
            return source
        }
        let text = String(source.characters)
        let matches = expression.matches(
            in: text,
            range: NSRange(
                text.startIndex..<text.endIndex,
                in: text
            )
        )
        guard !matches.isEmpty else {
            return source
        }

        var result = AttributedString()
        var cursor = text.startIndex
        for match in matches {
            guard
                let range = Range(
                    match.range,
                    in: text
                )
            else {
                continue
            }
            if cursor < range.lowerBound {
                result.append(
                    AttributedString(
                        String(text[cursor..<range.lowerBound])
                    )
                )
            }
            let matched = String(text[range])
            var linked = AttributedString(matched)
            if
                let marker = matched.first,
                let url = context.referenceURL(
                    marker: marker,
                    value: String(matched.dropFirst())
                )
            {
                linked.link = url
            }
            result.append(linked)
            cursor = range.upperBound
        }
        if cursor < text.endIndex {
            result.append(
                AttributedString(String(text[cursor...]))
            )
        }
        return result
    }
}

nonisolated private enum GitLabMarkdownHTMLSanitizer {
    private struct RangedMatch {
        let source: String
        let range: NSRange
    }

    struct Result {
        let richText: GitLabMarkdownRichText?
        let images: [GitLabMarkdownImage]
        let isCentered: Bool
    }

    static func sanitize(
        source: String,
        context: GitLabMarkdownLinkContext
    ) -> Result {
        let isCentered = source.range(
            of:
                #"(?is)\balign\s*=\s*[\"']?center[\"']?"#,
            options: .regularExpression
        ) != nil
        var sanitized = source
        sanitized = replacing(
            #"(?is)<!--.*?-->"#,
            in: sanitized,
            with: ""
        )
        sanitized = replacing(
            #"(?is)<(script|style|iframe|object|video|audio|canvas)\b[^>]*>.*?</\1\s*>"#,
            in: sanitized,
            with: ""
        )
        sanitized = replacing(
            #"(?is)<(script|style|iframe|object|video|audio|canvas)\b[^>]*/?>"#,
            in: sanitized,
            with: ""
        )

        let imageTags = rangedMatches(
            #"(?is)<img\b[^>]*>"#,
            in: sanitized
        )
        let anchors = rangedMatches(
            #"(?is)<a\b[^>]*>.*?</a\s*>"#,
            in: sanitized
        )
        let images = imageTags.compactMap { match -> GitLabMarkdownImage? in
            guard
                let rawURL = attribute(
                    "src",
                    in: match.source
                ),
                let url = URL(
                    string: decodeEntities(rawURL)
                ),
                let resolved = context
                    .resolveImageCandidates(url)
                    .first
            else {
                return nil
            }
            let urls = context.resolveImageCandidates(
                url
            )
            let linkURL = anchors.first {
                NSLocationInRange(
                    match.range.location,
                    $0.range
                )
                    && NSMaxRange(match.range)
                        <= NSMaxRange($0.range)
            }
            .flatMap {
                attribute("href", in: $0.source)
            }
            .map(decodeEntities)
            .flatMap(URL.init(string:))
            .flatMap(context.resolve)
            return GitLabMarkdownImage(
                accountID: context.accountID,
                url: resolved,
                fallbackURLs: Array(urls.dropFirst()),
                altText: attribute(
                    "alt",
                    in: match.source
                )
                    .map(decodeEntities)
                    ?? "",
                linkURL: linkURL,
                browserURL:
                    context.resolveImageBrowserURL(url),
                kind:
                    GitLabMarkdownMediaKind(url: url),
                dimensions:
                    htmlDimensions(in: match.source)
            )
        }
        sanitized = replacing(
            #"(?is)<img\b[^>]*>"#,
            in: sanitized,
            with: ""
        )
        sanitized = replacing(
            #"(?is)\s+on[a-z]+\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)"#,
            in: sanitized,
            with: ""
        )
        sanitized = replacing(
            #"(?is)\s+style\s*=\s*(\"[^\"]*\"|'[^']*'|[^\s>]+)"#,
            in: sanitized,
            with: ""
        )

        return Result(
            richText: richText(
                from: sanitized,
                context: context
            ),
            images: images,
            isCentered: isCentered
        )
    }

    private static func htmlDimensions(
        in tag: String
    ) -> GitLabMarkdownMediaDimensions? {
        var values: [String] = []
        if let width = attribute("width", in: tag) {
            values.append("width=\(width)")
        }
        if let height = attribute("height", in: tag) {
            values.append("height=\(height)")
        }
        guard !values.isEmpty else {
            return nil
        }
        return GitLabMarkdownMediaAttributeParser
            .parsePrefix(
                in: "{" + values.joined(separator: " ") + "}"
            )?
            .dimensions
    }

    private static func richText(
        from source: String,
        context: GitLabMarkdownLinkContext
    ) -> GitLabMarkdownRichText? {
        let visibleSource = source.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard
            !visibleSource.isEmpty,
            visibleSource.range(
                of: #"(?is)^<[^>]+>\s*</[^>]+>$"#,
                options: .regularExpression
            ) == nil
        else {
            return nil
        }

        let document = ExtendedMarkdownParser.standard
            .parse(visibleSource)
        guard let generated = AttributedStringGenerator(
            fontSize: 17,
            fontColor: "#1F2328",
            codeFontSize: 15,
            codeFontColor: "#1F2328",
            codeBlockFontSize: 14,
            codeBlockFontColor: "#1F2328",
            codeBlockBackground: "#F6F8FA",
            syntaxHighlighting: nil,
            borderColor: "#D0D7DE",
            blockquoteColor: "#8C959F",
            h1Color: "#1F2328",
            h2Color: "#1F2328",
            h3Color: "#1F2328",
            h4Color: "#1F2328",
            maxImageWidth: "100%"
        ).generate(doc: document) else {
            return nil
        }
        let mutable = NSMutableAttributedString(
            attributedString: generated
        )
        let fullRange = NSRange(
            location: 0,
            length: mutable.length
        )
        mutable.removeAttribute(
            NSAttributedString.Key.foregroundColor,
            range: fullRange
        )
        mutable.removeAttribute(
            NSAttributedString.Key.backgroundColor,
            range: fullRange
        )
        mutable.removeAttribute(
            NSAttributedString.Key.attachment,
            range: fullRange
        )
        mutable.enumerateAttribute(
            NSAttributedString.Key.link,
            in: fullRange
        ) { value, range, _ in
            let rawURL: URL?
            if let url = value as? URL {
                rawURL = url
            } else if let value = value as? String {
                rawURL = URL(string: value)
            } else {
                rawURL = nil
            }
            guard
                let rawURL,
                let resolved = context.resolve(rawURL)
            else {
                mutable.removeAttribute(
                    NSAttributedString.Key.link,
                    range: range
                )
                return
            }
            mutable.addAttribute(
                NSAttributedString.Key.link,
                value: resolved,
                range: range
            )
        }

        guard
            let trimmedRange = trimmedRange(
                in: mutable.string
            )
        else {
            return nil
        }
        return GitLabMarkdownRichText(
            mutable.attributedSubstring(
                from: trimmedRange
            )
        )
    }

    private static func trimmedRange(
        in source: String
    ) -> NSRange? {
        let characterSet = CharacterSet
            .whitespacesAndNewlines
            .inverted
        guard
            let first = source.rangeOfCharacter(
                from: characterSet
            ),
            let last = source.rangeOfCharacter(
                from: characterSet,
                options: .backwards
            )
        else {
            return nil
        }
        return NSRange(
            first.lowerBound..<last.upperBound,
            in: source
        )
    }

    private static func rangedMatches(
        _ pattern: String,
        in source: String
    ) -> [RangedMatch] {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern
            )
        else {
            return []
        }
        return expression.matches(
            in: source,
            range: NSRange(
                source.startIndex..<source.endIndex,
                in: source
            )
        ).compactMap { match in
            Range(match.range, in: source).map {
                RangedMatch(
                    source: String(source[$0]),
                    range: match.range
                )
            }
        }
    }

    private static func replacing(
        _ pattern: String,
        in source: String,
        with replacement: String
    ) -> String {
        guard
            let expression = try? NSRegularExpression(
                pattern: pattern
            )
        else {
            return source
        }
        return expression.stringByReplacingMatches(
            in: source,
            range: NSRange(
                source.startIndex..<source.endIndex,
                in: source
            ),
            withTemplate: replacement
        )
    }

    private static func attribute(
        _ name: String,
        in tag: String
    ) -> String? {
        let escapedName = NSRegularExpression
            .escapedPattern(for: name)
        let patterns = [
            "(?is)\\b\(escapedName)\\s*=\\s*\"([^\"]*)\"",
            "(?is)\\b\(escapedName)\\s*=\\s*'([^']*)'",
            "(?is)\\b\(escapedName)\\s*=\\s*([^\\s>]+)",
        ]
        for pattern in patterns {
            guard
                let expression = try? NSRegularExpression(
                    pattern: pattern
                ),
                let match = expression.firstMatch(
                    in: tag,
                    range: NSRange(
                        tag.startIndex..<tag.endIndex,
                        in: tag
                    )
                ),
                match.numberOfRanges > 1,
                let range = Range(
                    match.range(at: 1),
                    in: tag
                )
            else {
                continue
            }
            return String(tag[range])
        }
        return nil
    }

    private static func decodeEntities(
        _ source: String
    ) -> String {
        source
            .replacingOccurrences(
                of: "&amp;",
                with: "&"
            )
            .replacingOccurrences(
                of: "&quot;",
                with: "\""
            )
            .replacingOccurrences(
                of: "&#39;",
                with: "'"
            )
            .replacingOccurrences(
                of: "&lt;",
                with: "<"
            )
            .replacingOccurrences(
                of: "&gt;",
                with: ">"
            )
    }
}
