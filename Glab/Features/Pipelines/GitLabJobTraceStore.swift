import Foundation

nonisolated enum GitLabJobTraceStorageFormat {
    static let currentVersion = 1
}

nonisolated enum GitLabJobTraceIndexFormat {
    static let currentVersion = 1
    static let offsetByteCount =
        MemoryLayout<UInt32>.size
}

nonisolated enum
    GitLabJobTraceFailureCategory:
    String,
    Codable,
    CaseIterable,
    Equatable,
    Sendable
{
    case error
    case fatal
    case panic
    case exception
    case failed
    case traceback
}

nonisolated struct
    GitLabJobTraceFailureLocation:
    Codable,
    Equatable,
    Sendable
{
    let lineIndex: Int
    let category:
        GitLabJobTraceFailureCategory

    func isValid(
        forLineCount lineCount: Int
    ) -> Bool {
        lineIndex >= 0
            && lineIndex < lineCount
    }
}

nonisolated struct GitLabJobTraceKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let accountID: GitLabAccountID
    let route: GitLabJobTraceRoute

    init(
        accountID: GitLabAccountID,
        route: GitLabJobTraceRoute
    ) {
        self.accountID = accountID
        self.route = route
    }

    var description: String {
        "GitLabJobTraceKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var storageIdentifier: String {
        Self.lengthPrefixed([
            String(
                GitLabJobTraceStorageFormat
                    .currentVersion
            ),
            String(route.projectID),
            String(route.jobID),
        ])
    }

    private static func lengthPrefixed(
        _ components: [String]
    ) -> String {
        components.map {
            "\($0.utf8.count):\($0)"
        }
        .joined(separator: "|")
    }
}

nonisolated struct GitLabJobTraceDescriptor:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let key: GitLabJobTraceKey
    let traceFileURL: URL
    let indexFileURL: URL
    let byteCount: Int
    let lineCount: Int
    let storedAt: Date
    let rawContentDigest: String
    let longLineCount: Int
    let firstLikelyFailure:
        GitLabJobTraceFailureLocation?

    init(
        key: GitLabJobTraceKey,
        traceFileURL: URL,
        indexFileURL: URL,
        byteCount: Int,
        lineCount: Int,
        storedAt: Date,
        rawContentDigest: String,
        longLineCount: Int,
        firstLikelyFailure:
            GitLabJobTraceFailureLocation?
            = nil
    ) {
        self.key = key
        self.traceFileURL = traceFileURL
        self.indexFileURL = indexFileURL
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.storedAt = storedAt
        self.rawContentDigest =
            rawContentDigest
        self.longLineCount = longLineCount
        self.firstLikelyFailure =
            firstLikelyFailure
    }

    var hasLongLines: Bool {
        longLineCount > 0
    }

    var description: String {
        "GitLabJobTraceDescriptor(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated struct GitLabJobTraceImportWorkspace:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let key: GitLabJobTraceKey
    let directoryURL: URL
    let identifier: UUID

    init(
        key: GitLabJobTraceKey,
        directoryURL: URL,
        identifier: UUID
    ) {
        self.key = key
        self.directoryURL = directoryURL
        self.identifier = identifier
    }

    var description: String {
        "GitLabJobTraceImportWorkspace(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated struct GitLabJobTracePreparedEntry:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let traceFileURL: URL
    let indexFileURL: URL
    let byteCount: Int
    let lineCount: Int
    let rawContentDigest: String
    let indexFormatVersion: Int
    let longLineCount: Int
    let firstLikelyFailure:
        GitLabJobTraceFailureLocation?

    init(
        traceFileURL: URL,
        indexFileURL: URL,
        byteCount: Int,
        lineCount: Int,
        rawContentDigest: String,
        indexFormatVersion: Int,
        longLineCount: Int,
        firstLikelyFailure:
            GitLabJobTraceFailureLocation?
            = nil
    ) {
        self.traceFileURL = traceFileURL
        self.indexFileURL = indexFileURL
        self.byteCount = byteCount
        self.lineCount = lineCount
        self.rawContentDigest =
            rawContentDigest
        self.indexFormatVersion =
            indexFormatVersion
        self.longLineCount = longLineCount
        self.firstLikelyFailure =
            firstLikelyFailure
    }

    var description: String {
        "GitLabJobTracePreparedEntry(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated enum GitLabJobTraceStoreError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case invalidEntry
    case storage

    var errorDescription: String? {
        description
    }

    var description: String {
        switch self {
        case .invalidEntry:
            "The job log cache entry was invalid."
        case .storage:
            "The job log could not be stored securely."
        }
    }

    var debugDescription: String {
        description
    }
}

nonisolated protocol GitLabJobTraceStoring:
    Sendable
{
    func prepare() async

    func descriptor(
        for key: GitLabJobTraceKey
    ) async -> GitLabJobTraceDescriptor?

    func remove(
        for key: GitLabJobTraceKey
    ) async

    func removeAll(
        for accountID: GitLabAccountID
    ) async
}

nonisolated protocol
    GitLabJobTraceImportStoring:
    GitLabJobTraceStoring
{
    func beginImport(
        for key: GitLabJobTraceKey
    ) async throws
        -> GitLabJobTraceImportWorkspace

    func commit(
        _ prepared:
            GitLabJobTracePreparedEntry,
        in workspace:
            GitLabJobTraceImportWorkspace,
        storedAt: Date?
    ) async throws
        -> GitLabJobTraceDescriptor

    func discard(
        _ workspace:
            GitLabJobTraceImportWorkspace
    ) async
}

extension GitLabJobTraceImportStoring {
    func commit(
        _ prepared:
            GitLabJobTracePreparedEntry,
        in workspace:
            GitLabJobTraceImportWorkspace
    ) async throws
        -> GitLabJobTraceDescriptor
    {
        try await commit(
            prepared,
            in: workspace,
            storedAt: nil
        )
    }
}

actor InMemoryGitLabJobTraceStore:
    GitLabJobTraceStoring
{
    private var descriptors:
        [GitLabJobTraceKey: GitLabJobTraceDescriptor]

    init(
        descriptors:
            [GitLabJobTraceKey: GitLabJobTraceDescriptor]
            = [:]
    ) {
        self.descriptors = descriptors
    }

    func prepare() {}

    func descriptor(
        for key: GitLabJobTraceKey
    ) -> GitLabJobTraceDescriptor? {
        descriptors[key]
    }

    func store(
        _ descriptor: GitLabJobTraceDescriptor,
        for key: GitLabJobTraceKey
    ) {
        guard descriptor.key == key else {
            return
        }
        descriptors[key] = descriptor
    }

    func remove(
        for key: GitLabJobTraceKey
    ) {
        descriptors[key] = nil
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        descriptors = descriptors.filter {
            $0.key.accountID != accountID
        }
    }
}
