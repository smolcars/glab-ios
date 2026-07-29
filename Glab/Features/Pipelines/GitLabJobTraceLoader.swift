import Foundation

nonisolated enum GitLabJobTraceLoadError:
    Error,
    Equatable,
    Sendable,
    LocalizedError,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case noTrace
    case tooLarge
    case session(GitLabSessionClientError)
    case incomplete
    case unsafeRedirect
    case invalidTrace
    case storage
    case cancelled

    var description: String {
        switch self {
        case .noTrace:
            "GitLab did not return a job log."
        case .tooLarge:
            "This job log is too large to open safely."
        case let .session(error):
            error.description
        case .incomplete:
            "GitLab stopped sending the job log before it was complete."
        case .unsafeRedirect:
            "GitLab redirected the job log to an unsafe destination."
        case .invalidTrace:
            "The job log data was invalid."
        case .storage:
            "The job log could not be stored securely."
        case .cancelled:
            "The job log request was cancelled."
        }
    }

    var debugDescription: String {
        description
    }

    var errorDescription: String? {
        description
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .session(error) = self,
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }
}

nonisolated protocol GitLabJobTraceLoading:
    Sendable
{
    func cachedDescriptor(
        for key: GitLabJobTraceKey
    ) async -> GitLabJobTraceDescriptor?

    func loadTrace(
        for key: GitLabJobTraceKey
    ) async throws(GitLabJobTraceLoadError)
        -> GitLabJobTraceDescriptor
}

actor LiveGitLabJobTraceLoader:
    GitLabJobTraceLoading
{
    private let session:
        any GitLabRawFileSessionDownloading
    private let store:
        any GitLabJobTraceImportStoring
    private let indexer:
        GitLabJobTraceIndexer

    init(
        session:
            any GitLabRawFileSessionDownloading,
        store:
            any GitLabJobTraceImportStoring,
        indexer:
            GitLabJobTraceIndexer =
            GitLabJobTraceIndexer()
    ) {
        self.session = session
        self.store = store
        self.indexer = indexer
    }

    func cachedDescriptor(
        for key: GitLabJobTraceKey
    ) async -> GitLabJobTraceDescriptor? {
        await store.descriptor(for: key)
    }

    func loadTrace(
        for key: GitLabJobTraceKey
    ) async throws(GitLabJobTraceLoadError)
        -> GitLabJobTraceDescriptor
    {
        let workspace:
            GitLabJobTraceImportWorkspace
        do {
            try Task.checkCancellation()
            workspace =
                try await store.beginImport(
                    for: key
                )
        } catch {
            throw Self.map(error)
        }

        do {
            let downloaded =
                try await session
                .downloadRawFile(
                    GitLabJobTraceEndpoints
                        .trace(
                            at: key.route
                        ),
                    maximumByteCount:
                        GitLabJobTraceIndexer
                        .maximumTraceByteCount,
                    temporaryDirectory:
                        workspace
                        .directoryURL
                )
            try Task.checkCancellation()
            let prepared =
                try await indexer.prepare(
                    traceFileURL:
                        downloaded.fileURL,
                    byteCount:
                        downloaded.byteCount,
                    in: workspace
                )
            try Task.checkCancellation()
            return try await store.commit(
                prepared,
                in: workspace,
                storedAt: nil
            )
        } catch {
            await store.discard(workspace)
            throw Self.map(error)
        }
    }

    private static func map(
        _ error: any Error
    ) -> GitLabJobTraceLoadError {
        if let error =
            error as?
                GitLabJobTraceLoadError
        {
            return error
        }
        if error is CancellationError {
            return .cancelled
        }
        if let error =
            error as?
                GitLabRawFileSessionError
        {
            switch error {
            case .session(
                .api(.notFound)
            ):
                return .noTrace
            case .session(
                .api(.cancelled)
            ):
                return .cancelled
            case let .session(error):
                return .session(error)
            case .responseTooLarge:
                return .tooLarge
            case .incompleteResponse:
                return .incomplete
            case .unsafeRedirect:
                return .unsafeRedirect
            case .storageFailure:
                return .storage
            }
        }
        if let error =
            error as?
                GitLabJobTraceIndexingError
        {
            switch error {
            case .tooManyLines:
                return .tooLarge
            case .invalidFile:
                return .invalidTrace
            case .storageFailure:
                return .storage
            }
        }
        if
            error
                is GitLabJobTraceStoreError
        {
            return .storage
        }
        return .storage
    }
}
