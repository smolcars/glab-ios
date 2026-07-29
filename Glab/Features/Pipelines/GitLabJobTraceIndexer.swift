import CryptoKit
import Foundation

nonisolated enum GitLabJobTraceIndexingError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case invalidFile
    case tooManyLines
    case storageFailure

    var description: String {
        switch self {
        case .invalidFile:
            "The job log file was invalid."
        case .tooManyLines:
            "The job log has too many lines to open safely."
        case .storageFailure:
            "The job log index could not be stored securely."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }
}

nonisolated struct GitLabJobTraceIndexer:
    Sendable
{
    static let maximumTraceByteCount =
        110 * 1_024 * 1_024
    static let maximumLineCount =
        5_000_000
    static let maximumRenderedLineByteCount =
        32 * 1_024

    private static let indexBufferByteCount =
        64 * 1_024

    private let maximumTraceByteCount: Int
    private let maximumLineCount: Int
    private let chunkByteCount: Int
    private let chunkCheckpoint:
        (@Sendable () async -> Void)?

    init(
        maximumTraceByteCount: Int =
            GitLabJobTraceIndexer
            .maximumTraceByteCount,
        maximumLineCount: Int =
            GitLabJobTraceIndexer
            .maximumLineCount,
        chunkByteCount: Int =
            64 * 1_024,
        chunkCheckpoint:
            (@Sendable () async -> Void)?
            = nil
    ) {
        self.maximumTraceByteCount =
            max(0, maximumTraceByteCount)
        self.maximumLineCount =
            max(0, maximumLineCount)
        self.chunkByteCount =
            max(1, chunkByteCount)
        self.chunkCheckpoint =
            chunkCheckpoint
    }

    @concurrent
    func prepare(
        traceFileURL: URL,
        byteCount: Int,
        in workspace:
            GitLabJobTraceImportWorkspace
    ) async throws
        -> GitLabJobTracePreparedEntry
    {
        try Task.checkCancellation()
        try validate(
            traceFileURL: traceFileURL,
            byteCount: byteCount,
            workspace: workspace
        )

        let indexFileURL =
            workspace.directoryURL.appending(
                path:
                    ".glab-index-"
                    + UUID().uuidString,
                directoryHint: .notDirectory
            )
        let fileManager = FileManager.default
        guard
            fileManager.createFile(
                atPath: indexFileURL.path,
                contents: nil,
                attributes: [
                    .protectionKey:
                        FileProtectionType
                        .completeUntilFirstUserAuthentication,
                ]
            )
        else {
            throw GitLabJobTraceIndexingError
                .storageFailure
        }

        do {
            try excludeFromBackup(
                indexFileURL
            )
            let traceHandle =
                try FileHandle(
                    forReadingFrom:
                        traceFileURL
                )
            defer {
                try? traceHandle.close()
            }
            let indexHandle =
                try FileHandle(
                    forWritingTo:
                        indexFileURL
                )
            defer {
                try? indexHandle.close()
            }

            var hasher = SHA256()
            var indexBuffer = Data()
            indexBuffer.reserveCapacity(
                Self.indexBufferByteCount
            )
            var observedByteCount = 0
            var lineCount = 0
            var longLineCount = 0
            var pendingLineStart:
                UInt32?
            var currentLineByteCount = 0
            var currentLineLastByte:
                UInt8?
            var currentLinePrefix = Data()
            currentLinePrefix
                .reserveCapacity(
                    Self
                    .maximumRenderedLineByteCount
                )
            var firstLikelyFailure:
                GitLabJobTraceFailureLocation?

            func flushIndexBuffer()
                throws
            {
                guard !indexBuffer.isEmpty
                else {
                    return
                }
                try indexHandle.write(
                    contentsOf: indexBuffer
                )
                indexBuffer.removeAll(
                    keepingCapacity: true
                )
            }

            func appendOffset(
                _ offset: UInt32
            ) throws {
                guard
                    lineCount
                        < maximumLineCount
                else {
                    throw
                        GitLabJobTraceIndexingError
                        .tooManyLines
                }
                var value =
                    offset.littleEndian
                withUnsafeBytes(of: &value) {
                    indexBuffer.append(
                        contentsOf: $0
                    )
                }
                lineCount += 1
                if
                    indexBuffer.count
                        >= Self
                        .indexBufferByteCount
                {
                    try flushIndexBuffer()
                }
            }

            func finalizeCurrentLine() {
                let stripsCarriageReturn =
                    currentLineLastByte
                        == 0x0D
                let presentationByteCount =
                    max(
                        0,
                        currentLineByteCount
                            - (
                                stripsCarriageReturn
                                ? 1
                                : 0
                            )
                    )
                if
                    presentationByteCount
                        > Self
                        .maximumRenderedLineByteCount
                {
                    longLineCount += 1
                }

                var prefix =
                    currentLinePrefix
                if
                    stripsCarriageReturn,
                    prefix.last == 0x0D
                {
                    prefix.removeLast()
                }
                if
                    firstLikelyFailure
                        == nil,
                    Self
                        .mightContainFailureMarker(
                            currentLinePrefix
                        )
                {
                    let sanitized =
                        GitLabTerminalSanitizer
                        .sanitize(prefix)
                    if
                        let category =
                            Self
                            .failureCategory(
                                in: sanitized
                            )
                    {
                        firstLikelyFailure =
                            GitLabJobTraceFailureLocation(
                                lineIndex:
                                    lineCount
                                    - 1,
                                category:
                                    category
                            )
                    }
                }

                currentLineByteCount = 0
                currentLineLastByte = nil
                currentLinePrefix.removeAll(
                    keepingCapacity: true
                )
            }

            while
                let chunk =
                    try traceHandle.read(
                        upToCount:
                            chunkByteCount
                    ),
                !chunk.isEmpty
            {
                try Task.checkCancellation()
                if let chunkCheckpoint {
                    await chunkCheckpoint()
                    try Task
                        .checkCancellation()
                }
                hasher.update(data: chunk)

                for byte in chunk {
                    if lineCount == 0 {
                        try appendOffset(0)
                    } else if
                        let nextLineStart =
                            pendingLineStart
                    {
                        try appendOffset(
                            nextLineStart
                        )
                        pendingLineStart = nil
                    }

                    if byte == 0x0A {
                        finalizeCurrentLine()
                        pendingLineStart =
                            UInt32(
                                observedByteCount
                                    + 1
                            )
                    } else {
                        currentLineByteCount += 1
                        currentLineLastByte =
                            byte
                        if
                            currentLinePrefix
                                .count
                                < Self
                                .maximumRenderedLineByteCount
                        {
                            currentLinePrefix
                                .append(byte)
                        }
                    }
                    observedByteCount += 1
                }
            }

            guard
                observedByteCount
                    == byteCount
            else {
                throw
                    GitLabJobTraceIndexingError
                    .invalidFile
            }
            if
                observedByteCount > 0,
                pendingLineStart == nil
            {
                finalizeCurrentLine()
            }
            try Task.checkCancellation()
            try flushIndexBuffer()
            try indexHandle.synchronize()
            try Task.checkCancellation()

            return GitLabJobTracePreparedEntry(
                traceFileURL:
                    traceFileURL,
                indexFileURL:
                    indexFileURL,
                byteCount: byteCount,
                lineCount: lineCount,
                rawContentDigest:
                    Self.digest(
                        hasher.finalize()
                    ),
                indexFormatVersion:
                    GitLabJobTraceIndexFormat
                    .currentVersion,
                longLineCount:
                    longLineCount,
                firstLikelyFailure:
                    firstLikelyFailure
            )
        } catch is CancellationError {
            try? fileManager.removeItem(
                at: indexFileURL
            )
            throw CancellationError()
        } catch
            let error
                as GitLabJobTraceIndexingError
        {
            try? fileManager.removeItem(
                at: indexFileURL
            )
            throw error
        } catch {
            try? fileManager.removeItem(
                at: indexFileURL
            )
            throw GitLabJobTraceIndexingError
                .storageFailure
        }
    }

    private func validate(
        traceFileURL: URL,
        byteCount: Int,
        workspace:
            GitLabJobTraceImportWorkspace
    ) throws {
        guard
            byteCount >= 0,
            byteCount
                <= maximumTraceByteCount,
            UInt64(byteCount)
                <= UInt64(UInt32.max),
            maximumLineCount > 0,
            traceFileURL.isFileURL,
            traceFileURL
                .standardizedFileURL
                .deletingLastPathComponent()
                == workspace
                .directoryURL
                .standardizedFileURL,
            traceFileURL
                .deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == workspace
                .directoryURL
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceIndexingError
                .invalidFile
        }
        let values =
            try traceFileURL.resourceValues(
                forKeys: [
                    .fileSizeKey,
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                ]
            )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            values.fileSize == byteCount
        else {
            throw GitLabJobTraceIndexingError
                .invalidFile
        }
    }

    private func excludeFromBackup(
        _ fileURL: URL
    ) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = fileURL
        try protectedURL
            .setResourceValues(values)
    }

    private static func failureCategory(
        in line: String
    ) -> GitLabJobTraceFailureCategory? {
        let markers: [
            (
                GitLabJobTraceFailureCategory,
                String
            )
        ] = [
            (.error, "error:"),
            (.fatal, "fatal:"),
            (.panic, "panic:"),
            (.exception, "exception"),
            (.failed, "failed"),
            (.traceback, "traceback"),
        ]
        for (category, marker) in markers
        where
            line.range(
                of: marker,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive,
                ]
            ) != nil
        {
            return category
        }
        return nil
    }

    private static func
        mightContainFailureMarker(
            _ bytes: Data
        ) -> Bool
    {
        bytes.withUnsafeBytes {
            rawBuffer in
            let buffer =
                rawBuffer.bindMemory(
                    to: UInt8.self
                )
            for index in buffer.indices {
                let byte = buffer[index]
                if
                    byte < 0x20
                        || byte == 0x7F
                        || byte >= 0x80
                {
                    return true
                }
                switch asciiLowercased(
                    byte
                ) {
                case 0x65:
                    if
                        matchesASCII(
                            [0x65, 0x72, 0x72, 0x6F, 0x72, 0x3A],
                            in: buffer,
                            at: index
                        )
                        || matchesASCII(
                            [0x65, 0x78, 0x63, 0x65, 0x70, 0x74, 0x69, 0x6F, 0x6E],
                            in: buffer,
                            at: index
                        )
                    {
                        return true
                    }
                case 0x66:
                    if
                        matchesASCII(
                            [0x66, 0x61, 0x74, 0x61, 0x6C, 0x3A],
                            in: buffer,
                            at: index
                        )
                        || matchesASCII(
                            [0x66, 0x61, 0x69, 0x6C, 0x65, 0x64],
                            in: buffer,
                            at: index
                        )
                    {
                        return true
                    }
                case 0x70:
                    if
                        matchesASCII(
                            [0x70, 0x61, 0x6E, 0x69, 0x63, 0x3A],
                            in: buffer,
                            at: index
                        )
                    {
                        return true
                    }
                case 0x74:
                    if
                        matchesASCII(
                            [0x74, 0x72, 0x61, 0x63, 0x65, 0x62, 0x61, 0x63, 0x6B],
                            in: buffer,
                            at: index
                        )
                    {
                        return true
                    }
                default:
                    continue
                }
            }
            return false
        }
    }

    private static func matchesASCII(
        _ marker: [UInt8],
        in bytes:
            UnsafeBufferPointer<UInt8>,
        at start: Int
    ) -> Bool {
        guard
            start + marker.count
                <= bytes.count
        else {
            return false
        }
        for offset in marker.indices
        where
            asciiLowercased(
                bytes[start + offset]
            ) != marker[offset]
        {
            return false
        }
        return true
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

    private static func digest(
        _ digest: SHA256.Digest
    ) -> String {
        digest.map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
