import Foundation

nonisolated enum GitLabDiffLineKind:
    Equatable,
    Sendable
{
    case context
    case addition
    case deletion
}

nonisolated struct GitLabDiffLine:
    Equatable,
    Sendable
{
    let ordinal: Int
    let kind: GitLabDiffLineKind
    let oldLineNumber: Int?
    let newLineNumber: Int?
    let text: String
}

nonisolated struct GitLabDiffHunk:
    Equatable,
    Sendable
{
    let ordinal: Int
    let header: String
    let oldStart: Int
    let oldCount: Int
    let newStart: Int
    let newCount: Int
    let renderItemIndex: Int
}

nonisolated enum GitLabDiffRenderItem:
    Equatable,
    Sendable
{
    case hunkHeader(ordinal: Int, text: String)
    case context(GitLabDiffLine)
    case addition(GitLabDiffLine)
    case deletion(GitLabDiffLine)
    case noNewlineMarker(String)
    case fileMetadata(String)

    var line: GitLabDiffLine? {
        switch self {
        case let .context(line),
             let .addition(line),
             let .deletion(line):
            line
        case .hunkHeader,
             .noNewlineMarker,
             .fileMetadata:
            nil
        }
    }

    var text: String {
        switch self {
        case let .hunkHeader(_, text),
             let .noNewlineMarker(text),
             let .fileMetadata(text):
            text
        case let .context(line),
             let .addition(line),
             let .deletion(line):
            line.text
        }
    }
}

nonisolated struct GitLabParsedDiffDocument:
    Equatable,
    Sendable
{
    let items: [GitLabDiffRenderItem]
    let hunks: [GitLabDiffHunk]
    let lineCount: Int
    let estimatedCacheCost: Int
    let maximumRenderedColumnCount: Int
}

nonisolated enum GitLabUnifiedDiffParserError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible
{
    case malformedHunk(sourceLine: Int)

    var description: String {
        switch self {
        case let .malformedHunk(sourceLine):
            "GitLab returned a malformed diff hunk at line \(sourceLine)."
        }
    }

    var errorDescription: String? {
        description
    }
}

nonisolated enum GitLabUnifiedDiffParser {
    private static let itemOverhead = 96
    private static let hunkOverhead = 80

    @concurrent
    static func parse(
        _ source: String
    ) async throws -> GitLabParsedDiffDocument {
        try Task.checkCancellation()
        guard !source.isEmpty else {
            return GitLabParsedDiffDocument(
                items: [],
                hunks: [],
                lineCount: 0,
                estimatedCacheCost: 0,
                maximumRenderedColumnCount: 0
            )
        }

        let normalizedSource = source.replacingOccurrences(
            of: "\r\n",
            with: "\n"
        )
        var sourceLines = normalizedSource.split(
            separator: "\n",
            omittingEmptySubsequences: false
        )
        if normalizedSource.last == "\n" {
            sourceLines.removeLast()
        }

        var items: [GitLabDiffRenderItem] = []
        items.reserveCapacity(sourceLines.count)
        var hunks: [GitLabDiffHunk] = []
        var oldLineNumber: Int?
        var newLineNumber: Int?
        var isInsideHunk = false
        var lineOrdinal = 0
        var renderedTextCost = 0
        var maximumRenderedColumnCount = 0

        for (index, rawSourceLine) in sourceLines.enumerated() {
            if index.isMultiple(of: 256) {
                try Task.checkCancellation()
            }

            let sourceLine =
                rawSourceLine.last == "\r"
                    ? rawSourceLine.dropLast()
                    : rawSourceLine[...]
            let sourceLineNumber = index + 1

            if sourceLine.hasPrefix("@@") {
                guard
                    let parsed = parseHunkHeader(
                        sourceLine
                    )
                else {
                    throw GitLabUnifiedDiffParserError
                        .malformedHunk(
                            sourceLine:
                                sourceLineNumber
                        )
                }

                let header = String(sourceLine)
                let hunk = GitLabDiffHunk(
                    ordinal: hunks.count,
                    header: header,
                    oldStart: parsed.oldStart,
                    oldCount: parsed.oldCount,
                    newStart: parsed.newStart,
                    newCount: parsed.newCount,
                    renderItemIndex: items.count
                )
                hunks.append(hunk)
                items.append(
                    .hunkHeader(
                        ordinal: hunk.ordinal,
                        text: header
                    )
                )
                oldLineNumber = hunk.oldStart
                newLineNumber = hunk.newStart
                isInsideHunk = true
                record(
                    header,
                    renderedTextCost:
                        &renderedTextCost,
                    maximumColumns:
                        &maximumRenderedColumnCount
                )
                continue
            }

            guard isInsideHunk else {
                let metadata = String(sourceLine)
                items.append(
                    .fileMetadata(metadata)
                )
                record(
                    metadata,
                    renderedTextCost:
                        &renderedTextCost,
                    maximumColumns:
                        &maximumRenderedColumnCount
                )
                continue
            }

            if sourceLine
                == "\\ No newline at end of file"
            {
                let marker = String(sourceLine)
                items.append(
                    .noNewlineMarker(marker)
                )
                record(
                    marker,
                    renderedTextCost:
                        &renderedTextCost,
                    maximumColumns:
                        &maximumRenderedColumnCount
                )
                continue
            }

            guard let prefix = sourceLine.first else {
                items.append(.fileMetadata(""))
                continue
            }

            let text = String(sourceLine.dropFirst())
            let line: GitLabDiffLine

            switch prefix {
            case " ":
                line = GitLabDiffLine(
                    ordinal: lineOrdinal,
                    kind: .context,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: newLineNumber,
                    text: text
                )
                items.append(.context(line))
                oldLineNumber = increment(
                    oldLineNumber
                )
                newLineNumber = increment(
                    newLineNumber
                )
            case "-":
                line = GitLabDiffLine(
                    ordinal: lineOrdinal,
                    kind: .deletion,
                    oldLineNumber: oldLineNumber,
                    newLineNumber: nil,
                    text: text
                )
                items.append(.deletion(line))
                oldLineNumber = increment(
                    oldLineNumber
                )
            case "+":
                line = GitLabDiffLine(
                    ordinal: lineOrdinal,
                    kind: .addition,
                    oldLineNumber: nil,
                    newLineNumber: newLineNumber,
                    text: text
                )
                items.append(.addition(line))
                newLineNumber = increment(
                    newLineNumber
                )
            default:
                let metadata = String(sourceLine)
                items.append(
                    .fileMetadata(metadata)
                )
                record(
                    metadata,
                    renderedTextCost:
                        &renderedTextCost,
                    maximumColumns:
                        &maximumRenderedColumnCount
                )
                continue
            }

            lineOrdinal += 1
            record(
                text,
                renderedTextCost:
                    &renderedTextCost,
                maximumColumns:
                    &maximumRenderedColumnCount
            )
        }

        try Task.checkCancellation()
        let estimatedCacheCost =
            source.utf8.count
            + renderedTextCost
            + items.count * itemOverhead
            + hunks.count * hunkOverhead
        return GitLabParsedDiffDocument(
            items: items,
            hunks: hunks,
            lineCount: sourceLines.count,
            estimatedCacheCost: estimatedCacheCost,
            maximumRenderedColumnCount:
                maximumRenderedColumnCount
        )
    }

    private static func parseHunkHeader(
        _ header: Substring
    ) -> (
        oldStart: Int,
        oldCount: Int,
        newStart: Int,
        newCount: Int
    )? {
        guard header.hasPrefix("@@ ") else {
            return nil
        }

        var remainder = header.dropFirst(3)
        guard
            let oldRange = parseRange(
                in: &remainder,
                marker: "-"
            ),
            remainder.first == " "
        else {
            return nil
        }
        remainder.removeFirst()
        guard
            let newRange = parseRange(
                in: &remainder,
                marker: "+"
            ),
            remainder.hasPrefix(" @@")
        else {
            return nil
        }
        let trailingText = remainder.dropFirst(3)
        guard
            trailingText.isEmpty
                || trailingText.first == " "
        else {
            return nil
        }

        return (
            oldStart: oldRange.start,
            oldCount: oldRange.count,
            newStart: newRange.start,
            newCount: newRange.count
        )
    }

    private static func parseRange(
        in source: inout Substring,
        marker: Character
    ) -> (start: Int, count: Int)? {
        guard source.first == marker else {
            return nil
        }
        source.removeFirst()

        let startDigits = source.prefix {
            $0.isNumber
        }
        guard
            !startDigits.isEmpty,
            let start = Int(startDigits)
        else {
            return nil
        }
        source.removeFirst(startDigits.count)

        guard source.first == "," else {
            return (start, 1)
        }
        source.removeFirst()

        let countDigits = source.prefix {
            $0.isNumber
        }
        guard
            !countDigits.isEmpty,
            let count = Int(countDigits)
        else {
            return nil
        }
        source.removeFirst(countDigits.count)
        return (start, count)
    }

    private static func increment(
        _ value: Int?
    ) -> Int? {
        guard let value else {
            return nil
        }
        let result = value.addingReportingOverflow(1)
        return result.overflow
            ? nil
            : result.partialValue
    }

    private static func record(
        _ text: String,
        renderedTextCost: inout Int,
        maximumColumns: inout Int
    ) {
        renderedTextCost += text.utf8.count
        maximumColumns = max(
            maximumColumns,
            renderedColumnCount(text)
        )
    }

    private static func renderedColumnCount(
        _ text: String
    ) -> Int {
        let tabWidth = 4
        var columns = 0

        for scalar in text.unicodeScalars {
            if scalar.value == 0x09 {
                columns +=
                    tabWidth - columns % tabWidth
                continue
            }

            switch scalar.properties.generalCategory {
            case .nonspacingMark,
                 .enclosingMark,
                 .format:
                continue
            default:
                columns += scalar.value < 0x80
                    ? 1
                    : 2
            }
        }

        return columns
    }
}
