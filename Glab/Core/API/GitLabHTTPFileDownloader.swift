import Foundation
import Synchronization

nonisolated enum GitLabHTTPFileDownloadError:
    Error,
    Equatable,
    Sendable,
    LocalizedError
{
    case invalidConfiguration
    case invalidResponse
    case responseTooLarge
    case incompleteResponse
    case unsuccessfulStatus(Int)
    case storageFailure
    case networkFailure

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "The download configuration was invalid."
        case .invalidResponse:
            "The download server returned an invalid response."
        case .responseTooLarge:
            "The download exceeded its size limit."
        case .incompleteResponse:
            "The download ended before all bytes arrived."
        case let .unsuccessfulStatus(status):
            "The download server returned HTTP \(status)."
        case .storageFailure:
            "The download could not be stored securely."
        case .networkFailure:
            "The download could not be completed."
        }
    }
}

nonisolated struct GitLabHTTPDownloadedFile:
    Sendable
{
    let fileURL: URL
    let response: HTTPURLResponse
    let byteCount: Int
}

nonisolated protocol GitLabHTTPFileDownloading:
    Sendable
{
    func download(
        for request: URLRequest,
        maximumByteCount: Int,
        temporaryDirectory: URL
    ) async throws -> GitLabHTTPDownloadedFile
}

nonisolated struct
    URLSessionGitLabHTTPFileDownloader:
    GitLabHTTPFileDownloading
{
    private let protocolClasses: [AnyClass]?

    init(
        protocolClasses: [AnyClass]? = nil
    ) {
        self.protocolClasses =
            protocolClasses
    }

    func download(
        for request: URLRequest,
        maximumByteCount: Int,
        temporaryDirectory: URL
    ) async throws -> GitLabHTTPDownloadedFile {
        guard
            maximumByteCount > 0,
            request.httpMethod == "GET",
            request.httpBody == nil,
            request.httpBodyStream == nil
        else {
            throw GitLabHTTPFileDownloadError
                .invalidConfiguration
        }
        try Self.validate(
            temporaryDirectory:
                temporaryDirectory
        )

        var request = request
        request.setValue(
            "identity",
            forHTTPHeaderField:
                "Accept-Encoding"
        )
        let redirectPolicy =
            try GitLabHTTPFileRedirectPolicy(
                initialRequest: request
            )
        let preparedFile = try Self
            .createTemporaryFile(
                in: temporaryDirectory
            )
        let delegate =
            GitLabHTTPFileDownloadDelegate(
                fileURL:
                    preparedFile.url,
                fileHandle:
                    preparedFile.handle,
                maximumByteCount:
                    maximumByteCount,
                redirectPolicy:
                    redirectPolicy
            )
        let configuration =
            URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy =
            .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy =
            .never
        configuration.httpShouldSetCookies =
            false
        configuration
            .urlCredentialStorage = nil
        if let protocolClasses {
            configuration.protocolClasses =
                protocolClasses
        }

        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount =
            1
        delegateQueue.qualityOfService =
            .userInitiated
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer {
            session.finishTasksAndInvalidate()
        }

        return try await delegate.download(
            request,
            using: session
        )
    }

    private static func validate(
        temporaryDirectory: URL
    ) throws {
        guard temporaryDirectory.isFileURL
        else {
            throw GitLabHTTPFileDownloadError
                .invalidConfiguration
        }
        do {
            let values =
                try temporaryDirectory
                .resourceValues(
                    forKeys: [
                        .isDirectoryKey,
                        .isSymbolicLinkKey,
                    ]
                )
            guard
                values.isDirectory == true,
                values.isSymbolicLink != true
            else {
                throw GitLabHTTPFileDownloadError
                    .invalidConfiguration
            }
        } catch
            let error
                as GitLabHTTPFileDownloadError
        {
            throw error
        } catch {
            throw GitLabHTTPFileDownloadError
                .storageFailure
        }
    }

    private static func createTemporaryFile(
        in directory: URL
    ) throws -> (
        url: URL,
        handle: FileHandle
    ) {
        let fileURL = directory.appending(
            path:
                ".glab-download-"
                + UUID().uuidString,
            directoryHint: .notDirectory
        )
        let fileManager = FileManager.default
        guard
            fileManager.createFile(
                atPath: fileURL.path,
                contents: nil,
                attributes: [
                    .protectionKey:
                        FileProtectionType
                        .completeUntilFirstUserAuthentication,
                ]
            )
        else {
            throw GitLabHTTPFileDownloadError
                .storageFailure
        }

        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedFileURL = fileURL
            try protectedFileURL
                .setResourceValues(values)
            let handle = try FileHandle(
                forWritingTo: fileURL
            )
            return (fileURL, handle)
        } catch {
            try? fileManager.removeItem(
                at: fileURL
            )
            throw GitLabHTTPFileDownloadError
                .storageFailure
        }
    }
}

/// `URLSession` invokes delegate callbacks synchronously on its delegate
/// queue. Every mutable value and every file-handle operation is protected by
/// the single mutex below, no protected reference escapes, and the lock is
/// never held across an `await`.
private nonisolated final class
    GitLabHTTPFileDownloadDelegate:
    NSObject,
    URLSessionDataDelegate,
    @unchecked Sendable
{
    private static let writeChunkByteCount =
        64 * 1_024

    private struct State {
        var continuation:
            CheckedContinuation<
                GitLabHTTPDownloadedFile,
                any Error
            >?
        var task: URLSessionDataTask?
        var response: HTTPURLResponse?
        var expectedByteCount: Int?
        var byteCount = 0
        var redirectState:
            GitLabHTTPFileRedirectState
        var cancellationRequested = false
        var isComplete = false
    }

    private let fileURL: URL
    private let fileHandle: FileHandle
    private let maximumByteCount: Int
    private let redirectPolicy:
        GitLabHTTPFileRedirectPolicy
    private let state: Mutex<State>

    init(
        fileURL: URL,
        fileHandle: FileHandle,
        maximumByteCount: Int,
        redirectPolicy:
            GitLabHTTPFileRedirectPolicy
    ) {
        self.fileURL = fileURL
        self.fileHandle = fileHandle
        self.maximumByteCount =
            maximumByteCount
        self.redirectPolicy =
            redirectPolicy
        state = Mutex(
            State(
                redirectState:
                    redirectPolicy.initialState
            )
        )
    }

    func download(
        _ request: URLRequest,
        using session: URLSession
    ) async throws -> GitLabHTTPDownloadedFile {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                continuation in
                let task =
                    session.dataTask(
                        with: request
                    )
                let shouldStart =
                    state.withLock {
                        state in
                        guard
                            !state
                                .cancellationRequested,
                            !state.isComplete
                        else {
                            return false
                        }
                        state.continuation =
                            continuation
                        state.task = task
                        return true
                    }
                if shouldStart {
                    task.resume()
                } else {
                    task.cancel()
                    closeAndRemoveFile()
                    continuation.resume(
                        throwing:
                            CancellationError()
                    )
                }
            }
        } onCancel: {
            cancel()
        }
    }

    private func cancel() {
        let task =
            state.withLock {
                state -> URLSessionDataTask? in
                state.cancellationRequested =
                    true
                return state.task
            }
        task?.cancel()
        finish(
            throwing: CancellationError()
        )
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler:
            @escaping @Sendable (
                URLSession.ResponseDisposition
            ) -> Void
    ) {
        guard
            let response =
                response
                    as? HTTPURLResponse
        else {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(
                throwing:
                    GitLabHTTPFileDownloadError
                    .invalidResponse
            )
            return
        }
        guard
            (200...299).contains(
                response.statusCode
            )
        else {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(
                throwing:
                    GitLabHTTPFileDownloadError
                    .unsuccessfulStatus(
                        response.statusCode
                    )
            )
            return
        }

        let advertisedByteCount =
            response.expectedContentLength
        guard
            advertisedByteCount
                <= Int64(
                    maximumByteCount
                )
        else {
            completionHandler(.cancel)
            dataTask.cancel()
            finish(
                throwing:
                    GitLabHTTPFileDownloadError
                    .responseTooLarge
            )
            return
        }

        let contentEncoding =
            response.value(
                forHTTPHeaderField:
                    "Content-Encoding"
            )?
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .lowercased()
        state.withLock { state in
            state.response = response
            if
                advertisedByteCount >= 0,
                contentEncoding == nil
                    || contentEncoding
                        == "identity"
            {
                state.expectedByteCount =
                    Int(
                        advertisedByteCount
                    )
            }
        }
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let acceptance =
            state.withLock { state in
                if state.isComplete {
                    return (
                        shouldContinue: false,
                        failure: nil
                            as (any Error)?
                    )
                }
                if state.cancellationRequested {
                    return (
                        shouldContinue: false,
                        failure:
                            CancellationError()
                                as any Error
                    )
                }
                let (observed, overflow) =
                    state.byteCount
                    .addingReportingOverflow(
                        data.count
                    )
                if
                    overflow
                    || observed
                        > maximumByteCount
                {
                    return (
                        shouldContinue: false,
                        failure:
                            GitLabHTTPFileDownloadError
                            .responseTooLarge
                                as any Error
                    )
                }
                return (
                    shouldContinue: true,
                    failure: nil
                )
            }
        guard acceptance.shouldContinue else {
            guard
                let failure =
                    acceptance.failure
            else {
                return
            }
            dataTask.cancel()
            finish(
                throwing: failure
            )
            return
        }

        var startIndex = data.startIndex
        while startIndex < data.endIndex {
            let endIndex = min(
                data.endIndex,
                startIndex
                    + Self
                    .writeChunkByteCount
            )
            let write =
                state.withLock {
                    state in
                    if state.isComplete {
                        return (
                            didWrite: false,
                            failure: nil
                                as (any Error)?
                        )
                    }
                    if
                        state
                            .cancellationRequested
                    {
                        return (
                            didWrite: false,
                            failure:
                                CancellationError()
                                    as any Error
                        )
                    }
                    do {
                        try fileHandle.write(
                            contentsOf:
                                data[
                                    startIndex
                                        ..< endIndex
                                ]
                        )
                        state.byteCount +=
                            endIndex
                            - startIndex
                        return (
                            didWrite: true,
                            failure: nil
                                as (any Error)?
                        )
                    } catch {
                        return (
                            didWrite: false,
                            failure:
                                GitLabHTTPFileDownloadError
                                .storageFailure
                                    as any Error
                        )
                    }
                }
            guard write.didWrite else {
                guard
                    let failure =
                        write.failure
                else {
                    return
                }
                dataTask.cancel()
                finish(
                    throwing: failure
                )
                return
            }
            startIndex = endIndex
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response:
            HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler:
            @escaping @Sendable (
                URLRequest?
            ) -> Void
    ) {
        do {
            let redirectState =
                state.withLock {
                    $0.redirectState
                }
            let decision =
                try redirectPolicy.redirect(
                    request,
                    from: redirectState
                )
            state.withLock {
                $0.redirectState =
                    decision.state
            }
            completionHandler(
                decision.request
            )
        } catch {
            completionHandler(nil)
            task.cancel()
            finish(throwing: error)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error:
            (any Error)?
    ) {
        if let error {
            let wasCancelled =
                state.withLock {
                    $0.cancellationRequested
                }
            finish(
                throwing:
                    wasCancelled
                    ? CancellationError()
                    : Self.networkError(
                        error
                    )
            )
        } else {
            finishSuccessfully()
        }
    }

    private func finishSuccessfully() {
        let outcome:
            Result<
                GitLabHTTPDownloadedFile,
                any Error
            > =
            state.withLock { state in
                guard
                    let response =
                        state.response
                else {
                    return .failure(
                        GitLabHTTPFileDownloadError
                            .invalidResponse
                    )
                }
                if
                    let expected =
                        state.expectedByteCount,
                    expected
                        != state.byteCount
                {
                    return .failure(
                        GitLabHTTPFileDownloadError
                            .incompleteResponse
                    )
                }
                return .success(
                    GitLabHTTPDownloadedFile(
                        fileURL: fileURL,
                        response: response,
                        byteCount:
                            state.byteCount
                    )
                )
            }
        finish(with: outcome)
    }

    private func finish(
        throwing error: any Error
    ) {
        finish(
            with: .failure(error)
        )
    }

    private func finish(
        with outcome:
            Result<
                GitLabHTTPDownloadedFile,
                any Error
            >
    ) {
        let continuation =
            state.withLock {
                state
                -> CheckedContinuation<
                    GitLabHTTPDownloadedFile,
                    any Error
                >? in
                guard !state.isComplete
                else {
                    return nil
                }
                state.isComplete = true
                state.task = nil
                let continuation =
                    state.continuation
                state.continuation = nil
                try? fileHandle.close()
                return continuation
            }
        guard let continuation else {
            return
        }

        switch outcome {
        case let .success(file):
            continuation.resume(
                returning: file
            )
        case let .failure(error):
            try? FileManager.default
                .removeItem(at: fileURL)
            continuation.resume(
                throwing: error
            )
        }
    }

    private func closeAndRemoveFile() {
        state.withLock { _ in
            try? fileHandle.close()
        }
        try? FileManager.default
            .removeItem(at: fileURL)
    }

    private static func networkError(
        _ error: any Error
    ) -> any Error {
        if error is CancellationError {
            return CancellationError()
        }
        return GitLabHTTPFileDownloadError
            .networkFailure
    }
}
