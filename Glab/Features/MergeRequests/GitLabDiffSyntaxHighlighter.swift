import Foundation

nonisolated struct GitLabDiffSyntaxHighlightRequest:
    Sendable
{
    let document: GitLabParsedDiffDocument
    let oldLanguage: GitLabSyntaxLanguage?
    let newLanguage: GitLabSyntaxLanguage?
    let theme: GitLabSyntaxTheme
}

nonisolated struct GitLabDiffHighlightedLine:
    Sendable
{
    private let source: GitLabHighlightedText
    private let range: NSRange

    init(
        source: GitLabHighlightedText,
        range: NSRange
    ) {
        self.source = source
        self.range = range
    }

    init(_ attributedString: NSAttributedString) {
        source = GitLabHighlightedText(
            attributedString
        )
        range = NSRange(
            location: 0,
            length: attributedString.length
        )
    }

    var attributedString: NSAttributedString {
        source.attributedString.attributedSubstring(
            from: range
        )
    }
}

nonisolated struct GitLabDiffSyntaxHighlighter:
    Sendable
{
    static let maximumHunkCount = 100
    static let maximumProjectedSourceByteCount =
        GitLabSyntaxHighlighter.maximumInputByteCount * 2

    private struct Projection: Sendable {
        let lines: [String]
        let ordinals: [Int]
    }

    private let syntaxHighlighter:
        any GitLabSyntaxHighlighting

    init(
        syntaxHighlighter:
            any GitLabSyntaxHighlighting
    ) {
        self.syntaxHighlighter = syntaxHighlighter
    }

    @concurrent
    func highlight(
        _ request: GitLabDiffSyntaxHighlightRequest
    ) async throws -> [Int: GitLabDiffHighlightedLine] {
        try Task.checkCancellation()
        guard
            request.oldLanguage != nil
                || request.newLanguage != nil,
            !request.document.hunks.isEmpty,
            request.document.hunks.count
                <= Self.maximumHunkCount,
            try Self.projectedSourceByteCount(
                in: request.document
            ) <= Self.maximumProjectedSourceByteCount
        else {
            return [:]
        }

        var result: [Int: GitLabDiffHighlightedLine] = [:]
        result.reserveCapacity(
            request.document.items.count
        )

        for hunkIndex in request.document.hunks.indices {
            try Task.checkCancellation()
            let hunk = request.document.hunks[hunkIndex]
            let endIndex =
                if
                    request.document.hunks.indices
                    .contains(hunkIndex + 1)
                {
                    request.document.hunks[
                        hunkIndex + 1
                    ].renderItemIndex
                } else {
                    request.document.items.endIndex
                }
            let itemRange = request.document.items.index(
                after: hunk.renderItemIndex
            )..<endIndex
            let projections = try Self.projections(
                for: request.document.items[itemRange]
            )

            if let oldLanguage = request.oldLanguage {
                let oldLines = try await highlightedLines(
                    projections.old,
                    language: oldLanguage,
                    theme: request.theme
                )
                result.merge(oldLines) { _, new in new }
            }

            if let newLanguage = request.newLanguage {
                let newLines = try await highlightedLines(
                    projections.new,
                    language: newLanguage,
                    theme: request.theme
                )
                // The new side is the preferred source of attributes for
                // context rows shared by both projections.
                result.merge(newLines) { _, new in new }
            }
        }

        try Task.checkCancellation()
        return result
    }

    private func highlightedLines(
        _ projection: Projection,
        language: GitLabSyntaxLanguage,
        theme: GitLabSyntaxTheme
    ) async throws -> [Int: GitLabDiffHighlightedLine] {
        guard !projection.lines.isEmpty else {
            return [:]
        }
        try Task.checkCancellation()
        guard
            let highlighted = await syntaxHighlighter
                .highlight(
                    GitLabSyntaxHighlightRequest(
                        lines: projection.lines,
                        language: language,
                        theme: theme
                    )
                )
        else {
            try Task.checkCancellation()
            return [:]
        }
        try Task.checkCancellation()
        guard
            let ranges = try Self.lineRanges(
                for: projection.lines,
                in: highlighted.attributedString
            )
        else {
            return [:]
        }

        var result: [Int: GitLabDiffHighlightedLine] = [:]
        result.reserveCapacity(
            projection.ordinals.count
        )
        for index in projection.lines.indices {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            result[projection.ordinals[index]] =
                GitLabDiffHighlightedLine(
                    source: highlighted,
                    range: ranges[index]
                )
        }
        return result
    }

    private static func projections(
        for items: ArraySlice<GitLabDiffRenderItem>
    ) throws -> (old: Projection, new: Projection) {
        var oldLines: [String] = []
        var oldOrdinals: [Int] = []
        var newLines: [String] = []
        var newOrdinals: [Int] = []

        for (index, item) in items.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            guard let line = item.line else {
                continue
            }
            switch line.kind {
            case .context:
                oldLines.append(line.text)
                oldOrdinals.append(line.ordinal)
                newLines.append(line.text)
                newOrdinals.append(line.ordinal)
            case .addition:
                newLines.append(line.text)
                newOrdinals.append(line.ordinal)
            case .deletion:
                oldLines.append(line.text)
                oldOrdinals.append(line.ordinal)
            }
        }

        return (
            old: Projection(
                lines: oldLines,
                ordinals: oldOrdinals
            ),
            new: Projection(
                lines: newLines,
                ordinals: newOrdinals
            )
        )
    }

    private static func lineRanges(
        for lines: [String],
        in highlighted: NSAttributedString
    ) throws -> [NSRange]? {
        var ranges: [NSRange] = []
        ranges.reserveCapacity(lines.count)
        var location = 0
        for (index, line) in lines.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            let length = line.utf16.count
            ranges.append(
                NSRange(
                    location: location,
                    length: length
                )
            )
            location += length + 1
        }
        guard
            max(0, location - 1)
                == highlighted.length
        else {
            return nil
        }
        return ranges
    }

    private static func projectedSourceByteCount(
        in document: GitLabParsedDiffDocument
    ) throws -> Int {
        var byteCount = 0
        var projectedLineCount = 0
        for (index, item) in document.items.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }
            guard let line = item.line else {
                continue
            }
            let projectionCount =
                line.kind == .context ? 2 : 1
            byteCount +=
                line.text.utf8.count
                * projectionCount
            projectedLineCount += projectionCount
            guard
                byteCount
                    <= maximumProjectedSourceByteCount
            else {
                return byteCount
            }
        }
        return byteCount
            + max(0, projectedLineCount - 1)
    }
}
