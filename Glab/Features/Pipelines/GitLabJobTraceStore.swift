import Foundation

nonisolated enum GitLabJobTraceStorageFormat {
    static let currentVersion = 1
}

nonisolated enum GitLabJobTraceIndexFormat {
    static let currentVersion = 1
    static let offsetByteCount =
        MemoryLayout<UInt32>.size
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

    func removeAll(
        for accountID: GitLabAccountID
    ) async
}

nonisolated extension GitLabJobTraceStoring {
    func prepare() async {}
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

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        descriptors = descriptors.filter {
            $0.key.accountID != accountID
        }
    }
}
