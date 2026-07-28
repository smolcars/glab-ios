import CryptoKit
import Foundation

nonisolated enum GitLabMarkdownSourceDigest {
    static func digest(
        for source: String
    ) -> Data {
        Data(
            SHA256.hash(
                data: Data(source.utf8)
            )
        )
    }
}

nonisolated struct GitLabMarkdownTaskSourceID:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible,
    CustomReflectable
{
    let sourceDigest: Data
    let markerUTF8Offset: Int

    var description: String {
        "GitLabMarkdownTaskSourceID(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var customMirror: Mirror {
        Mirror(
            self,
            children: ["redacted": true],
            displayStyle: .struct
        )
    }
}

nonisolated struct GitLabMarkdownIndexedTask:
    Equatable,
    Sendable
{
    let sourceID: GitLabMarkdownTaskSourceID
    let state: GitLabMarkdownTaskState
}

nonisolated enum GitLabMarkdownTaskRewriteError:
    Error,
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case staleSource
    case invalidTask
    case inapplicable
    case noChange

    var description: String {
        "GitLabMarkdownTaskRewriteError(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabMarkdownTaskSourceIndex {
    @concurrent
    static func tasks(
        in source: String
    ) async throws -> [GitLabMarkdownIndexedTask] {
        let digest =
            GitLabMarkdownSourceDigest.digest(
                for: source
            )
        return try GitLabMarkdownTaskSourceScanner
            .tasks(
                in: source,
                sourceDigest: digest
            )
    }
}

nonisolated enum GitLabMarkdownTaskSourceRewriter {
    @concurrent
    static func rewrite(
        _ source: String,
        task: GitLabMarkdownIndexedTask,
        to desiredState:
            GitLabMarkdownTaskState
    ) async throws -> String {
        try Task.checkCancellation()
        guard
            task.state != .inapplicable,
            desiredState != .inapplicable
        else {
            throw GitLabMarkdownTaskRewriteError
                .inapplicable
        }
        guard task.state != desiredState else {
            throw GitLabMarkdownTaskRewriteError
                .noChange
        }

        let digest =
            GitLabMarkdownSourceDigest.digest(
                for: source
            )
        guard
            digest == task.sourceID.sourceDigest
        else {
            throw GitLabMarkdownTaskRewriteError
                .staleSource
        }

        let indexedTasks =
            try GitLabMarkdownTaskSourceScanner
                .tasks(
                    in: source,
                    sourceDigest: digest
                )
        guard
            indexedTasks.contains(task)
        else {
            throw GitLabMarkdownTaskRewriteError
                .invalidTask
        }

        var bytes = Array(source.utf8)
        let markerOffset =
            task.sourceID.markerUTF8Offset
        guard
            markerOffset >= 0,
            markerOffset + 2 < bytes.count,
            bytes[markerOffset]
                == GitLabMarkdownTaskASCII
                    .openBracket,
            bytes[markerOffset + 2]
                == GitLabMarkdownTaskASCII
                    .closeBracket,
            GitLabMarkdownTaskASCII.state(
                for: bytes[markerOffset + 1]
            ) == task.state
        else {
            throw GitLabMarkdownTaskRewriteError
                .invalidTask
        }

        bytes[markerOffset + 1] =
            switch desiredState {
            case .complete:
                GitLabMarkdownTaskASCII
                    .lowercaseX
            case .incomplete:
                GitLabMarkdownTaskASCII.space
            case .inapplicable:
                throw GitLabMarkdownTaskRewriteError
                    .inapplicable
            }

        guard
            let result = String(
                bytes: bytes,
                encoding: .utf8
            )
        else {
            throw GitLabMarkdownTaskRewriteError
                .invalidTask
        }
        return result
    }
}

nonisolated enum GitLabMarkdownTaskSourceMapper {
    static func attaching(
        _ indexedTasks:
            [GitLabMarkdownIndexedTask],
        to document:
            GitLabMarkdownDocument
    ) -> GitLabMarkdownDocument {
        let renderedStates =
            taskStates(
                in: document.blocks
            )
        guard
            renderedStates
                == indexedTasks.map(\.state)
        else {
            var unusedIndex = 0
            return GitLabMarkdownDocument(
                blocks:
                    mappedBlocks(
                        document.blocks,
                        indexedTasks: nil,
                        taskIndex:
                            &unusedIndex
                    )
            )
        }

        var taskIndex = 0
        return GitLabMarkdownDocument(
            blocks:
                mappedBlocks(
                    document.blocks,
                    indexedTasks:
                        indexedTasks,
                    taskIndex: &taskIndex
                )
        )
    }

    private static func taskStates(
        in blocks: [GitLabMarkdownBlock]
    ) -> [GitLabMarkdownTaskState] {
        var result:
            [GitLabMarkdownTaskState] = []

        for block in blocks {
            switch block {
            case let .list(list):
                for item in list.items {
                    if let state =
                        item.taskState
                    {
                        result.append(state)
                    }
                    result.append(
                        contentsOf:
                            taskStates(
                                in: item.blocks
                            )
                    )
                }
            case let .quote(quote):
                result.append(
                    contentsOf:
                        taskStates(
                            in: quote.blocks
                        )
                )
            case .heading,
                 .paragraph,
                 .code,
                 .table,
                 .image,
                 .thematicBreak,
                 .unsupported:
                break
            }
        }

        return result
    }

    private static func mappedBlocks(
        _ blocks: [GitLabMarkdownBlock],
        indexedTasks:
            [GitLabMarkdownIndexedTask]?,
        taskIndex: inout Int
    ) -> [GitLabMarkdownBlock] {
        blocks.map { block in
            switch block {
            case let .list(list):
                .list(
                    GitLabMarkdownList(
                        kind: list.kind,
                        items: list.items.map {
                            item in
                            let sourceID:
                                GitLabMarkdownTaskSourceID?
                            if item.taskState != nil {
                                sourceID =
                                    indexedTasks?[
                                        taskIndex
                                    ].sourceID
                                taskIndex += 1
                            } else {
                                sourceID = nil
                            }

                            return GitLabMarkdownListItem(
                                ordinal:
                                    item.ordinal,
                                taskState:
                                    item.taskState,
                                taskSourceID:
                                    sourceID,
                                blocks:
                                    mappedBlocks(
                                        item.blocks,
                                        indexedTasks:
                                            indexedTasks,
                                        taskIndex:
                                            &taskIndex
                                    )
                            )
                        }
                    )
                )
            case let .quote(quote):
                .quote(
                    GitLabMarkdownQuote(
                        blocks:
                            mappedBlocks(
                                quote.blocks,
                                indexedTasks:
                                    indexedTasks,
                                taskIndex:
                                    &taskIndex
                            )
                    )
                )
            case .heading,
                 .paragraph,
                 .code,
                 .table,
                 .image,
                 .thematicBreak,
                 .unsupported:
                block
            }
        }
    }
}

nonisolated private enum GitLabMarkdownTaskASCII {
    static let tab: UInt8 = 0x09
    static let lineFeed: UInt8 = 0x0A
    static let carriageReturn: UInt8 = 0x0D
    static let space: UInt8 = 0x20
    static let exclamationMark: UInt8 = 0x21
    static let plus: UInt8 = 0x2B
    static let hyphen: UInt8 = 0x2D
    static let period: UInt8 = 0x2E
    static let slash: UInt8 = 0x2F
    static let zero: UInt8 = 0x30
    static let nine: UInt8 = 0x39
    static let lessThan: UInt8 = 0x3C
    static let greaterThan: UInt8 = 0x3E
    static let questionMark: UInt8 = 0x3F
    static let uppercaseA: UInt8 = 0x41
    static let uppercaseX: UInt8 = 0x58
    static let uppercaseZ: UInt8 = 0x5A
    static let openBracket: UInt8 = 0x5B
    static let backslash: UInt8 = 0x5C
    static let closeBracket: UInt8 = 0x5D
    static let lowercaseA: UInt8 = 0x61
    static let lowercaseX: UInt8 = 0x78
    static let lowercaseZ: UInt8 = 0x7A
    static let tilde: UInt8 = 0x7E
    static let asterisk: UInt8 = 0x2A
    static let backtick: UInt8 = 0x60
    static let closingParenthesis: UInt8 = 0x29

    static func state(
        for byte: UInt8
    ) -> GitLabMarkdownTaskState? {
        switch byte {
        case lowercaseX, uppercaseX:
            .complete
        case space:
            .incomplete
        case tilde:
            .inapplicable
        default:
            nil
        }
    }

    static func isHorizontalWhitespace(
        _ byte: UInt8
    ) -> Bool {
        byte == space || byte == tab
    }

    static func isLineEnding(
        _ byte: UInt8
    ) -> Bool {
        byte == lineFeed
            || byte == carriageReturn
    }
}

nonisolated private enum
    GitLabMarkdownTaskSourceScanner
{
    private struct Fence {
        let marker: UInt8
        let minimumLength: Int
    }

    private struct ListContext {
        let markerIndent: Int
        let contentIndent: Int
    }

    private struct LinePrefix {
        let quoteDepth: Int
        let indentation: Int
        let contentStart: Int
    }

    private struct ListMarker {
        let contentStart: Int
        let contentIndent: Int
        let canContainTask: Bool
    }

    static func tasks(
        in source: String,
        sourceDigest: Data
    ) throws -> [GitLabMarkdownIndexedTask] {
        let originalBytes = Array(source.utf8)
        let bytes: [UInt8]
        if source.range(of: "<!--") == nil {
            bytes = originalBytes
        } else {
            bytes =
                bytesMaskingHTMLComments(
                    originalBytes
                )
        }
        var result:
            [GitLabMarkdownIndexedTask] = []
        var listContexts:
            [Int: [ListContext]] = [:]
        var fence: Fence?
        var lineStart = 0
        var lineNumber = 0
        var hasRawHTMLAmbiguity = false

        while lineStart < bytes.count {
            if lineNumber.isMultiple(of: 128) {
                try Task.checkCancellation()
            }
            lineNumber += 1

            var lineEnd = lineStart
            while
                lineEnd < bytes.count,
                !GitLabMarkdownTaskASCII
                    .isLineEnding(bytes[lineEnd])
            {
                lineEnd += 1
            }

            let prefix = linePrefix(
                in: bytes,
                start: lineStart,
                end: lineEnd
            )
            let contentStart =
                prefix.contentStart
            let detectedOpeningFence =
                fence == nil
                ? openingFence(
                    in: bytes,
                    start: contentStart,
                    end: lineEnd
                )
                : nil

            if
                fence == nil,
                detectedOpeningFence == nil,
                containsPotentialRawHTMLTag(
                    in: bytes,
                    start: contentStart,
                    end: lineEnd
                )
            {
                hasRawHTMLAmbiguity = true
            }

            if let activeFence = fence {
                if
                    isFence(
                        in: bytes,
                        start: contentStart,
                        end: lineEnd,
                        marker:
                            activeFence.marker,
                        minimumLength:
                            activeFence
                                .minimumLength
                    )
                {
                    fence = nil
                }
            } else if
                let openingFence =
                    detectedOpeningFence
            {
                fence = openingFence
            } else if
                let marker = listMarker(
                    in: bytes,
                    prefix: prefix,
                    end: lineEnd
                ),
                isValidListIndent(
                    prefix.indentation,
                    contexts:
                        listContexts[
                            prefix.quoteDepth
                        ] ?? []
                )
            {
                updateListContexts(
                    &listContexts,
                    quoteDepth:
                        prefix.quoteDepth,
                    markerIndent:
                        prefix.indentation,
                    contentIndent:
                        marker.contentIndent
                )

                if
                    marker.canContainTask,
                    let state =
                        taskState(
                            in: bytes,
                            markerOffset:
                                marker
                                    .contentStart,
                            lineEnd: lineEnd
                        )
                {
                    result.append(
                        GitLabMarkdownIndexedTask(
                            sourceID:
                                GitLabMarkdownTaskSourceID(
                                    sourceDigest:
                                        sourceDigest,
                                    markerUTF8Offset:
                                        marker
                                            .contentStart
                                ),
                            state: state
                        )
                    )
                }
            } else if contentStart < lineEnd {
                trimListContexts(
                    &listContexts,
                    quoteDepth:
                        prefix.quoteDepth,
                    indentation:
                        prefix.indentation
                )
            }

            lineStart = nextLineStart(
                after: lineEnd,
                in: bytes
            )
        }

        try Task.checkCancellation()
        return hasRawHTMLAmbiguity
            ? []
            : result
    }

    private static func
        containsPotentialRawHTMLTag(
            in bytes: [UInt8],
            start: Int,
            end: Int
        ) -> Bool
    {
        var cursor = start
        while cursor < end {
            guard
                bytes[cursor]
                    == GitLabMarkdownTaskASCII
                        .lessThan,
                !isEscaped(
                    in: bytes,
                    at: cursor,
                    lowerBound: start
                )
            else {
                cursor += 1
                continue
            }

            var nameStart = cursor + 1
            guard nameStart < end else {
                return false
            }
            if
                bytes[nameStart]
                    == GitLabMarkdownTaskASCII
                        .exclamationMark
                    || bytes[nameStart]
                        == GitLabMarkdownTaskASCII
                            .questionMark
            {
                return true
            }
            if
                bytes[nameStart]
                    == GitLabMarkdownTaskASCII
                        .slash
            {
                nameStart += 1
            }
            guard
                nameStart < end,
                isASCIILetter(
                    bytes[nameStart]
                )
            else {
                cursor += 1
                continue
            }

            var probe = nameStart + 1
            while
                probe < end,
                isHTMLTagNameByte(
                    bytes[probe]
                )
            {
                probe += 1
            }
            guard probe < end else {
                return true
            }
            if
                GitLabMarkdownTaskASCII
                    .isHorizontalWhitespace(
                        bytes[probe]
                    )
                    || bytes[probe]
                        == GitLabMarkdownTaskASCII
                            .slash
                    || bytes[probe]
                        == GitLabMarkdownTaskASCII
                            .greaterThan
            {
                return true
            }
            cursor += 1
        }
        return false
    }

    private static func isASCIILetter(
        _ byte: UInt8
    ) -> Bool {
        (
            byte
                >= GitLabMarkdownTaskASCII
                    .uppercaseA
                && byte
                    <= GitLabMarkdownTaskASCII
                        .uppercaseZ
        )
            || (
                byte
                    >= GitLabMarkdownTaskASCII
                        .lowercaseA
                    && byte
                        <= GitLabMarkdownTaskASCII
                            .lowercaseZ
            )
    }

    private static func isHTMLTagNameByte(
        _ byte: UInt8
    ) -> Bool {
        isASCIILetter(byte)
            || (
                byte
                    >= GitLabMarkdownTaskASCII.zero
                    && byte
                        <= GitLabMarkdownTaskASCII
                            .nine
            )
            || byte
                == GitLabMarkdownTaskASCII.hyphen
    }

    private static func isEscaped(
        in bytes: [UInt8],
        at offset: Int,
        lowerBound: Int
    ) -> Bool {
        var cursor = offset
        var backslashCount = 0
        while
            cursor > lowerBound,
            bytes[cursor - 1]
                == GitLabMarkdownTaskASCII
                    .backslash
        {
            cursor -= 1
            backslashCount += 1
        }
        return !backslashCount.isMultiple(of: 2)
    }

    private static func linePrefix(
        in bytes: [UInt8],
        start: Int,
        end: Int
    ) -> LinePrefix {
        var cursor = start
        var quoteDepth = 0

        while cursor < end {
            var probe = cursor
            var leadingSpaces = 0
            while
                probe < end,
                leadingSpaces < 3,
                bytes[probe]
                    == GitLabMarkdownTaskASCII
                        .space
            {
                probe += 1
                leadingSpaces += 1
            }
            guard
                probe < end,
                bytes[probe]
                    == GitLabMarkdownTaskASCII
                        .greaterThan
            else {
                break
            }

            quoteDepth += 1
            cursor = probe + 1
            if
                cursor < end,
                GitLabMarkdownTaskASCII
                    .isHorizontalWhitespace(
                        bytes[cursor]
                    )
            {
                cursor += 1
            }
        }

        var indentation = 0
        while
            cursor < end,
            GitLabMarkdownTaskASCII
                .isHorizontalWhitespace(
                    bytes[cursor]
                )
        {
            indentation =
                nextColumn(
                    after: bytes[cursor],
                    current: indentation
                )
            cursor += 1
        }

        return LinePrefix(
            quoteDepth: quoteDepth,
            indentation: indentation,
            contentStart: cursor
        )
    }

    private static func listMarker(
        in bytes: [UInt8],
        prefix: LinePrefix,
        end: Int
    ) -> ListMarker? {
        var cursor = prefix.contentStart
        guard cursor < end else {
            return nil
        }
        let markerStart = cursor

        switch bytes[cursor] {
        case GitLabMarkdownTaskASCII.hyphen,
             GitLabMarkdownTaskASCII.plus,
             GitLabMarkdownTaskASCII.asterisk:
            cursor += 1
        case GitLabMarkdownTaskASCII.zero
            ... GitLabMarkdownTaskASCII.nine:
            var digitCount = 0
            while
                cursor < end,
                bytes[cursor]
                    >= GitLabMarkdownTaskASCII.zero,
                bytes[cursor]
                    <= GitLabMarkdownTaskASCII.nine,
                digitCount < 10
            {
                cursor += 1
                digitCount += 1
            }
            guard
                digitCount > 0,
                digitCount <= 9,
                cursor < end,
                bytes[cursor]
                    == GitLabMarkdownTaskASCII
                        .period
                    || bytes[cursor]
                        == GitLabMarkdownTaskASCII
                            .closingParenthesis
            else {
                return nil
            }
            cursor += 1
        default:
            return nil
        }

        guard
            cursor < end,
            GitLabMarkdownTaskASCII
                .isHorizontalWhitespace(
                    bytes[cursor]
                )
        else {
            return nil
        }

        let markerEndIndent =
            prefix.indentation
                + cursor
                - markerStart
        var contentIndent =
            markerEndIndent
        while
            cursor < end,
            GitLabMarkdownTaskASCII
                .isHorizontalWhitespace(
                    bytes[cursor]
                )
        {
            contentIndent =
                nextColumn(
                    after: bytes[cursor],
                    current: contentIndent
                )
            cursor += 1
        }
        let canContainTask =
            contentIndent
                - markerEndIndent
                <= 4
        if !canContainTask {
            contentIndent =
                markerEndIndent + 1
        }

        return ListMarker(
            contentStart: cursor,
            contentIndent: contentIndent,
            canContainTask:
                canContainTask
        )
    }

    private static func taskState(
        in bytes: [UInt8],
        markerOffset: Int,
        lineEnd: Int
    ) -> GitLabMarkdownTaskState? {
        guard
            markerOffset + 2 < lineEnd,
            bytes[markerOffset]
                == GitLabMarkdownTaskASCII
                    .openBracket,
            bytes[markerOffset + 2]
                == GitLabMarkdownTaskASCII
                    .closeBracket
        else {
            return nil
        }
        return GitLabMarkdownTaskASCII.state(
            for: bytes[markerOffset + 1]
        )
    }

    private static func isValidListIndent(
        _ indentation: Int,
        contexts: [ListContext]
    ) -> Bool {
        if indentation <= 3 {
            return true
        }
        return contexts.contains {
            indentation >= $0.contentIndent
                && indentation
                    <= $0.contentIndent + 3
        }
    }

    private static func updateListContexts(
        _ allContexts:
            inout [Int: [ListContext]],
        quoteDepth: Int,
        markerIndent: Int,
        contentIndent: Int
    ) {
        var contexts =
            allContexts[quoteDepth] ?? []
        contexts.removeAll {
            $0.markerIndent >= markerIndent
        }
        contexts.append(
            ListContext(
                markerIndent: markerIndent,
                contentIndent: contentIndent
            )
        )
        allContexts[quoteDepth] = contexts
    }

    private static func trimListContexts(
        _ allContexts:
            inout [Int: [ListContext]],
        quoteDepth: Int,
        indentation: Int
    ) {
        guard
            var contexts =
                allContexts[quoteDepth]
        else {
            return
        }
        contexts.removeAll {
            indentation
                <= $0.markerIndent
        }
        allContexts[quoteDepth] =
            contexts.isEmpty
            ? nil
            : contexts
    }

    private static func openingFence(
        in bytes: [UInt8],
        start: Int,
        end: Int
    ) -> Fence? {
        guard start < end else {
            return nil
        }
        let marker = bytes[start]
        guard
            marker
                == GitLabMarkdownTaskASCII
                    .backtick
                || marker
                    == GitLabMarkdownTaskASCII
                        .tilde
        else {
            return nil
        }
        let length = repeatedByteCount(
            marker,
            in: bytes,
            start: start,
            end: end
        )
        guard length >= 3 else {
            return nil
        }
        return Fence(
            marker: marker,
            minimumLength: length
        )
    }

    private static func isFence(
        in bytes: [UInt8],
        start: Int,
        end: Int,
        marker: UInt8,
        minimumLength: Int
    ) -> Bool {
        let length = repeatedByteCount(
            marker,
            in: bytes,
            start: start,
            end: end
        )
        guard length >= minimumLength else {
            return false
        }
        return bytes[
            min(start + length, end)..<end
        ].allSatisfy {
            GitLabMarkdownTaskASCII
                .isHorizontalWhitespace($0)
        }
    }

    private static func repeatedByteCount(
        _ byte: UInt8,
        in bytes: [UInt8],
        start: Int,
        end: Int
    ) -> Int {
        var cursor = start
        while
            cursor < end,
            bytes[cursor] == byte
        {
            cursor += 1
        }
        return cursor - start
    }

    private static func nextColumn(
        after byte: UInt8,
        current: Int
    ) -> Int {
        guard
            byte
                == GitLabMarkdownTaskASCII.tab
        else {
            return current + 1
        }
        return current + 4 - current % 4
    }

    private static func nextLineStart(
        after lineEnd: Int,
        in bytes: [UInt8]
    ) -> Int {
        guard lineEnd < bytes.count else {
            return bytes.count
        }
        if
            bytes[lineEnd]
                == GitLabMarkdownTaskASCII
                    .carriageReturn,
            lineEnd + 1 < bytes.count,
            bytes[lineEnd + 1]
                == GitLabMarkdownTaskASCII
                    .lineFeed
        {
            return lineEnd + 2
        }
        return lineEnd + 1
    }

    private static func
        bytesMaskingHTMLComments(
            _ source: [UInt8]
        ) -> [UInt8]
    {
        var result = source
        var cursor = 0
        var isInsideComment = false

        while cursor < result.count {
            if
                !isInsideComment,
                matches(
                    [0x3C, 0x21, 0x2D, 0x2D],
                    in: result,
                    at: cursor
                )
            {
                isInsideComment = true
                mask(
                    count: 4,
                    in: &result,
                    at: cursor
                )
                cursor += 4
                continue
            }

            if
                isInsideComment,
                matches(
                    [0x2D, 0x2D, 0x3E],
                    in: result,
                    at: cursor
                )
            {
                mask(
                    count: 3,
                    in: &result,
                    at: cursor
                )
                isInsideComment = false
                cursor += 3
                continue
            }

            if
                isInsideComment,
                !GitLabMarkdownTaskASCII
                    .isLineEnding(
                        result[cursor]
                    )
            {
                result[cursor] =
                    GitLabMarkdownTaskASCII.space
            }
            cursor += 1
        }
        return result
    }

    private static func matches(
        _ sequence: [UInt8],
        in bytes: [UInt8],
        at offset: Int
    ) -> Bool {
        guard
            offset >= 0,
            offset + sequence.count
                <= bytes.count
        else {
            return false
        }
        for index in sequence.indices
        where bytes[offset + index]
            != sequence[index]
        {
            return false
        }
        return true
    }

    private static func mask(
        count: Int,
        in bytes: inout [UInt8],
        at offset: Int
    ) {
        for index in 0..<count
        where offset + index < bytes.count
        {
            bytes[offset + index] =
                GitLabMarkdownTaskASCII.space
        }
    }
}
