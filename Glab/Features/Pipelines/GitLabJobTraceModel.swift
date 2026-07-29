import Foundation
import Observation

nonisolated enum GitLabJobTraceSource:
    Equatable,
    Sendable
{
    case cache
    case network
    case refresh
}

nonisolated enum GitLabJobTraceState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case ready(
        GitLabJobTraceDescriptor,
        source: GitLabJobTraceSource
    )
    case empty(
        GitLabJobTraceDescriptor,
        source: GitLabJobTraceSource
    )
    case noTrace
    case tooLarge
    case failed(GitLabJobTraceLoadError)
}

typealias GitLabJobTraceDocumentFactory =
    @Sendable (
        GitLabJobTraceDescriptor
    ) -> GitLabJobTraceDocument

@MainActor
@Observable
final class GitLabJobTraceModel {
    nonisolated let accountID:
        GitLabAccountID
    nonisolated let context:
        GitLabJobTraceContext

    private(set) var state:
        GitLabJobTraceState = .idle
    private(set) var document:
        GitLabJobTraceDocument?
    private(set) var isRefreshing = false
    private(set) var refreshError:
        GitLabJobTraceLoadError?
    private(set) var searchQuery = ""
    private(set) var searchResult:
        GitLabJobTraceSearchResult = .empty
    private(set) var isSearching = false
    private(set) var searchError:
        GitLabJobTraceDocumentError?

    private enum LoadOutcome:
        Sendable
    {
        case cache(
            GitLabJobTraceDescriptor
        )
        case network(
            GitLabJobTraceDescriptor
        )
        case failure(
            GitLabJobTraceLoadError
        )
    }

    private struct LoadOperation {
        let id: UUID
        let task:
            Task<LoadOutcome, Never>
    }

    private enum SearchOutcome:
        Sendable
    {
        case result(
            GitLabJobTraceSearchResult
        )
        case failure(
            GitLabJobTraceDocumentError
        )
        case cancelled
    }

    private struct SearchOperation {
        let id: UUID
        let task:
            Task<SearchOutcome, Never>
    }

    private let loader:
        any GitLabJobTraceLoading
    private let documentFactory:
        GitLabJobTraceDocumentFactory
    private let isAccountCurrent:
        @MainActor () -> Bool
    private var generation: UInt64 = 0
    private var searchGeneration:
        UInt64 = 0
    private var loadOperation:
        LoadOperation?
    private var searchOperation:
        SearchOperation?

    init(
        accountID: GitLabAccountID,
        context: GitLabJobTraceContext,
        loader:
            any GitLabJobTraceLoading,
        documentFactory:
            @escaping
            GitLabJobTraceDocumentFactory = {
                GitLabJobTraceDocument(
                    descriptor: $0
                )
            },
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.accountID = accountID
        self.context = context
        self.loader = loader
        self.documentFactory =
            documentFactory
        self.isAccountCurrent =
            isAccountCurrent
    }

    var descriptor:
        GitLabJobTraceDescriptor?
    {
        switch state {
        case let .ready(
            descriptor,
            _
        ),
            let .empty(
                descriptor,
                _
            ):
            descriptor
        case .idle,
             .loading,
             .noTrace,
             .tooLarge,
             .failed:
            nil
        }
    }

    var source: GitLabJobTraceSource? {
        switch state {
        case let .ready(_, source),
             let .empty(_, source):
            source
        case .idle,
             .loading,
             .noTrace,
             .tooLarge,
             .failed:
            nil
        }
    }

    var canRefresh: Bool {
        descriptor != nil
            && !context.status.isTerminal
            && !isRefreshing
            && loadOperation == nil
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        if
            let authenticationFailure =
                refreshError?
                .authenticationFailure
        {
            return authenticationFailure
        }
        guard
            case let .failed(error) =
                state
        else {
            return nil
        }
        return error.authenticationFailure
    }

    func loadIfNeeded() async {
        if let operation = loadOperation {
            _ = await operation.task.value
            return
        }
        guard state == .idle else {
            return
        }

        state = .loading
        await beginInitialLoad()
    }

    func retry() async {
        let canRetry: Bool =
            switch state {
            case .noTrace,
                 .tooLarge,
                 .failed:
                true
            case .idle,
                 .loading,
                 .ready,
                 .empty:
                false
            }
        guard
            loadOperation == nil,
            canRetry
        else {
            return
        }

        state = .loading
        refreshError = nil
        await beginInitialLoad()
    }

    func refresh() async {
        guard canRefresh else {
            return
        }

        generation &+= 1
        let currentGeneration =
            generation
        let id = UUID()
        let key = traceKey
        let loader = loader
        let task =
            Task<LoadOutcome, Never> {
                do {
                    return .network(
                        try await loader
                            .loadTrace(
                                for: key
                            )
                    )
                } catch
                    let error as
                        GitLabJobTraceLoadError
                {
                    return .failure(error)
                } catch {
                    return .failure(.storage)
                }
            }
        loadOperation = LoadOperation(
            id: id,
            task: task
        )
        isRefreshing = true
        refreshError = nil

        let outcome = await task.value
        guard
            loadOperation?.id == id
        else {
            return
        }
        loadOperation = nil
        isRefreshing = false
        guard
            isValid(
                generation:
                    currentGeneration
            )
        else {
            return
        }

        switch outcome {
        case let .network(descriptor):
            await publish(
                descriptor,
                source: .refresh,
                generation:
                    currentGeneration
            )
        case let .failure(error):
            guard
                error
                    != GitLabJobTraceLoadError
                    .cancelled
            else {
                return
            }
            refreshError = error
        case .cache:
            break
        }
    }

    func search(_ query: String) async {
        searchOperation?.task.cancel()
        searchOperation = nil
        searchGeneration &+= 1
        let currentSearchGeneration =
            searchGeneration
        searchQuery = query
        searchError = nil

        guard
            let document,
            !query
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            .isEmpty
        else {
            searchResult = .empty
            isSearching = false
            return
        }

        let id = UUID()
        let task =
            Task<SearchOutcome, Never> {
                do {
                    return .result(
                        try await document
                            .search(query)
                    )
                } catch
                    let error as
                        GitLabJobTraceDocumentError
                {
                    return .failure(error)
                } catch is CancellationError {
                    return .cancelled
                } catch {
                    return .failure(
                        .invalidFile
                    )
                }
            }
        searchOperation =
            SearchOperation(
                id: id,
                task: task
            )
        isSearching = true

        let outcome = await task.value
        guard
            searchOperation?.id == id
        else {
            return
        }
        searchOperation = nil
        isSearching = false
        guard
            searchGeneration
                == currentSearchGeneration,
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        switch outcome {
        case let .result(result):
            searchResult = result
        case let .failure(error):
            searchResult = .empty
            searchError = error
        case .cancelled:
            break
        }
    }

    func selectNextMatch()
        async -> Int?
    {
        await selectMatch(step: 1)
    }

    func selectPreviousMatch()
        async -> Int?
    {
        await selectMatch(step: -1)
    }

    func cancel() async {
        generation &+= 1
        searchGeneration &+= 1
        loadOperation?.task.cancel()
        loadOperation = nil
        searchOperation?.task.cancel()
        searchOperation = nil
        isRefreshing = false
        isSearching = false
        if let document {
            await document.invalidate()
        }
        self.document = nil
        state = .idle
        refreshError = nil
        resetSearch()
    }

    private var traceKey:
        GitLabJobTraceKey
    {
        GitLabJobTraceKey(
            accountID: accountID,
            route: context.route
        )
    }

    private func beginInitialLoad() async {
        generation &+= 1
        let currentGeneration =
            generation
        let id = UUID()
        let key = traceKey
        let loader = loader
        let task =
            Task<LoadOutcome, Never> {
                if
                    let cached =
                        await loader
                        .cachedDescriptor(
                            for: key
                        )
                {
                    guard !Task.isCancelled
                    else {
                        return .failure(
                            .cancelled
                        )
                    }
                    return .cache(cached)
                }
                do {
                    return .network(
                        try await loader
                            .loadTrace(
                                for: key
                            )
                    )
                } catch
                    let error as
                        GitLabJobTraceLoadError
                {
                    return .failure(error)
                } catch {
                    return .failure(.storage)
                }
            }
        loadOperation = LoadOperation(
            id: id,
            task: task
        )

        let outcome = await task.value
        guard
            loadOperation?.id == id
        else {
            return
        }
        loadOperation = nil
        guard
            isValid(
                generation:
                    currentGeneration
            )
        else {
            return
        }

        switch outcome {
        case let .cache(descriptor):
            await publish(
                descriptor,
                source: .cache,
                generation:
                    currentGeneration
            )
        case let .network(descriptor):
            await publish(
                descriptor,
                source: .network,
                generation:
                    currentGeneration
            )
        case let .failure(error):
            publish(error)
        }
    }

    private func publish(
        _ descriptor:
            GitLabJobTraceDescriptor,
        source: GitLabJobTraceSource,
        generation expectedGeneration:
            UInt64
    ) async {
        guard
            isValid(
                generation:
                    expectedGeneration
            )
        else {
            return
        }
        guard
            isValid(descriptor)
        else {
            if source == .refresh {
                refreshError =
                    .invalidTrace
            } else {
                state =
                    .failed(
                        .invalidTrace
                    )
            }
            return
        }

        if let document {
            await document.invalidate()
            guard
                isValid(
                    generation:
                        expectedGeneration
                )
            else {
                return
            }
        }

        if descriptor.lineCount == 0 {
            document = nil
            state = .empty(
                descriptor,
                source: source
            )
        } else {
            document =
                documentFactory(
                    descriptor
                )
            state = .ready(
                descriptor,
                source: source
            )
        }
        resetSearch()
    }

    private func publish(
        _ error:
            GitLabJobTraceLoadError
    ) {
        guard error != .cancelled else {
            return
        }
        switch error {
        case .noTrace:
            state = .noTrace
        case .tooLarge:
            state = .tooLarge
        case .session,
             .incomplete,
             .unsafeRedirect,
             .invalidTrace,
             .storage:
            state = .failed(error)
        case .cancelled:
            break
        }
    }

    private func selectMatch(
        step: Int
    ) async -> Int? {
        let matches =
            searchResult.lineIndexes
        guard
            !matches.isEmpty,
            let document
        else {
            return nil
        }

        let current =
            searchResult
            .selectedMatchPosition
        let nextPosition: Int
        if let current {
            nextPosition =
                (
                    current
                        + step
                        + matches.count
                )
                % matches.count
        } else {
            nextPosition =
                step > 0
                ? 0
                : matches.count - 1
        }
        let lineIndex =
            matches[nextPosition]
        let expectedGeneration =
            generation
        let expectedSearchGeneration =
            searchGeneration

        do {
            _ = try await document
                .lines(
                    in:
                        lineIndex..<(lineIndex + 1)
                )
        } catch is CancellationError {
            return nil
        } catch
            let error as
                GitLabJobTraceDocumentError
        {
            searchError = error
            return nil
        } catch {
            searchError = .invalidFile
            return nil
        }
        guard
            isValid(
                generation:
                    expectedGeneration
            ),
            expectedSearchGeneration
                == searchGeneration
        else {
            return nil
        }

        searchResult =
            GitLabJobTraceSearchResult(
                lineIndexes: matches,
                selectedMatchPosition:
                    nextPosition,
                hasAdditionalMatches:
                    searchResult
                    .hasAdditionalMatches
            )
        return lineIndex
    }

    private func resetSearch() {
        searchOperation?.task.cancel()
        searchOperation = nil
        searchGeneration &+= 1
        searchQuery = ""
        searchResult = .empty
        isSearching = false
        searchError = nil
    }

    private func isValid(
        _ descriptor:
            GitLabJobTraceDescriptor
    ) -> Bool {
        guard
            descriptor.key == traceKey,
            descriptor.traceFileURL
                .isFileURL,
            descriptor.indexFileURL
                .isFileURL,
            descriptor.byteCount >= 0,
            descriptor.lineCount >= 0,
            descriptor.longLineCount >= 0,
            descriptor.longLineCount
                <= descriptor.lineCount,
            !descriptor
                .rawContentDigest
                .isEmpty
        else {
            return false
        }
        return descriptor
            .firstLikelyFailure?
            .isValid(
                forLineCount:
                    descriptor.lineCount
            )
            ?? true
    }

    private func isValid(
        generation expectedGeneration:
            UInt64
    ) -> Bool {
        generation
            == expectedGeneration
            && !Task.isCancelled
            && isAccountCurrent()
    }
}
