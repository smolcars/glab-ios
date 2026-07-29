import CryptoKit
import Foundation
import Testing
@testable import Glab

@Suite("GitLab job trace store")
struct GitLabJobTraceStoreTests {
    @Test("Separates every account and trace identity component")
    func separatesKeysAndRedactsDescriptions() throws {
        let firstAccount = try account()
        let firstRoute = try route()
        let keys = [
            GitLabJobTraceKey(
                accountID: firstAccount,
                route: firstRoute
            ),
            GitLabJobTraceKey(
                accountID: try account(
                    host: "https://other.example.com"
                ),
                route: firstRoute
            ),
            GitLabJobTraceKey(
                accountID: try account(userID: 8),
                route: firstRoute
            ),
            GitLabJobTraceKey(
                accountID: firstAccount,
                route: try route(projectID: 43)
            ),
            GitLabJobTraceKey(
                accountID: firstAccount,
                route: try route(jobID: 8)
            ),
        ]

        #expect(Set(keys).count == keys.count)
        for key in keys {
            for value in [
                String(describing: key),
                String(reflecting: key),
            ] {
                #expect(!value.contains("gitlab.example.com"))
                #expect(!value.contains("other.example.com"))
                #expect(!value.contains("42"))
                #expect(!value.contains("7"))
            }
        }
    }

    @Test("All store values and errors redact identities and paths")
    func redactsStoreDescriptions() async throws {
        try await withFileStore { store, rootDirectory in
            let key = try traceKey()
            let workspace = try await store.beginImport(
                for: key
            )
            let privateTrace =
                Data("private-token-value".utf8)
            let prepared = try writePreparedEntry(
                privateTrace,
                offsets: [0],
                in: workspace
            )
            let descriptor = try await store.commit(
                prepared,
                in: workspace
            )

            for value in [
                String(describing: key),
                String(reflecting: key),
                String(describing: workspace),
                String(reflecting: workspace),
                String(describing: prepared),
                String(reflecting: prepared),
                String(describing: descriptor),
                String(reflecting: descriptor),
                String(
                    describing:
                        GitLabJobTraceStoreError
                        .invalidEntry
                ),
                String(
                    reflecting:
                        GitLabJobTraceStoreError
                        .storage
                ),
            ] {
                #expect(!value.contains("gitlab.example.com"))
                #expect(!value.contains(rootDirectory.path))
                #expect(!value.contains("private-token-value"))
                #expect(!value.contains("42"))
                #expect(!value.contains("7"))
            }
        }
    }

    @Test("Commits and restores one protected account-scoped entry")
    func commitsAndRestoresEntry() async throws {
        try await withFileStore { store, rootDirectory in
            let key = try traceKey()
            let trace = Data("first\nsecond\n".utf8)
            let descriptor = try await prepareAndCommit(
                trace,
                offsets: [0, 6],
                for: key,
                in: store,
                storedAt: Date(timeIntervalSince1970: 1_000)
            )

            #expect(descriptor.key == key)
            #expect(descriptor.byteCount == trace.count)
            #expect(descriptor.lineCount == 2)
            #expect(descriptor.longLineCount == 0)
            #expect(
                descriptor.rawContentDigest
                    == digest(trace)
            )
            #expect(
                try Data(contentsOf: descriptor.traceFileURL)
                    == trace
            )

            let restoredStore = FileGitLabJobTraceStore(
                rootDirectory: rootDirectory
            )
            let restored = try #require(
                await restoredStore.descriptor(for: key)
            )
            #expect(restored == descriptor)

            let paths = recursiveURLs(below: rootDirectory)
                .map(\.path)
            #expect(
                paths.allSatisfy {
                    !$0.contains("gitlab.example.com")
                        && !$0.contains("/42/")
                        && !$0.contains("/7/")
                }
            )
            #expect(
                entryDirectories(in: rootDirectory).count
                    == 1
            )
        }
    }

    @Test("Reads touch LRU metadata without rewriting stored content")
    func readsTouchAccessTime() async throws {
        let rootDirectory =
            FileManager.default.temporaryDirectory
            .appending(
                path:
                    "GlabJobTraceStoreTests-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(
                at: rootDirectory
            )
        }
        let accessedAt =
            Date(timeIntervalSince1970: 2_000)
        let store = FileGitLabJobTraceStore(
            rootDirectory: rootDirectory,
            currentDate: { accessedAt }
        )
        let key = try traceKey()
        _ = try await prepareAndCommit(
            Data("private trace".utf8),
            offsets: [0],
            for: key,
            in: store,
            storedAt: Date(timeIntervalSince1970: 1_000)
        )
        let entryURL = try #require(
            entryDirectories(in: rootDirectory)
                .first
        )
        let metadataURL = try #require(
            recursiveURLs(below: rootDirectory)
                .first {
                    $0.lastPathComponent
                        == "metadata.plist"
                }
        )
        let metadataBefore = try Data(
            contentsOf: metadataURL
        )

        _ = await store.descriptor(for: key)

        let modificationDate =
            try entryURL.resourceValues(
                forKeys: [
                    .contentModificationDateKey,
                ]
            )
            .contentModificationDate
        #expect(modificationDate == accessedAt)
        #expect(
            try Data(contentsOf: metadataURL)
                == metadataBefore
        )
    }

    @Test("In-memory storage isolates and purges accounts")
    func inMemoryStorePurgesAccount() async throws {
        let firstKey = try traceKey(userID: 7)
        let secondKey = try traceKey(userID: 8)
        let first = descriptor(for: firstKey)
        let second = descriptor(for: secondKey)
        let store = InMemoryGitLabJobTraceStore(
            descriptors: [
                firstKey: first,
                secondKey: second,
            ]
        )

        await store.removeAll(
            for: firstKey.accountID
        )

        #expect(
            await store.descriptor(for: firstKey)
                == nil
        )
        #expect(
            await store.descriptor(for: secondKey)
                == second
        )
    }

    @Test("A failed refresh retains the previous complete entry")
    func failedRefreshRetainsPreviousEntry() async throws {
        try await withFileStore { store, rootDirectory in
            let key = try traceKey()
            let original = Data("complete old trace\n".utf8)
            let originalDescriptor =
                try await prepareAndCommit(
                    original,
                    offsets: [0],
                    for: key,
                    in: store
                )
            let workspace = try await store.beginImport(
                for: key
            )
            let replacement =
                Data("incomplete replacement\n".utf8)
            let prepared = try writePreparedEntry(
                replacement,
                offsets: [0],
                in: workspace,
                digestOverride: String(repeating: "0", count: 64)
            )

            await #expect(
                throws:
                    GitLabJobTraceStoreError
                    .invalidEntry
            ) {
                try await store.commit(
                    prepared,
                    in: workspace
                )
            }

            let restored = try #require(
                await store.descriptor(for: key)
            )
            #expect(restored == originalDescriptor)
            #expect(
                try Data(contentsOf: restored.traceFileURL)
                    == original
            )
            #expect(
                entryDirectories(in: rootDirectory).count
                    == 1
            )
            #expect(
                temporaryDirectories(in: rootDirectory)
                    .isEmpty
            )
        }
    }

    @Test("Rejects a trace outside its store-owned workspace")
    func rejectsTraversalOutsideWorkspace() async throws {
        try await withFileStore { store, rootDirectory in
            let workspace = try await store.beginImport(
                for: traceKey()
            )
            let outsideURL = rootDirectory.appending(
                path: "private-outside-trace",
                directoryHint: .notDirectory
            )
            let trace = Data("private trace".utf8)
            try trace.write(to: outsideURL)
            let indexURL = workspace.directoryURL.appending(
                path: "index.tmp",
                directoryHint: .notDirectory
            )
            try encodedOffsets([0]).write(to: indexURL)
            let prepared = GitLabJobTracePreparedEntry(
                traceFileURL: outsideURL,
                indexFileURL: indexURL,
                byteCount: trace.count,
                lineCount: 1,
                rawContentDigest: digest(trace),
                indexFormatVersion:
                    GitLabJobTraceIndexFormat.currentVersion,
                longLineCount: 0
            )

            await #expect(
                throws:
                    GitLabJobTraceStoreError
                    .invalidEntry
            ) {
                try await store.commit(
                    prepared,
                    in: workspace
                )
            }
            #expect(
                FileManager.default.fileExists(
                    atPath: outsideURL.path
                )
            )
            #expect(
                temporaryDirectories(in: rootDirectory)
                    .isEmpty
            )
        }
    }

    @Test("Binds each workspace to its original trace key")
    func rejectsWorkspaceRebinding() async throws {
        try await withFileStore { store, _ in
            let originalKey = try traceKey()
            let workspace = try await store.beginImport(
                for: originalKey
            )
            let otherKey = GitLabJobTraceKey(
                accountID: originalKey.accountID,
                route: try route(jobID: 99)
            )
            let rebound =
                GitLabJobTraceImportWorkspace(
                    key: otherKey,
                    directoryURL:
                        workspace.directoryURL,
                    identifier:
                        workspace.identifier
                )
            let prepared = try writePreparedEntry(
                Data("private trace".utf8),
                offsets: [0],
                in: workspace
            )

            await #expect(
                throws:
                    GitLabJobTraceStoreError
                    .invalidEntry
            ) {
                try await store.commit(
                    prepared,
                    in: rebound
                )
            }
            await store.discard(workspace)
        }
    }

    @Test("Rejects symbolic-link entry files")
    func rejectsSymbolicLinks() async throws {
        try await withFileStore { store, rootDirectory in
            let workspace = try await store.beginImport(
                for: traceKey()
            )
            let outsideURL = rootDirectory.appending(
                path: "private-link-target",
                directoryHint: .notDirectory
            )
            let trace = Data("private trace".utf8)
            try trace.write(to: outsideURL)
            let linkedTraceURL =
                workspace.directoryURL.appending(
                    path: "trace-link.tmp",
                    directoryHint: .notDirectory
                )
            try FileManager.default.createSymbolicLink(
                at: linkedTraceURL,
                withDestinationURL: outsideURL
            )
            let indexURL = workspace.directoryURL.appending(
                path: "index.tmp",
                directoryHint: .notDirectory
            )
            try encodedOffsets([0]).write(to: indexURL)
            let prepared = GitLabJobTracePreparedEntry(
                traceFileURL: linkedTraceURL,
                indexFileURL: indexURL,
                byteCount: trace.count,
                lineCount: 1,
                rawContentDigest: digest(trace),
                indexFormatVersion:
                    GitLabJobTraceIndexFormat.currentVersion,
                longLineCount: 0
            )

            await #expect(
                throws:
                    GitLabJobTraceStoreError
                    .invalidEntry
            ) {
                try await store.commit(
                    prepared,
                    in: workspace
                )
            }
            #expect(
                FileManager.default.fileExists(
                    atPath: outsideURL.path
                )
            )
        }
    }

    @Test(
        "Rejects invalid line offsets",
        arguments: [
            [UInt32(1)],
            [UInt32(0), UInt32(0)],
            [UInt32(0), UInt32(8)],
        ]
    )
    func rejectsInvalidLineOffsets(
        _ offsets: [UInt32]
    ) async throws {
        try await withFileStore { store, _ in
            let key = try traceKey()
            let workspace = try await store.beginImport(
                for: key
            )
            let prepared = try writePreparedEntry(
                Data("one\ntwo".utf8),
                offsets: offsets,
                in: workspace
            )

            await #expect(
                throws:
                    GitLabJobTraceStoreError
                    .invalidEntry
            ) {
                try await store.commit(
                    prepared,
                    in: workspace
                )
            }
            #expect(await store.descriptor(for: key) == nil)
        }
    }

    @Test(
        "Rejects invalid import claims",
        arguments: [
            ImportMutation.byteCount,
            .digest,
            .indexVersion,
            .indexByteCount,
            .lineCount,
            .longLineCount,
        ]
    )
    func rejectsInvalidImportClaims(
        _ mutation: ImportMutation
    ) async throws {
        try await withFileStore { store, _ in
            let key = try traceKey()
            let workspace = try await store.beginImport(
                for: key
            )
            let trace = Data("one\ntwo".utf8)
            let valid = try writePreparedEntry(
                trace,
                offsets: [0, 4],
                in: workspace
            )
            let invalid = mutation.applying(to: valid)

            await #expect(
                throws:
                    GitLabJobTraceStoreError
                    .invalidEntry
            ) {
                try await store.commit(
                    invalid,
                    in: workspace
                )
            }
            #expect(await store.descriptor(for: key) == nil)
        }
    }

    @Test("Corrupt metadata is removed instead of being published")
    func removesCorruptMetadata() async throws {
        try await withFileStore { store, rootDirectory in
            let key = try traceKey()
            _ = try await prepareAndCommit(
                Data("private trace\n".utf8),
                offsets: [0],
                for: key,
                in: store
            )
            let metadataURL = try #require(
                recursiveURLs(below: rootDirectory)
                    .first {
                        $0.lastPathComponent
                            == "metadata.plist"
                    }
            )
            try Data("private corrupt metadata".utf8)
                .write(to: metadataURL)

            #expect(await store.descriptor(for: key) == nil)
            #expect(
                entryDirectories(in: rootDirectory)
                    .isEmpty
            )
        }
    }

    @Test("Corrupt trace or index bytes invalidate the complete entry")
    func removesCorruptEntryFiles() async throws {
        for fileName in ["trace.raw", "lines.idx"] {
            try await withFileStore { store, rootDirectory in
                let key = try traceKey()
                _ = try await prepareAndCommit(
                    Data("private trace\n".utf8),
                    offsets: [0],
                    for: key,
                    in: store
                )
                let fileURL = try #require(
                    recursiveURLs(below: rootDirectory)
                        .first {
                            $0.lastPathComponent
                                == fileName
                        }
                )
                var bytes = try Data(contentsOf: fileURL)
                bytes[bytes.startIndex] ^= 0xff
                try bytes.write(to: fileURL)

                #expect(
                    await store.descriptor(for: key)
                        == nil
                )
                #expect(
                    entryDirectories(in: rootDirectory)
                        .isEmpty
                )
            }
        }
    }

    @Test("Cancellation keeps the old entry and removes staging data")
    func cancellationCleansWorkspace() async throws {
        try await withFileStore { store, rootDirectory in
            let key = try traceKey()
            let original = try await prepareAndCommit(
                Data("old trace".utf8),
                offsets: [0],
                for: key,
                in: store
            )
            let workspace = try await store.beginImport(
                for: key
            )
            let prepared = try writePreparedEntry(
                Data("replacement".utf8),
                offsets: [0],
                in: workspace
            )
            let gate = TestGate()
            let task = Task {
                await gate.wait()
                return try await store.commit(
                    prepared,
                    in: workspace
                )
            }
            await gate.waitUntilBlocked()
            task.cancel()
            await gate.open()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }
            #expect(
                await store.descriptor(for: key)
                    == original
            )
            #expect(
                temporaryDirectories(in: rootDirectory)
                    .isEmpty
            )
        }
    }

    @Test("Purges one account without affecting another")
    func purgesOnlySelectedAccount() async throws {
        try await withFileStore { store, _ in
            let firstKey = try traceKey(userID: 7)
            let secondKey = try traceKey(userID: 8)
            _ = try await prepareAndCommit(
                Data("first".utf8),
                offsets: [0],
                for: firstKey,
                in: store
            )
            let second = try await prepareAndCommit(
                Data("second".utf8),
                offsets: [0],
                for: secondKey,
                in: store
            )

            await store.removeAll(
                for: firstKey.accountID
            )

            #expect(
                await store.descriptor(for: firstKey)
                    == nil
            )
            #expect(
                await store.descriptor(for: secondKey)
                    == second
            )
        }
    }

    @Test("Committed files are backup-excluded and protected")
    func appliesStorageProtection() async throws {
        try await withFileStore { store, rootDirectory in
            _ = try await prepareAndCommit(
                Data("trace".utf8),
                offsets: [0],
                for: traceKey(),
                in: store
            )

            for url in recursiveURLs(below: rootDirectory) {
                let resourceValues = try url.resourceValues(
                    forKeys: [.isExcludedFromBackupKey]
                )
                #expect(
                    resourceValues.isExcludedFromBackup
                        == true
                )

                let attributes =
                    try FileManager.default
                    .attributesOfItem(atPath: url.path)
                let protection =
                    attributes[.protectionKey]
                        as? FileProtectionType
                #if targetEnvironment(simulator)
                    #expect(protection == nil)
                #else
                    #expect(
                        protection
                            == .completeUntilFirstUserAuthentication
                    )
                #endif
            }
        }
    }
}

extension GitLabJobTraceStoreTests {
    enum ImportMutation: CaseIterable, Sendable {
        case byteCount
        case digest
        case indexVersion
        case indexByteCount
        case lineCount
        case longLineCount

        func applying(
            to entry: GitLabJobTracePreparedEntry
        ) -> GitLabJobTracePreparedEntry {
            switch self {
            case .byteCount:
                entry.replacing(
                    byteCount: entry.byteCount + 1
                )
            case .digest:
                entry.replacing(
                    rawContentDigest:
                        String(repeating: "f", count: 64)
                )
            case .indexVersion:
                entry.replacing(indexFormatVersion: 999)
            case .indexByteCount:
                entry.replacing(lineCount: 1)
            case .lineCount:
                entry.replacing(
                    lineCount:
                        FileGitLabJobTraceStore
                        .maximumLineCount + 1
                )
            case .longLineCount:
                entry.replacing(longLineCount: 3)
            }
        }
    }

    func account(
        host: String = "https://gitlab.example.com",
        userID: Int = 7
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(host),
            userID: userID
        )
    }

    func route(
        projectID: Int = 42,
        jobID: Int = 7
    ) throws -> GitLabJobTraceRoute {
        try #require(
            GitLabJobTraceRoute(
                projectID: projectID,
                jobID: jobID
            )
        )
    }

    func traceKey(
        userID: Int = 7
    ) throws -> GitLabJobTraceKey {
        GitLabJobTraceKey(
            accountID: try account(userID: userID),
            route: try route()
        )
    }

    func descriptor(
        for key: GitLabJobTraceKey
    ) -> GitLabJobTraceDescriptor {
        GitLabJobTraceDescriptor(
            key: key,
            traceFileURL:
                URL(filePath: "/private/trace"),
            indexFileURL:
                URL(filePath: "/private/index"),
            byteCount: 1,
            lineCount: 1,
            storedAt:
                Date(timeIntervalSince1970: 1),
            rawContentDigest:
                String(repeating: "0", count: 64),
            longLineCount: 0
        )
    }

    func prepareAndCommit(
        _ trace: Data,
        offsets: [UInt32],
        for key: GitLabJobTraceKey,
        in store: FileGitLabJobTraceStore,
        storedAt: Date = Date(
            timeIntervalSince1970: 2_000
        )
    ) async throws -> GitLabJobTraceDescriptor {
        let workspace = try await store.beginImport(
            for: key
        )
        let prepared = try writePreparedEntry(
            trace,
            offsets: offsets,
            in: workspace
        )
        return try await store.commit(
            prepared,
            in: workspace,
            storedAt: storedAt
        )
    }

    func writePreparedEntry(
        _ trace: Data,
        offsets: [UInt32],
        in workspace:
            GitLabJobTraceImportWorkspace,
        digestOverride: String? = nil
    ) throws -> GitLabJobTracePreparedEntry {
        let traceURL = workspace.directoryURL.appending(
            path: "download.tmp",
            directoryHint: .notDirectory
        )
        let indexURL = workspace.directoryURL.appending(
            path: "index.tmp",
            directoryHint: .notDirectory
        )
        try trace.write(to: traceURL)
        try encodedOffsets(offsets).write(to: indexURL)

        return GitLabJobTracePreparedEntry(
            traceFileURL: traceURL,
            indexFileURL: indexURL,
            byteCount: trace.count,
            lineCount: offsets.count,
            rawContentDigest:
                digestOverride ?? digest(trace),
            indexFormatVersion:
                GitLabJobTraceIndexFormat.currentVersion,
            longLineCount: 0
        )
    }

    func encodedOffsets(
        _ offsets: [UInt32]
    ) -> Data {
        var data = Data()
        for offset in offsets {
            var littleEndian =
                offset.littleEndian
            withUnsafeBytes(of: &littleEndian) {
                data.append(contentsOf: $0)
            }
        }
        return data
    }

    func digest(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map {
                String(format: "%02x", $0)
            }
            .joined()
    }

    func withFileStore(
        _ operation: (
            FileGitLabJobTraceStore,
            URL
        ) async throws -> Void
    ) async throws {
        let rootDirectory =
            FileManager.default.temporaryDirectory
            .appending(
                path:
                    "GlabJobTraceStoreTests-"
                    + UUID().uuidString,
                directoryHint: .isDirectory
            )
        defer {
            try? FileManager.default.removeItem(
                at: rootDirectory
            )
        }
        try await operation(
            FileGitLabJobTraceStore(
                rootDirectory: rootDirectory
            ),
            rootDirectory
        )
    }

    func recursiveURLs(
        below rootDirectory: URL
    ) -> [URL] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: nil
            )
        else {
            return []
        }
        return enumerator.compactMap { $0 as? URL }
    }

    func entryDirectories(
        in rootDirectory: URL
    ) -> [URL] {
        recursiveURLs(below: rootDirectory)
            .filter {
                $0.pathExtension == "entry"
                    && (try? $0.resourceValues(
                        forKeys: [.isDirectoryKey]
                    ).isDirectory) == true
            }
    }

    func temporaryDirectories(
        in rootDirectory: URL
    ) -> [URL] {
        recursiveURLs(below: rootDirectory)
            .filter {
                $0.lastPathComponent
                    .hasPrefix(".tmp-")
            }
    }
}

private actor TestGate {
    private var continuation:
        CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func waitUntilBlocked() async {
        while continuation == nil {
            await Task.yield()
        }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

private extension GitLabJobTracePreparedEntry {
    func replacing(
        byteCount: Int? = nil,
        lineCount: Int? = nil,
        rawContentDigest: String? = nil,
        indexFormatVersion: Int? = nil,
        longLineCount: Int? = nil
    ) -> Self {
        Self(
            traceFileURL: traceFileURL,
            indexFileURL: indexFileURL,
            byteCount: byteCount ?? self.byteCount,
            lineCount: lineCount ?? self.lineCount,
            rawContentDigest:
                rawContentDigest
                ?? self.rawContentDigest,
            indexFormatVersion:
                indexFormatVersion
                ?? self.indexFormatVersion,
            longLineCount:
                longLineCount
                ?? self.longLineCount
        )
    }
}
