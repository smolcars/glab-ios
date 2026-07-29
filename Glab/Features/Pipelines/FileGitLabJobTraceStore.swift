import CryptoKit
import Foundation

actor FileGitLabJobTraceStore:
    GitLabJobTraceStoring
{
    private struct StoredMetadata:
        Codable,
        Equatable,
        Sendable
    {
        let formatVersion: Int
        let keyDigest: String
        let byteCount: Int
        let lineCount: Int
        let indexByteCount: Int
        let indexFormatVersion: Int
        let rawContentDigest: String
        let indexContentDigest: String
        let longLineCount: Int
        let storedAt: Date
    }

    private struct MaintenanceEntry {
        let directoryURL: URL
        let logicalByteCount: Int
        let lastAccessedAt: Date
    }

    private struct EntrySnapshot: Equatable {
        let metadata: Data
        let directorySystemNumber: UInt64
        let directoryFileNumber: UInt64
    }

    static let maximumTraceByteCount =
        110 * 1_024 * 1_024
    static let maximumLineCount = 5_000_000
    static let defaultMaximumStoredByteCount =
        256 * 1_024 * 1_024

    private static let metadataFormatVersion =
        GitLabJobTraceStorageFormat.currentVersion
    private static let metadataMaximumByteCount =
        64 * 1_024
    private static let directoryName =
        "GlabGitLabJobTraceCache"
    private static let traceFileName = "trace.raw"
    private static let indexFileName = "lines.idx"
    private static let metadataFileName =
        "metadata.plist"

    private let rootDirectory: URL
    private let maximumStoredByteCount: Int
    private let currentDate: @Sendable () -> Date
    private let fileManager: FileManager
    private var activeWorkspaceDirectories:
        Set<URL> = []

    init(
        rootDirectory: URL =
            URL.cachesDirectory
            .appending(
                path:
                    FileGitLabJobTraceStore
                    .directoryName,
                directoryHint: .isDirectory
            )
            .appending(
                path: "v1",
                directoryHint: .isDirectory
            ),
        maximumStoredByteCount: Int =
            FileGitLabJobTraceStore
            .defaultMaximumStoredByteCount,
        currentDate:
            @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.maximumStoredByteCount =
            max(0, maximumStoredByteCount)
        self.currentDate = currentDate
        self.fileManager = fileManager
    }

    func prepare() async {
        do {
            try Task.checkCancellation()
            try createProtectedDirectory(
                rootDirectory,
                withIntermediateDirectories: true
            )
            let entries =
                try await maintainedEntries()
            try Task.checkCancellation()
            prune(entries)
        } catch {
            return
        }
    }

    func beginImport(
        for key: GitLabJobTraceKey
    ) throws -> GitLabJobTraceImportWorkspace {
        try Task.checkCancellation()
        let identifier = UUID()
        let accountDirectory =
            accountDirectory(for: key.accountID)
        let workspaceDirectory =
            workspaceDirectory(
                accountDirectory: accountDirectory,
                key: key,
                identifier: identifier
            )

        do {
            try createProtectedDirectory(
                rootDirectory,
                withIntermediateDirectories: true
            )
            try createProtectedDirectory(
                accountDirectory,
                withIntermediateDirectories: false
            )
            guard
                !fileManager.fileExists(
                    atPath: workspaceDirectory.path
                )
            else {
                throw GitLabJobTraceStoreError
                    .storage
            }
            try createProtectedDirectory(
                workspaceDirectory,
                withIntermediateDirectories: false
            )
            activeWorkspaceDirectories.insert(
                workspaceDirectory
                    .standardizedFileURL
            )
            return GitLabJobTraceImportWorkspace(
                key: key,
                directoryURL: workspaceDirectory,
                identifier: identifier
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try? fileManager.removeItem(
                at: workspaceDirectory
            )
            throw GitLabJobTraceStoreError.storage
        }
    }

    func commit(
        _ prepared: GitLabJobTracePreparedEntry,
        in workspace:
            GitLabJobTraceImportWorkspace,
        storedAt: Date? = nil
    ) async throws -> GitLabJobTraceDescriptor {
        do {
            try Task.checkCancellation()
            try validate(workspace)
            let ownedPrepared = try claim(
                prepared,
                in: workspace
            )
            let validated =
                try await GitLabJobTraceFileValidator
                .validate(
                    ownedPrepared,
                    inside: workspace.directoryURL,
                    maximumTraceByteCount:
                        Self.maximumTraceByteCount,
                    maximumLineCount:
                        Self.maximumLineCount
                )
            try Task.checkCancellation()
            try validate(workspace)

            try protectAndExcludeFromBackup(
                ownedPrepared.traceFileURL
            )
            try protectAndExcludeFromBackup(
                ownedPrepared.indexFileURL
            )

            let entryStoredAt =
                storedAt ?? currentDate()
            let metadata = StoredMetadata(
                formatVersion:
                    Self.metadataFormatVersion,
                keyDigest: Self.digest(
                    workspace.key.storageIdentifier
                ),
                byteCount: ownedPrepared.byteCount,
                lineCount: ownedPrepared.lineCount,
                indexByteCount:
                    validated.indexByteCount,
                indexFormatVersion:
                    ownedPrepared.indexFormatVersion,
                rawContentDigest:
                    ownedPrepared.rawContentDigest,
                indexContentDigest:
                    validated.indexContentDigest,
                longLineCount:
                    ownedPrepared.longLineCount,
                storedAt: entryStoredAt
            )
            let metadataURL =
                workspace.directoryURL.appending(
                    path: Self.metadataFileName,
                    directoryHint: .notDirectory
                )
            try persist(
                metadata,
                at: metadataURL
            )
            try protectAndExcludeFromBackup(
                workspace.directoryURL
            )
            try Task.checkCancellation()

            let entryURL = self.entryDirectory(
                for: workspace.key
            )
            try publish(
                workspace.directoryURL,
                at: entryURL
            )
            try fileManager.setAttributes(
                [.modificationDate: entryStoredAt],
                ofItemAtPath: entryURL.path
            )
            activeWorkspaceDirectories.remove(
                workspace.directoryURL
                    .standardizedFileURL
            )

            let publishedDescriptor = descriptor(
                metadata: metadata,
                key: workspace.key,
                entryURL: entryURL
            )
            if
                let entries =
                    try? publishedEntries()
            {
                prune(entries)
            }
            return publishedDescriptor
        } catch is CancellationError {
            discard(workspace)
            throw CancellationError()
        } catch
            let error as GitLabJobTraceStoreError
        {
            discard(workspace)
            throw error
        } catch {
            discard(workspace)
            throw GitLabJobTraceStoreError.storage
        }
    }

    func discard(
        _ workspace:
            GitLabJobTraceImportWorkspace
    ) {
        guard
            isExpectedWorkspace(workspace)
        else {
            return
        }
        activeWorkspaceDirectories.remove(
            workspace.directoryURL
                .standardizedFileURL
        )
        try? fileManager.removeItem(
            at: workspace.directoryURL
        )
    }

    func descriptor(
        for key: GitLabJobTraceKey
    ) async -> GitLabJobTraceDescriptor? {
        let entryURL = entryDirectory(for: key)
        let metadataURL = entryURL.appending(
            path: Self.metadataFileName,
            directoryHint: .notDirectory
        )

        for _ in 0..<3 {
            var entrySnapshot: EntrySnapshot?
            do {
                try validateDirectory(
                    entryURL,
                    expectedParent:
                        accountDirectory(
                            for: key.accountID
                        )
                )
                let metadataData =
                    try boundedRegularFileData(
                        at: metadataURL,
                        expectedParent: entryURL,
                        maximumByteCount:
                            Self.metadataMaximumByteCount
                    )
                entrySnapshot = try snapshot(
                    entryURL: entryURL,
                    metadata: metadataData
                )
                let metadata =
                    try decoder.decode(
                        StoredMetadata.self,
                        from: metadataData
                    )
                try validate(
                    metadata,
                    for: key
                )

                let prepared =
                    GitLabJobTracePreparedEntry(
                        traceFileURL:
                            entryURL.appending(
                                path:
                                    Self.traceFileName,
                                directoryHint:
                                    .notDirectory
                            ),
                        indexFileURL:
                            entryURL.appending(
                                path:
                                    Self.indexFileName,
                                directoryHint:
                                    .notDirectory
                            ),
                        byteCount:
                            metadata.byteCount,
                        lineCount:
                            metadata.lineCount,
                        rawContentDigest:
                            metadata
                            .rawContentDigest,
                        indexFormatVersion:
                            metadata
                            .indexFormatVersion,
                        longLineCount:
                            metadata.longLineCount
                    )
                let validated =
                    try await GitLabJobTraceFileValidator
                    .validate(
                        prepared,
                        inside: entryURL,
                        maximumTraceByteCount:
                            Self.maximumTraceByteCount,
                        maximumLineCount:
                            Self.maximumLineCount
                    )
                let currentSnapshot =
                    try currentSnapshot(
                        entryURL: entryURL,
                        metadataURL: metadataURL
                    )
                guard
                    currentSnapshot == entrySnapshot
                else {
                    continue
                }
                guard
                    validated.indexByteCount
                        == metadata.indexByteCount,
                    validated.indexContentDigest
                        == metadata.indexContentDigest
                else {
                    throw GitLabJobTraceStoreError
                        .invalidEntry
                }

                let accessedAt = currentDate()
                try? fileManager.setAttributes(
                    [.modificationDate: accessedAt],
                    ofItemAtPath: entryURL.path
                )
                return descriptor(
                    metadata: metadata,
                    key: key,
                    entryURL: entryURL
                )
            } catch is CancellationError {
                return nil
            } catch {
                if
                    let entrySnapshot
                {
                    guard
                        let current =
                            try? currentSnapshot(
                                entryURL: entryURL,
                                metadataURL:
                                    metadataURL
                            ),
                        current == entrySnapshot
                    else {
                        continue
                    }
                }
                try? removeOwnedItem(
                    entryURL,
                    expectedParent:
                        accountDirectory(
                            for: key.accountID
                        )
                )
                return nil
            }
        }
        return nil
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        try? fileManager.removeItem(
            at: accountDirectory(for: accountID)
        )
    }

    private var encoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    private var decoder: PropertyListDecoder {
        PropertyListDecoder()
    }

    private func validate(
        _ workspace:
            GitLabJobTraceImportWorkspace
    ) throws {
        guard isExpectedWorkspace(workspace)
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        try validateDirectory(
            workspace.directoryURL,
            expectedParent:
                accountDirectory(
                    for: workspace.key.accountID
                )
        )
    }

    private func validate(
        _ metadata: StoredMetadata,
        for key: GitLabJobTraceKey
    ) throws {
        guard
            metadata.formatVersion
                == Self.metadataFormatVersion,
            metadata.keyDigest
                == Self.digest(
                    key.storageIdentifier
                ),
            metadata.lineCount >= 0,
            metadata.lineCount
                <= Self.maximumLineCount,
            metadata.indexByteCount
                == metadata.lineCount
                    * GitLabJobTraceIndexFormat
                    .offsetByteCount
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
    }

    private func isExpectedWorkspace(
        _ workspace:
            GitLabJobTraceImportWorkspace
    ) -> Bool {
        let expectedDirectory =
            workspaceDirectory(
                accountDirectory:
                    accountDirectory(
                        for:
                            workspace.key
                            .accountID
                    ),
                key: workspace.key,
                identifier:
                    workspace.identifier
            )
            .standardizedFileURL
        return
            workspace.directoryURL
            .standardizedFileURL
                == expectedDirectory
                && activeWorkspaceDirectories
                .contains(expectedDirectory)
    }

    private func createProtectedDirectory(
        _ directory: URL,
        withIntermediateDirectories: Bool
    ) throws {
        if fileManager.fileExists(
            atPath: directory.path
        ) {
            let values =
                try directory.resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ]
                )
            guard
                values.isDirectory == true,
                values.isSymbolicLink != true
            else {
                throw GitLabJobTraceStoreError
                    .storage
            }
        } else {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories:
                    withIntermediateDirectories
            )
        }
        try protectAndExcludeFromBackup(directory)
    }

    private func protectAndExcludeFromBackup(
        _ url: URL
    ) throws {
        try fileManager.setAttributes(
            [
                .protectionKey:
                    FileProtectionType
                    .completeUntilFirstUserAuthentication,
            ],
            ofItemAtPath: url.path
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var protectedURL = url
        try protectedURL.setResourceValues(values)
    }

    private func claim(
        _ prepared: GitLabJobTracePreparedEntry,
        in workspace:
            GitLabJobTraceImportWorkspace
    ) throws -> GitLabJobTracePreparedEntry {
        try validatePreparedSource(
            prepared.traceFileURL,
            in: workspace.directoryURL
        )
        try validatePreparedSource(
            prepared.indexFileURL,
            in: workspace.directoryURL
        )
        guard
            prepared.traceFileURL
                .standardizedFileURL
                != prepared.indexFileURL
                .standardizedFileURL
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }

        let traceURL =
            workspace.directoryURL.appending(
                path: Self.traceFileName,
                directoryHint: .notDirectory
            )
        let indexURL =
            workspace.directoryURL.appending(
                path: Self.indexFileName,
                directoryHint: .notDirectory
            )
        let reservedURLs = [
            traceURL.standardizedFileURL,
            indexURL.standardizedFileURL,
            workspace.directoryURL.appending(
                path: Self.metadataFileName,
                directoryHint: .notDirectory
            ).standardizedFileURL,
        ]
        guard
            !reservedURLs.contains(
                prepared.traceFileURL
                    .standardizedFileURL
            ),
            !reservedURLs.contains(
                prepared.indexFileURL
                    .standardizedFileURL
            ),
            !fileManager.fileExists(
                atPath: traceURL.path
            ),
            !fileManager.fileExists(
                atPath: indexURL.path
            )
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        try fileManager.moveItem(
            at: prepared.traceFileURL,
            to: traceURL
        )
        try fileManager.moveItem(
            at: prepared.indexFileURL,
            to: indexURL
        )
        return GitLabJobTracePreparedEntry(
            traceFileURL: traceURL,
            indexFileURL: indexURL,
            byteCount: prepared.byteCount,
            lineCount: prepared.lineCount,
            rawContentDigest:
                prepared.rawContentDigest,
            indexFormatVersion:
                prepared.indexFormatVersion,
            longLineCount:
                prepared.longLineCount
        )
    }

    private func validatePreparedSource(
        _ fileURL: URL,
        in directory: URL
    ) throws {
        guard
            fileURL.standardizedFileURL
                .deletingLastPathComponent()
                == directory.standardizedFileURL,
            fileURL.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == directory
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let values = try fileURL.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
    }

    private func persist(
        _ metadata: StoredMetadata,
        at fileURL: URL
    ) throws {
        let data = try encoder.encode(metadata)
        guard
            data.count
                <= Self.metadataMaximumByteCount
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        try data.write(
            to: fileURL,
            options: [
                .atomic,
                .completeFileProtectionUntilFirstUserAuthentication,
            ]
        )
        try protectAndExcludeFromBackup(fileURL)
    }

    private func publish(
        _ stagedURL: URL,
        at entryURL: URL
    ) throws {
        if fileManager.fileExists(
            atPath: entryURL.path
        ) {
            let backupName =
                ".old-" + UUID().uuidString
            _ = try fileManager.replaceItemAt(
                entryURL,
                withItemAt: stagedURL,
                backupItemName: backupName,
                options: []
            )
            let backupURL =
                entryURL.deletingLastPathComponent()
                .appending(
                    path: backupName,
                    directoryHint: .isDirectory
                )
            try? fileManager.removeItem(
                at: backupURL
            )
        } else {
            try fileManager.moveItem(
                at: stagedURL,
                to: entryURL
            )
        }
    }

    private func validateDirectory(
        _ directory: URL,
        expectedParent: URL
    ) throws {
        guard
            directory.standardizedFileURL
                .deletingLastPathComponent()
                == expectedParent
                .standardizedFileURL,
            directory.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == expectedParent
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let values = try directory.resourceValues(
            forKeys: [
                .isDirectoryKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isDirectory == true,
            values.isSymbolicLink != true
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
    }

    private func boundedRegularFileData(
        at fileURL: URL,
        expectedParent: URL,
        maximumByteCount: Int
    ) throws -> Data {
        guard
            fileURL.standardizedFileURL
                .deletingLastPathComponent()
                == expectedParent
                .standardizedFileURL,
            fileURL.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == expectedParent
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let values = try fileURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize >= 0,
            fileSize <= maximumByteCount
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let fileHandle = try FileHandle(
            forReadingFrom: fileURL
        )
        defer {
            try? fileHandle.close()
        }
        var data = Data()
        while data.count <= maximumByteCount {
            let remaining =
                maximumByteCount + 1 - data.count
            guard
                let chunk = try fileHandle.read(
                    upToCount:
                        min(64 * 1_024, remaining)
                ),
                !chunk.isEmpty
            else {
                break
            }
            data.append(chunk)
        }
        guard
            data.count <= maximumByteCount,
            data.count == fileSize
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        return data
    }

    private func maintainedEntries() async throws
        -> [MaintenanceEntry]
    {
        var entries: [MaintenanceEntry] = []
        for accountURL in try immediateChildren(
            of: rootDirectory
        ) {
            try Task.checkCancellation()
            guard
                Self.isSHA256Digest(
                    accountURL.lastPathComponent
                )
            else {
                try? removeOwnedItem(
                    accountURL,
                    expectedParent: rootDirectory
                )
                continue
            }

            do {
                try validateDirectory(
                    accountURL,
                    expectedParent: rootDirectory
                )
                try protectAndExcludeFromBackup(
                    accountURL
                )
                for entryURL in
                    try immediateChildren(
                        of: accountURL
                    )
                {
                    try Task.checkCancellation()
                    let name =
                        entryURL.lastPathComponent
                    if
                        name.hasPrefix(".tmp-")
                            || name.hasPrefix(".old-")
                    {
                        if
                            activeWorkspaceDirectories
                            .contains(
                                entryURL
                                    .standardizedFileURL
                            )
                        {
                            continue
                        }
                        try? removeOwnedItem(
                            entryURL,
                            expectedParent: accountURL
                        )
                        continue
                    }
                    guard
                        Self.isEntryDirectoryName(
                            name
                        )
                    else {
                        try? removeOwnedItem(
                            entryURL,
                            expectedParent: accountURL
                        )
                        continue
                    }
                    if
                        let entry =
                            try await maintainedEntry(
                                at: entryURL,
                                accountDirectory:
                                    accountURL
                            )
                    {
                        entries.append(entry)
                    }
                }
                if
                    try immediateChildren(
                        of: accountURL
                    ).isEmpty
                {
                    try? removeOwnedItem(
                        accountURL,
                        expectedParent: rootDirectory
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? removeOwnedItem(
                    accountURL,
                    expectedParent: rootDirectory
                )
            }
        }
        return entries
    }

    private func maintainedEntry(
        at entryURL: URL,
        accountDirectory: URL
    ) async throws -> MaintenanceEntry? {
        let metadataURL = entryURL.appending(
            path: Self.metadataFileName,
            directoryHint: .notDirectory
        )

        for _ in 0..<3 {
            var entrySnapshot: EntrySnapshot?
            do {
                try validateDirectory(
                    entryURL,
                    expectedParent: accountDirectory
                )
                try validateEntryChildren(
                    at: entryURL
                )
                let metadataData =
                    try boundedRegularFileData(
                        at: metadataURL,
                        expectedParent: entryURL,
                        maximumByteCount:
                            Self.metadataMaximumByteCount
                    )
                entrySnapshot = try snapshot(
                    entryURL: entryURL,
                    metadata: metadataData
                )
                let metadata =
                    try decoder.decode(
                        StoredMetadata.self,
                        from: metadataData
                    )
                try validate(
                    metadata,
                    entryDirectory: entryURL
                )
                let prepared =
                    preparedEntry(
                        metadata: metadata,
                        entryURL: entryURL
                    )
                let validated =
                    try await GitLabJobTraceFileValidator
                    .validate(
                        prepared,
                        inside: entryURL,
                        maximumTraceByteCount:
                            Self.maximumTraceByteCount,
                        maximumLineCount:
                            Self.maximumLineCount
                    )
                let currentSnapshot =
                    try currentSnapshot(
                        entryURL: entryURL,
                        metadataURL: metadataURL
                    )
                guard
                    currentSnapshot == entrySnapshot
                else {
                    continue
                }
                guard
                    validated.indexByteCount
                        == metadata.indexByteCount,
                    validated.indexContentDigest
                        == metadata.indexContentDigest
                else {
                    throw GitLabJobTraceStoreError
                        .invalidEntry
                }
                try protectAndExcludeFromBackup(
                    prepared.traceFileURL
                )
                try protectAndExcludeFromBackup(
                    prepared.indexFileURL
                )
                try protectAndExcludeFromBackup(
                    metadataURL
                )
                try protectAndExcludeFromBackup(
                    entryURL
                )
                let values =
                    try entryURL.resourceValues(
                        forKeys: [
                            .contentModificationDateKey,
                        ]
                    )
                return MaintenanceEntry(
                    directoryURL: entryURL,
                    logicalByteCount:
                        metadata.byteCount
                        + metadata.indexByteCount
                        + metadataData.count,
                    lastAccessedAt:
                        values.contentModificationDate
                        ?? metadata.storedAt
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if
                    let entrySnapshot
                {
                    guard
                        let current =
                            try? currentSnapshot(
                                entryURL: entryURL,
                                metadataURL:
                                    metadataURL
                            ),
                        current == entrySnapshot
                    else {
                        continue
                    }
                }
                try? removeOwnedItem(
                    entryURL,
                    expectedParent: accountDirectory
                )
                return nil
            }
        }
        return nil
    }

    private func snapshot(
        entryURL: URL,
        metadata: Data
    ) throws -> EntrySnapshot {
        let attributes =
            try fileManager.attributesOfItem(
                atPath: entryURL.path
            )
        guard
            let systemNumber =
                attributes[.systemNumber]
                    as? NSNumber,
            let fileNumber =
                attributes[.systemFileNumber]
                    as? NSNumber
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        return EntrySnapshot(
            metadata: metadata,
            directorySystemNumber:
                systemNumber.uint64Value,
            directoryFileNumber:
                fileNumber.uint64Value
        )
    }

    private func currentSnapshot(
        entryURL: URL,
        metadataURL: URL
    ) throws -> EntrySnapshot {
        let metadata =
            try boundedRegularFileData(
                at: metadataURL,
                expectedParent: entryURL,
                maximumByteCount:
                    Self.metadataMaximumByteCount
            )
        return try snapshot(
            entryURL: entryURL,
            metadata: metadata
        )
    }

    private func publishedEntries() throws
        -> [MaintenanceEntry]
    {
        var entries: [MaintenanceEntry] = []
        guard
            fileManager.fileExists(
                atPath: rootDirectory.path
            )
        else {
            return entries
        }
        for accountURL in try immediateChildren(
            of: rootDirectory
        ) where
            Self.isSHA256Digest(
                accountURL.lastPathComponent
            )
        {
            guard
                (try? validateDirectory(
                    accountURL,
                    expectedParent: rootDirectory
                )) != nil
            else {
                continue
            }
            for entryURL in
                try immediateChildren(of: accountURL)
            where
                Self.isEntryDirectoryName(
                    entryURL.lastPathComponent
                )
            {
                if
                    let entry =
                        try? publishedEntry(
                            at: entryURL,
                            accountDirectory:
                                accountURL
                        )
                {
                    entries.append(entry)
                }
            }
        }
        return entries
    }

    private func publishedEntry(
        at entryURL: URL,
        accountDirectory: URL
    ) throws -> MaintenanceEntry {
        try validateDirectory(
            entryURL,
            expectedParent: accountDirectory
        )
        try validateEntryChildren(at: entryURL)
        let metadataURL = entryURL.appending(
            path: Self.metadataFileName,
            directoryHint: .notDirectory
        )
        let metadataData =
            try boundedRegularFileData(
                at: metadataURL,
                expectedParent: entryURL,
                maximumByteCount:
                    Self.metadataMaximumByteCount
            )
        let metadata =
            try decoder.decode(
                StoredMetadata.self,
                from: metadataData
            )
        try validate(
            metadata,
            entryDirectory: entryURL
        )
        let prepared = preparedEntry(
            metadata: metadata,
            entryURL: entryURL
        )
        let traceSize = try regularFileSize(
            at: prepared.traceFileURL,
            expectedParent: entryURL
        )
        let indexSize = try regularFileSize(
            at: prepared.indexFileURL,
            expectedParent: entryURL
        )
        guard
            traceSize == metadata.byteCount,
            indexSize == metadata.indexByteCount
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let values = try entryURL.resourceValues(
            forKeys: [.contentModificationDateKey]
        )
        return MaintenanceEntry(
            directoryURL: entryURL,
            logicalByteCount:
                traceSize
                + indexSize
                + metadataData.count,
            lastAccessedAt:
                values.contentModificationDate
                ?? metadata.storedAt
        )
    }

    private func validate(
        _ metadata: StoredMetadata,
        entryDirectory: URL
    ) throws {
        let keyDigest =
            entryDirectory
            .deletingPathExtension()
            .lastPathComponent
        guard
            metadata.formatVersion
                == Self.metadataFormatVersion,
            metadata.keyDigest == keyDigest,
            Self.isSHA256Digest(
                metadata.keyDigest
            ),
            metadata.byteCount >= 0,
            metadata.byteCount
                <= Self.maximumTraceByteCount,
            metadata.lineCount >= 0,
            metadata.lineCount
                <= Self.maximumLineCount,
            metadata.indexByteCount
                == metadata.lineCount
                    * GitLabJobTraceIndexFormat
                    .offsetByteCount,
            metadata.indexFormatVersion
                == GitLabJobTraceIndexFormat
                .currentVersion,
            Self.isSHA256Digest(
                metadata.rawContentDigest
            ),
            Self.isSHA256Digest(
                metadata.indexContentDigest
            ),
            metadata.longLineCount >= 0,
            metadata.longLineCount
                <= metadata.lineCount,
            (metadata.byteCount == 0)
                == (metadata.lineCount == 0)
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
    }

    private func validateEntryChildren(
        at entryURL: URL
    ) throws {
        let names = try immediateChildren(
            of: entryURL
        ).map(\.lastPathComponent)
        guard
            names.count == 3,
            Set(names)
                == Set([
                    Self.traceFileName,
                    Self.indexFileName,
                    Self.metadataFileName,
                ])
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
    }

    private func preparedEntry(
        metadata: StoredMetadata,
        entryURL: URL
    ) -> GitLabJobTracePreparedEntry {
        GitLabJobTracePreparedEntry(
            traceFileURL:
                entryURL.appending(
                    path: Self.traceFileName,
                    directoryHint: .notDirectory
                ),
            indexFileURL:
                entryURL.appending(
                    path: Self.indexFileName,
                    directoryHint: .notDirectory
                ),
            byteCount: metadata.byteCount,
            lineCount: metadata.lineCount,
            rawContentDigest:
                metadata.rawContentDigest,
            indexFormatVersion:
                metadata.indexFormatVersion,
            longLineCount:
                metadata.longLineCount
        )
    }

    private func regularFileSize(
        at fileURL: URL,
        expectedParent: URL
    ) throws -> Int {
        guard
            fileURL.standardizedFileURL
                .deletingLastPathComponent()
                == expectedParent
                .standardizedFileURL,
            fileURL.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == expectedParent
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let values = try fileURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize >= 0
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        return fileSize
    }

    private func immediateChildren(
        of directory: URL
    ) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .fileSizeKey,
                .isDirectoryKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ],
            options: []
        )
    }

    private func removeOwnedItem(
        _ url: URL,
        expectedParent: URL
    ) throws {
        guard
            url.standardizedFileURL
                .deletingLastPathComponent()
                == expectedParent
                .standardizedFileURL,
            url.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == expectedParent
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        try fileManager.removeItem(at: url)
    }

    private func prune(
        _ entries: [MaintenanceEntry]
    ) {
        var storedByteCount =
            entries.reduce(into: 0) {
                let (sum, overflow) =
                    $0.addingReportingOverflow(
                        $1.logicalByteCount
                    )
                $0 = overflow ? Int.max : sum
            }
        guard
            storedByteCount
                > maximumStoredByteCount
        else {
            return
        }
        let oldestFirst = entries.sorted {
            if
                $0.lastAccessedAt
                    != $1.lastAccessedAt
            {
                return
                    $0.lastAccessedAt
                    < $1.lastAccessedAt
            }
            return
                $0.directoryURL.path
                < $1.directoryURL.path
        }
        for entry in oldestFirst {
            guard
                storedByteCount
                    > maximumStoredByteCount
            else {
                break
            }
            do {
                try removeOwnedItem(
                    entry.directoryURL,
                    expectedParent:
                        entry.directoryURL
                        .deletingLastPathComponent()
                )
                storedByteCount = max(
                    0,
                    storedByteCount
                        - entry.logicalByteCount
                )
            } catch {
                continue
            }
        }
    }

    private func descriptor(
        metadata: StoredMetadata,
        key: GitLabJobTraceKey,
        entryURL: URL
    ) -> GitLabJobTraceDescriptor {
        GitLabJobTraceDescriptor(
            key: key,
            traceFileURL:
                entryURL.appending(
                    path: Self.traceFileName,
                    directoryHint: .notDirectory
                ),
            indexFileURL:
                entryURL.appending(
                    path: Self.indexFileName,
                    directoryHint: .notDirectory
                ),
            byteCount: metadata.byteCount,
            lineCount: metadata.lineCount,
            storedAt: metadata.storedAt,
            rawContentDigest:
                metadata.rawContentDigest,
            longLineCount:
                metadata.longLineCount
        )
    }

    private func accountDirectory(
        for accountID: GitLabAccountID
    ) -> URL {
        rootDirectory.appending(
            path: Self.digest(
                accountID.storageIdentifier
            ),
            directoryHint: .isDirectory
        )
    }

    private func entryDirectory(
        for key: GitLabJobTraceKey
    ) -> URL {
        accountDirectory(for: key.accountID)
            .appending(
                path:
                    Self.digest(
                        key.storageIdentifier
                    )
                    + ".entry",
                directoryHint: .isDirectory
            )
    }

    private func workspaceDirectory(
        accountDirectory: URL,
        key: GitLabJobTraceKey,
        identifier: UUID
    ) -> URL {
        accountDirectory.appending(
            path:
                ".tmp-"
                + Self.digest(
                    key.storageIdentifier
                )
                + "-"
                + identifier.uuidString
                .lowercased(),
            directoryHint: .isDirectory
        )
    }

    private static func digest(
        _ value: String
    ) -> String {
        digest(Data(value.utf8))
    }

    private static func digest(
        _ data: Data
    ) -> String {
        SHA256.hash(data: data)
            .map {
                String(format: "%02x", $0)
            }
            .joined()
    }

    private static func isEntryDirectoryName(
        _ name: String
    ) -> Bool {
        name.hasSuffix(".entry")
            && isSHA256Digest(
                String(name.dropLast(".entry".count))
            )
    }

    private static func isSHA256Digest(
        _ value: String
    ) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57)
                    || ($0 >= 97 && $0 <= 102)
            }
    }
}

private nonisolated enum
    GitLabJobTraceFileValidator
{
    struct Result: Sendable {
        let indexByteCount: Int
        let indexContentDigest: String
    }

    @concurrent
    static func validate(
        _ prepared:
            GitLabJobTracePreparedEntry,
        inside directory: URL,
        maximumTraceByteCount: Int,
        maximumLineCount: Int
    ) async throws -> Result {
        do {
            try Task.checkCancellation()
            guard
                prepared.byteCount >= 0,
                prepared.byteCount
                    <= maximumTraceByteCount,
                prepared.lineCount >= 0,
                prepared.lineCount
                    <= maximumLineCount,
                prepared.longLineCount >= 0,
                prepared.longLineCount
                    <= prepared.lineCount,
                prepared.indexFormatVersion
                    == GitLabJobTraceIndexFormat
                    .currentVersion,
                Self.isSHA256Digest(
                    prepared.rawContentDigest
                ),
                (prepared.byteCount == 0)
                    == (prepared.lineCount == 0),
                prepared.traceFileURL
                    .standardizedFileURL
                    != prepared.indexFileURL
                    .standardizedFileURL
            else {
                throw GitLabJobTraceStoreError
                    .invalidEntry
            }

            let traceSize = try regularFileSize(
                at: prepared.traceFileURL,
                inside: directory
            )
            let indexSize = try regularFileSize(
                at: prepared.indexFileURL,
                inside: directory
            )
            let expectedIndexSize =
                prepared.lineCount
                * GitLabJobTraceIndexFormat
                .offsetByteCount
            guard
                traceSize == prepared.byteCount,
                indexSize == expectedIndexSize
            else {
                throw GitLabJobTraceStoreError
                    .invalidEntry
            }

            let rawDigest = try fileDigest(
                at: prepared.traceFileURL
            )
            guard
                rawDigest
                    == prepared.rawContentDigest
            else {
                throw GitLabJobTraceStoreError
                    .invalidEntry
            }
            let indexDigest = try validateIndex(
                at: prepared.indexFileURL,
                lineCount: prepared.lineCount,
                traceByteCount:
                    prepared.byteCount
            )
            return Result(
                indexByteCount: indexSize,
                indexContentDigest: indexDigest
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch
            let error as GitLabJobTraceStoreError
        {
            throw error
        } catch {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
    }

    private static func regularFileSize(
        at fileURL: URL,
        inside directory: URL
    ) throws -> Int {
        guard
            fileURL.standardizedFileURL
                .deletingLastPathComponent()
                == directory.standardizedFileURL,
            fileURL.deletingLastPathComponent()
                .resolvingSymlinksInPath()
                == directory
                .resolvingSymlinksInPath()
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        let values = try fileURL.resourceValues(
            forKeys: [
                .fileSizeKey,
                .isRegularFileKey,
                .isSymbolicLinkKey,
            ]
        )
        guard
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize >= 0
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        return fileSize
    }

    private static func fileDigest(
        at fileURL: URL
    ) throws -> String {
        let fileHandle = try FileHandle(
            forReadingFrom: fileURL
        )
        defer {
            try? fileHandle.close()
        }
        var hasher = SHA256()
        while
            let chunk = try fileHandle.read(
                upToCount: 64 * 1_024
            ),
            !chunk.isEmpty
        {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map {
                String(format: "%02x", $0)
            }
            .joined()
    }

    private static func validateIndex(
        at fileURL: URL,
        lineCount: Int,
        traceByteCount: Int
    ) throws -> String {
        let fileHandle = try FileHandle(
            forReadingFrom: fileURL
        )
        defer {
            try? fileHandle.close()
        }
        var hasher = SHA256()
        var observedLineCount = 0
        var previousOffset: UInt32?
        var pendingBytes: [UInt8] = []

        while
            let chunk = try fileHandle.read(
                upToCount: 64 * 1_024
            ),
            !chunk.isEmpty
        {
            try Task.checkCancellation()
            hasher.update(data: chunk)
            pendingBytes.append(
                contentsOf: chunk
            )

            var index = 0
            let completeByteCount =
                pendingBytes.count
                - pendingBytes.count
                    % GitLabJobTraceIndexFormat
                    .offsetByteCount
            while index < completeByteCount {
                let value =
                    UInt32(pendingBytes[index])
                    | UInt32(pendingBytes[index + 1])
                        << 8
                    | UInt32(pendingBytes[index + 2])
                        << 16
                    | UInt32(pendingBytes[index + 3])
                        << 24
                if observedLineCount == 0 {
                    guard value == 0 else {
                        throw GitLabJobTraceStoreError
                            .invalidEntry
                    }
                } else {
                    guard
                        let previousOffset,
                        value > previousOffset
                    else {
                        throw GitLabJobTraceStoreError
                            .invalidEntry
                    }
                }
                guard
                    Int(value) < traceByteCount
                else {
                    throw GitLabJobTraceStoreError
                        .invalidEntry
                }
                previousOffset = value
                observedLineCount += 1
                index +=
                    GitLabJobTraceIndexFormat
                    .offsetByteCount
            }
            if index > 0 {
                pendingBytes.removeFirst(index)
            }
        }
        guard
            pendingBytes.isEmpty,
            observedLineCount == lineCount
        else {
            throw GitLabJobTraceStoreError
                .invalidEntry
        }
        return hasher.finalize()
            .map {
                String(format: "%02x", $0)
            }
            .joined()
    }

    private static func isSHA256Digest(
        _ value: String
    ) -> Bool {
        value.utf8.count == 64
            && value.utf8.allSatisfy {
                ($0 >= 48 && $0 <= 57)
                    || ($0 >= 97 && $0 <= 102)
            }
    }
}
