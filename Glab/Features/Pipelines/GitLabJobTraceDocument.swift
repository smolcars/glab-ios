import Foundation

nonisolated struct GitLabJobTraceLine:
    Equatable,
    Identifiable,
    Sendable
{
    let index: Int
    let text: String
    let rawByteCount: Int
    let isTruncated: Bool

    var id: Int {
        index
    }

    var displayNumber: Int {
        index + 1
    }
}

nonisolated struct GitLabJobTraceSearchResult:
    Equatable,
    Sendable
{
    let lineIndexes: [Int]
    let selectedMatchPosition: Int?
    let hasAdditionalMatches: Bool

    static let empty =
        GitLabJobTraceSearchResult(
            lineIndexes: [],
            selectedMatchPosition: nil,
            hasAdditionalMatches: false
        )
}

nonisolated struct GitLabJobTraceCacheMetrics:
    Equatable,
    Sendable
{
    let lineCount: Int
    let byteCount: Int
}

nonisolated enum GitLabJobTraceDocumentError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case invalidRange
    case invalidFile

    var description: String {
        switch self {
        case .invalidRange:
            "The requested job log lines were invalid."
        case .invalidFile:
            "The cached job log was invalid."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated protocol GitLabJobTraceReading:
    Sendable
{
    func lines(
        in range: Range<Int>,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) async throws
        -> [GitLabJobTraceLine]

    func search(
        _ query: String,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) async throws
        -> GitLabJobTraceSearchResult
}

actor GitLabJobTraceDocument {
    static let maximumVisibleWindowLineCount =
        512
    static let maximumCachedLineCount =
        2_000
    static let maximumCachedByteCount =
        8 * 1_024 * 1_024
    static let maximumSearchQueryByteCount =
        256
    static let maximumSearchResultCount =
        2_000

    nonisolated let lineCount: Int

    private struct CachedLine {
        let line: GitLabJobTraceLine
        let byteCount: Int
        var lastAccess: UInt64
    }

    private struct WindowLoad {
        let id: UUID
        let range: Range<Int>
        let generation: UInt64
        let task:
            Task<
                [GitLabJobTraceLine],
                any Error
            >
    }

    private let descriptor:
        GitLabJobTraceDescriptor
    private let reader:
        any GitLabJobTraceReading
    private let maximumCachedLineCount:
        Int
    private let maximumCachedByteCount:
        Int
    private var cachedLines:
        [Int: CachedLine] = [:]
    private var cachedByteCount = 0
    private var accessCounter: UInt64 = 0
    private var generation: UInt64 = 0
    private var windowLoad: WindowLoad?
    private var searchGeneration:
        UInt64 = 0
    private var searchTask:
        Task<
            GitLabJobTraceSearchResult,
            any Error
        >?

    init(
        descriptor:
            GitLabJobTraceDescriptor,
        reader:
            any GitLabJobTraceReading =
            GitLabJobTraceFileReader(),
        maximumCachedLineCount: Int =
            GitLabJobTraceDocument
            .maximumCachedLineCount,
        maximumCachedByteCount: Int =
            GitLabJobTraceDocument
            .maximumCachedByteCount
    ) {
        self.descriptor = descriptor
        self.reader = reader
        self.maximumCachedLineCount =
            min(
                max(
                    0,
                    maximumCachedLineCount
                ),
                Self
                    .maximumCachedLineCount
            )
        self.maximumCachedByteCount =
            min(
                max(
                    0,
                    maximumCachedByteCount
                ),
                Self
                    .maximumCachedByteCount
            )
        lineCount =
            max(0, descriptor.lineCount)
    }

    func lines(
        in range: Range<Int>
    ) async throws
        -> [GitLabJobTraceLine]
    {
        guard
            range.lowerBound >= 0,
            range.upperBound <= lineCount,
            range.count
                <= Self
                .maximumVisibleWindowLineCount
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidRange
        }
        guard !range.isEmpty else {
            return []
        }

        while true {
            try Task.checkCancellation()
            if
                let cached =
                    cachedWindow(
                        in: range
                    )
            {
                return cached
            }

            let load: WindowLoad
            if let existing = windowLoad {
                load = existing
            } else {
                guard
                    let missingRange =
                        firstMissingRange(
                            in: range
                        )
                else {
                    continue
                }
                let id = UUID()
                let loadGeneration =
                    generation
                let descriptor =
                    descriptor
                let reader = reader
                let task = Task {
                    try await reader.lines(
                        in: missingRange,
                        descriptor:
                            descriptor,
                        maximumLineByteCount:
                            GitLabJobTraceIndexer
                            .maximumRenderedLineByteCount
                    )
                }
                load = WindowLoad(
                    id: id,
                    range:
                        missingRange,
                    generation:
                        loadGeneration,
                    task: task
                )
                windowLoad = load
            }

            let loaded: [
                GitLabJobTraceLine
            ]
            do {
                loaded =
                    try await load
                    .task.value
            } catch {
                if
                    windowLoad?.id
                        == load.id
                {
                    windowLoad = nil
                }
                if
                    load.generation
                        != generation
                        || error
                            is CancellationError
                {
                    throw CancellationError()
                }
                throw error
            }
            try Task.checkCancellation()
            guard
                load.generation
                    == generation
            else {
                throw CancellationError()
            }
            if
                windowLoad?.id
                    == load.id
            {
                windowLoad = nil
            }
            guard
                Self.isValid(
                    loaded,
                    for: load.range
                )
            else {
                throw
                    GitLabJobTraceDocumentError
                    .invalidFile
            }
            for line in loaded {
                cache(line)
            }
        }
    }

    func search(
        _ query: String
    ) async throws
        -> GitLabJobTraceSearchResult
    {
        searchTask?.cancel()
        searchTask = nil
        searchGeneration &+= 1
        let currentGeneration =
            searchGeneration

        guard
            !query
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
        else {
            return .empty
        }
        guard
            query.utf8.count
                <= Self
                .maximumSearchQueryByteCount
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidRange
        }

        let descriptor = descriptor
        let reader = reader
        let task = Task {
            try await reader.search(
                query,
                descriptor: descriptor,
                maximumLineByteCount:
                    GitLabJobTraceIndexer
                    .maximumRenderedLineByteCount,
                maximumResultCount:
                    Self
                    .maximumSearchResultCount
            )
        }
        searchTask = task

        do {
            let result =
                try await task.value
            try Task.checkCancellation()
            guard
                currentGeneration
                    == searchGeneration
            else {
                throw CancellationError()
            }
            searchTask = nil
            return result
        } catch {
            if
                currentGeneration
                    == searchGeneration
            {
                searchTask = nil
            }
            if
                currentGeneration
                    != searchGeneration
                    || error
                        is CancellationError
            {
                throw CancellationError()
            }
            throw error
        }
    }

    func invalidate() {
        generation &+= 1
        searchGeneration &+= 1
        windowLoad?.task.cancel()
        windowLoad = nil
        searchTask?.cancel()
        searchTask = nil
        cachedLines.removeAll()
        cachedByteCount = 0
    }

    func cacheMetrics()
        -> GitLabJobTraceCacheMetrics
    {
        GitLabJobTraceCacheMetrics(
            lineCount:
                cachedLines.count,
            byteCount:
                cachedByteCount
        )
    }

    private func cachedWindow(
        in range: Range<Int>
    ) -> [GitLabJobTraceLine]? {
        guard
            range.allSatisfy({
                cachedLines[$0] != nil
            })
        else {
            return nil
        }

        return range.compactMap {
            index in
            accessCounter &+= 1
            cachedLines[index]?
                .lastAccess =
                accessCounter
            return
                cachedLines[index]?
                .line
        }
    }

    private func firstMissingRange(
        in range: Range<Int>
    ) -> Range<Int>? {
        guard
            let firstMissing =
                range.first(
                    where: {
                        cachedLines[$0]
                            == nil
                    }
                )
        else {
            return nil
        }
        var upperBound =
            firstMissing + 1
        while
            upperBound
                < range.upperBound,
            cachedLines[upperBound]
                == nil
        {
            upperBound += 1
        }
        return firstMissing..<upperBound
    }

    private static func isValid(
        _ lines: [GitLabJobTraceLine],
        for range: Range<Int>
    ) -> Bool {
        guard
            lines.count == range.count
        else {
            return false
        }
        for (offset, line)
        in lines.enumerated()
        where
            line.index
                != range.lowerBound + offset
                || line.rawByteCount < 0
        {
            return false
        }
        return true
    }

    private func cache(
        _ line: GitLabJobTraceLine
    ) {
        guard
            line.index >= 0,
            line.index < lineCount
        else {
            return
        }
        if
            let existing =
                cachedLines
                .removeValue(
                    forKey: line.index
                )
        {
            cachedByteCount -=
                existing.byteCount
        }
        accessCounter &+= 1
        let cost = line.text.utf8.count
        cachedLines[line.index] =
            CachedLine(
                line: line,
                byteCount: cost,
                lastAccess:
                    accessCounter
            )
        cachedByteCount += cost
        pruneCache()
    }

    private func pruneCache() {
        while
            cachedLines.count
                > maximumCachedLineCount
                || cachedByteCount
                    > maximumCachedByteCount
        {
            guard
                let oldest =
                    cachedLines.min(
                        by: {
                            $0.value
                                .lastAccess
                                < $1.value
                                .lastAccess
                        }
                    )
            else {
                return
            }
            cachedLines.removeValue(
                forKey: oldest.key
            )
            cachedByteCount -=
                oldest.value.byteCount
        }
    }
}

nonisolated struct GitLabJobTraceFileReader:
    GitLabJobTraceReading
{
    private static let readChunkByteCount =
        64 * 1_024

    @concurrent
    func lines(
        in range: Range<Int>,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int
    ) async throws
        -> [GitLabJobTraceLine]
    {
        do {
            try Task.checkCancellation()
            try Self.validate(
                descriptor
            )
            guard
                range.lowerBound >= 0,
                range.upperBound
                    <= descriptor.lineCount,
                range.count
                    <= GitLabJobTraceDocument
                    .maximumVisibleWindowLineCount,
                maximumLineByteCount > 0,
                maximumLineByteCount
                    <= GitLabJobTraceIndexer
                    .maximumRenderedLineByteCount
            else {
                throw
                    GitLabJobTraceDocumentError
                    .invalidRange
            }
            guard !range.isEmpty else {
                return []
            }

            let indexHandle =
                try FileHandle(
                    forReadingFrom:
                        descriptor
                        .indexFileURL
                )
            defer {
                try? indexHandle.close()
            }
            let traceHandle =
                try FileHandle(
                    forReadingFrom:
                        descriptor
                        .traceFileURL
                )
            defer {
                try? traceHandle.close()
            }

            let offsetCount =
                range.count
                + (
                    range.upperBound
                        < descriptor.lineCount
                    ? 1
                    : 0
                )
            try indexHandle.seek(
                toOffset:
                    UInt64(
                        range.lowerBound
                        * GitLabJobTraceIndexFormat
                        .offsetByteCount
                    )
            )
            let offsetData =
                try Self.readExactly(
                    offsetCount
                        * GitLabJobTraceIndexFormat
                        .offsetByteCount,
                    from: indexHandle
                )
            var offsets =
                try Self.decodeOffsets(
                    offsetData
                )
            if
                range.upperBound
                    == descriptor.lineCount
            {
                offsets.append(
                    UInt32(
                        descriptor.byteCount
                    )
                )
            }
            guard
                offsets.count
                    == range.count + 1
            else {
                throw
                    GitLabJobTraceDocumentError
                    .invalidFile
            }
            let firstOffset =
                Int(
                    offsets[0]
                )
            if range.lowerBound == 0 {
                guard firstOffset == 0 else {
                    throw
                        GitLabJobTraceDocumentError
                        .invalidFile
                }
            } else {
                guard firstOffset > 0 else {
                    throw
                        GitLabJobTraceDocumentError
                        .invalidFile
                }
                try traceHandle.seek(
                    toOffset:
                        UInt64(
                            firstOffset - 1
                        )
                )
                guard
                    try Self.readExactly(
                        1,
                        from: traceHandle
                    ).first == 0x0A
                else {
                    throw
                        GitLabJobTraceDocumentError
                        .invalidFile
                }
            }

            var result: [
                GitLabJobTraceLine
            ] = []
            result.reserveCapacity(
                range.count
            )
            for position in 0..<range.count {
                try Task.checkCancellation()
                result.append(
                    try Self.readLine(
                        index:
                            range.lowerBound
                            + position,
                        start:
                            Int(
                                offsets[
                                    position
                                ]
                            ),
                        end:
                            Int(
                                offsets[
                                    position
                                    + 1
                                ]
                            ),
                        isLastLine:
                            range.lowerBound
                            + position
                            == descriptor
                            .lineCount
                            - 1,
                        maximumLineByteCount:
                            maximumLineByteCount,
                        traceHandle:
                            traceHandle
                    )
                )
            }
            return result
        } catch is CancellationError {
            throw CancellationError()
        } catch
            let error
                as GitLabJobTraceDocumentError
        {
            throw error
        } catch {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
    }

    @concurrent
    func search(
        _ query: String,
        descriptor:
            GitLabJobTraceDescriptor,
        maximumLineByteCount: Int,
        maximumResultCount: Int
    ) async throws
        -> GitLabJobTraceSearchResult
    {
        do {
            try Task.checkCancellation()
            try Self.validate(
                descriptor
            )
            guard
                maximumLineByteCount > 0,
                maximumLineByteCount
                    <= GitLabJobTraceIndexer
                    .maximumRenderedLineByteCount,
                maximumResultCount > 0,
                maximumResultCount
                    <= GitLabJobTraceDocument
                    .maximumSearchResultCount,
                query.utf8.count
                    <= GitLabJobTraceDocument
                    .maximumSearchQueryByteCount
            else {
                throw
                    GitLabJobTraceDocumentError
                    .invalidRange
            }
            guard
                !query
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )
                .isEmpty
            else {
                return .empty
            }

            let traceHandle =
                try FileHandle(
                    forReadingFrom:
                        descriptor
                        .traceFileURL
                )
            defer {
                try? traceHandle.close()
            }

            var matches: [Int] = []
            matches.reserveCapacity(
                min(
                    maximumResultCount,
                    descriptor.lineCount
                )
            )
            var lineIndex = 0
            var linePrefix = Data()
            linePrefix.reserveCapacity(
                maximumLineByteCount
            )
            var lastLineByte: UInt8?
            var lastTraceByte: UInt8?
            var didFindAdditional = false
            let asciiQuery =
                Self.asciiSearchNeedle(
                    query
                )

            func inspectLine() -> Bool {
                if
                    lastLineByte == 0x0D,
                    linePrefix.last == 0x0D
                {
                    linePrefix.removeLast()
                }
                if
                    let asciiQuery,
                    Self
                        .printableASCIIMatch(
                            asciiQuery,
                            in: linePrefix
                        ) == false
                {
                    lineIndex += 1
                    linePrefix.removeAll(
                        keepingCapacity: true
                    )
                    lastLineByte = nil
                    return false
                }
                let line =
                    GitLabTerminalSanitizer
                    .sanitize(linePrefix)
                if
                    line.range(
                        of: query,
                        options: [
                            .caseInsensitive,
                            .diacriticInsensitive,
                        ]
                    ) != nil
                {
                    if
                        matches.count
                            < maximumResultCount
                    {
                        matches.append(
                            lineIndex
                        )
                    } else {
                        didFindAdditional = true
                    }
                }
                lineIndex += 1
                linePrefix.removeAll(
                    keepingCapacity: true
                )
                lastLineByte = nil
                return didFindAdditional
            }

            searchLoop: while
                let chunk =
                    try traceHandle.read(
                        upToCount:
                            Self
                            .readChunkByteCount
                    ),
                !chunk.isEmpty
            {
                try Task.checkCancellation()
                for byte in chunk {
                    lastTraceByte = byte
                    if byte == 0x0A {
                        if inspectLine() {
                            break searchLoop
                        }
                    } else {
                        lastLineByte = byte
                        if
                            linePrefix.count
                                < maximumLineByteCount
                        {
                            linePrefix.append(
                                byte
                            )
                        }
                    }
                }
            }
            if
                !didFindAdditional,
                descriptor.byteCount > 0,
                lastTraceByte != 0x0A
            {
                _ = inspectLine()
            }
            if
                !didFindAdditional,
                lineIndex
                    != descriptor.lineCount
            {
                throw
                    GitLabJobTraceDocumentError
                    .invalidFile
            }
            try Task.checkCancellation()
            return GitLabJobTraceSearchResult(
                lineIndexes: matches,
                selectedMatchPosition:
                    matches.isEmpty
                    ? nil
                    : 0,
                hasAdditionalMatches:
                    didFindAdditional
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch
            let error
                as GitLabJobTraceDocumentError
        {
            throw error
        } catch {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
    }

    private static func asciiSearchNeedle(
        _ query: String
    ) -> [UInt8]? {
        let bytes = Array(query.utf8)
        guard
            !bytes.isEmpty,
            bytes.allSatisfy({
                $0 >= 0x20
                    && $0 < 0x7F
            })
        else {
            return nil
        }
        return bytes.map(
            asciiLowercased
        )
    }

    private static func printableASCIIMatch(
        _ needle: [UInt8],
        in bytes: Data
    ) -> Bool? {
        bytes.withUnsafeBytes {
            rawBuffer in
            let buffer =
                rawBuffer.bindMemory(
                    to: UInt8.self
                )
            guard
                needle.count
                    <= buffer.count
            else {
                for byte in buffer
                where
                    byte < 0x20
                        || byte >= 0x7F
                {
                    return nil
                }
                return false
            }
            let finalStart =
                buffer.count
                - needle.count
            for start in buffer.indices {
                let byte = buffer[start]
                guard
                    byte >= 0x20,
                    byte < 0x7F
                else {
                    return nil
                }
                guard
                    start <= finalStart,
                    asciiLowercased(byte)
                        == needle[0]
                else {
                    continue
                }
                var matched = true
                for offset in 1..<needle.count
                where
                    asciiLowercased(
                        buffer[
                            start + offset
                        ]
                    ) != needle[offset]
                {
                    matched = false
                    break
                }
                if matched {
                    return true
                }
            }
            return false
        }
    }

    private static func asciiLowercased(
        _ byte: UInt8
    ) -> UInt8 {
        if
            byte >= 0x41,
            byte <= 0x5A
        {
            return byte + 0x20
        }
        return byte
    }

    private static func validate(
        _ descriptor:
            GitLabJobTraceDescriptor
    ) throws {
        guard
            descriptor.byteCount >= 0,
            descriptor.byteCount
                <= GitLabJobTraceIndexer
                .maximumTraceByteCount,
            descriptor.lineCount >= 0,
            descriptor.lineCount
                <= GitLabJobTraceIndexer
                .maximumLineCount,
            (descriptor.byteCount == 0)
                == (descriptor.lineCount == 0)
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        try validateFile(
            descriptor.traceFileURL,
            expectedByteCount:
                descriptor.byteCount
        )
        try validateFile(
            descriptor.indexFileURL,
            expectedByteCount:
                descriptor.lineCount
                * GitLabJobTraceIndexFormat
                .offsetByteCount
        )
    }

    private static func validateFile(
        _ fileURL: URL,
        expectedByteCount: Int
    ) throws {
        let values =
            try fileURL.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.fileSize
                == expectedByteCount
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
    }

    private static func decodeOffsets(
        _ data: Data
    ) throws -> [UInt32] {
        guard
            data.count
                % GitLabJobTraceIndexFormat
                .offsetByteCount
                == 0
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        var result: [UInt32] = []
        result.reserveCapacity(
            data.count
            / GitLabJobTraceIndexFormat
                .offsetByteCount
        )
        var index = 0
        while index < data.count {
            result.append(
                UInt32(data[index])
                    | UInt32(
                        data[index + 1]
                    ) << 8
                    | UInt32(
                        data[index + 2]
                    ) << 16
                    | UInt32(
                        data[index + 3]
                    ) << 24
            )
            index +=
                GitLabJobTraceIndexFormat
                .offsetByteCount
        }
        return result
    }

    private static func readLine(
        index: Int,
        start: Int,
        end: Int,
        isLastLine: Bool,
        maximumLineByteCount: Int,
        traceHandle: FileHandle
    ) throws -> GitLabJobTraceLine {
        guard
            start >= 0,
            end > start
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        let rawRangeByteCount =
            end - start
        let tailByteCount =
            min(2, rawRangeByteCount)
        try traceHandle.seek(
            toOffset:
                UInt64(
                    end - tailByteCount
                )
        )
        let tail =
            try readExactly(
                tailByteCount,
                from: traceHandle
            )
        let hasLineFeed =
            tail.last == 0x0A
        guard
            isLastLine || hasLineFeed
        else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        var contentByteCount =
            rawRangeByteCount
        if hasLineFeed {
            contentByteCount -= 1
        }
        let carriageReturnIndex =
            tail.count
            - (
                hasLineFeed
                ? 2
                : 1
            )
        if
            carriageReturnIndex >= 0,
            tail[carriageReturnIndex]
                == 0x0D
        {
            contentByteCount -= 1
        }
        guard contentByteCount >= 0 else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        let displayedByteCount =
            min(
                contentByteCount,
                maximumLineByteCount
            )
        try traceHandle.seek(
            toOffset: UInt64(start)
        )
        let prefix =
            try readExactly(
                displayedByteCount,
                from: traceHandle
            )
        return GitLabJobTraceLine(
            index: index,
            text:
                GitLabTerminalSanitizer
                .sanitize(prefix),
            rawByteCount:
                contentByteCount,
            isTruncated:
                contentByteCount
                > maximumLineByteCount
        )
    }

    private static func readExactly(
        _ byteCount: Int,
        from handle: FileHandle
    ) throws -> Data {
        guard byteCount >= 0 else {
            throw
                GitLabJobTraceDocumentError
                .invalidFile
        }
        guard byteCount > 0 else {
            return Data()
        }
        var result = Data()
        result.reserveCapacity(byteCount)
        while result.count < byteCount {
            let remaining =
                byteCount - result.count
            guard
                let chunk =
                    try handle.read(
                        upToCount:
                            remaining
                    ),
                !chunk.isEmpty
            else {
                throw
                    GitLabJobTraceDocumentError
                    .invalidFile
            }
            result.append(chunk)
        }
        return result
    }
}
