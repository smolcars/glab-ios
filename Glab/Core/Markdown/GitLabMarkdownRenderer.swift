import CryptoKit
import Foundation
import Observation

nonisolated struct GitLabMarkdownCacheKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let accountID: GitLabAccountID
    let resource: GitLabMarkdownResourceID
    let contentDigest: Data
    let rendererVersion: Int

    init(
        request: GitLabMarkdownRequest,
        rendererVersion: Int
    ) {
        accountID = request.accountID
        resource = request.resource
        contentDigest = Data(
            SHA256.hash(
                data: Data(request.source.utf8)
            )
        )
        self.rendererVersion = rendererVersion
    }

    var description: String {
        "GitLabMarkdownCacheKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated protocol GitLabMarkdownRendering:
    Sendable
{
    func render(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument
}

actor GitLabMarkdownRenderer:
    GitLabMarkdownRendering
{
    typealias Parser =
        @Sendable (
            GitLabMarkdownRequest
        ) async throws -> GitLabMarkdownDocument

    private struct CacheEntry {
        let document: GitLabMarkdownDocument
        let sourceCost: Int
        var lastAccess: UInt64
    }

    private struct InFlightRender {
        let identifier: UInt64
        let task:
            Task<GitLabMarkdownDocument, any Error>
        var waiters: Set<UUID>
    }

    private let maximumDocumentCount: Int
    private let maximumSourceCost: Int
    private let rendererVersion: Int
    private let parser: Parser
    private var cache:
        [GitLabMarkdownCacheKey: CacheEntry] = [:]
    private var inFlight:
        [GitLabMarkdownCacheKey: InFlightRender] = [:]
    private var accessCounter: UInt64 = 0
    private var renderCounter: UInt64 = 0

    init(
        maximumDocumentCount: Int = 32,
        maximumSourceCost: Int = 2 * 1_024 * 1_024,
        rendererVersion: Int = 1,
        parser: @escaping Parser =
            GitLabMarkdownParser.parse
    ) {
        precondition(maximumDocumentCount > 0)
        precondition(maximumSourceCost > 0)
        precondition(rendererVersion > 0)
        self.maximumDocumentCount =
            maximumDocumentCount
        self.maximumSourceCost =
            maximumSourceCost
        self.rendererVersion = rendererVersion
        self.parser = parser
    }

    func render(
        _ request: GitLabMarkdownRequest
    ) async throws -> GitLabMarkdownDocument {
        try Task.checkCancellation()
        let key = GitLabMarkdownCacheKey(
            request: request,
            rendererVersion: rendererVersion
        )

        if var cached = cache[key] {
            cached.lastAccess = nextAccess()
            cache[key] = cached
            return cached.document
        }

        let waiterID = UUID()
        let render = registerRender(
            for: key,
            request: request,
            waiterID: waiterID
        )

        return try await withTaskCancellationHandler {
            do {
                let document =
                    try await render.task.value
                try Task.checkCancellation()
                completeRender(
                    document,
                    key: key,
                    renderID: render.identifier,
                    sourceCost:
                        request.source.utf8.count
                )
                return document
            } catch {
                cancelWaiter(
                    waiterID,
                    key: key,
                    renderID: render.identifier
                )
                if Task.isCancelled {
                    throw CancellationError()
                }
                throw error
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    waiterID,
                    key: key,
                    renderID:
                        render.identifier
                )
            }
        }
    }

    var cacheEntryCount: Int {
        cache.count
    }

    var cacheSourceCost: Int {
        cache.values.reduce(0) {
            $0 + $1.sourceCost
        }
    }

    var inFlightCount: Int {
        inFlight.count
    }

    private func registerRender(
        for key: GitLabMarkdownCacheKey,
        request: GitLabMarkdownRequest,
        waiterID: UUID
    ) -> InFlightRender {
        if var existing = inFlight[key] {
            existing.waiters.insert(waiterID)
            inFlight[key] = existing
            return existing
        }

        renderCounter &+= 1
        let render = InFlightRender(
            identifier: renderCounter,
            task: Task {
                try await parser(request)
            },
            waiters: [waiterID]
        )
        inFlight[key] = render
        return render
    }

    private func completeRender(
        _ document: GitLabMarkdownDocument,
        key: GitLabMarkdownCacheKey,
        renderID: UInt64,
        sourceCost: Int
    ) {
        guard
            inFlight[key]?.identifier == renderID
        else {
            return
        }

        inFlight[key] = nil
        removeStaleEntries(for: key)
        guard sourceCost <= maximumSourceCost else {
            return
        }

        cache[key] = CacheEntry(
            document: document,
            sourceCost: sourceCost,
            lastAccess: nextAccess()
        )
        evictIfNeeded()
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        key: GitLabMarkdownCacheKey,
        renderID: UInt64
    ) {
        guard
            var render = inFlight[key],
            render.identifier == renderID,
            render.waiters.remove(waiterID) != nil
        else {
            return
        }

        guard render.waiters.isEmpty else {
            inFlight[key] = render
            return
        }

        inFlight[key] = nil
        render.task.cancel()
    }

    private func removeStaleEntries(
        for key: GitLabMarkdownCacheKey
    ) {
        cache = cache.filter {
            $0.key == key
                || $0.key.accountID != key.accountID
                || $0.key.resource != key.resource
        }
    }

    private func evictIfNeeded() {
        while
            cache.count > maximumDocumentCount
                || cacheSourceCost > maximumSourceCost
        {
            guard
                let leastRecentlyUsed = cache.min(
                    by: {
                        $0.value.lastAccess
                            < $1.value.lastAccess
                    }
                )?.key
            else {
                return
            }
            cache[leastRecentlyUsed] = nil
        }
    }

    private func nextAccess() -> UInt64 {
        accessCounter &+= 1
        return accessCounter
    }
}

nonisolated enum GitLabMarkdownModelState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded(GitLabMarkdownDocument)
    case failed(String)
}

@MainActor
@Observable
final class GitLabMarkdownModel {
    private(set) var state =
        GitLabMarkdownModelState.idle
    private(set) var failureMessage: String?

    private let renderer:
        any GitLabMarkdownRendering
    private var generation: UInt64 = 0

    init(renderer: any GitLabMarkdownRendering) {
        self.renderer = renderer
    }

    var document: GitLabMarkdownDocument? {
        guard case let .loaded(document) = state else {
            return nil
        }
        return document
    }

    func load(
        _ request: GitLabMarkdownRequest
    ) async {
        generation &+= 1
        let loadGeneration = generation
        let previousState = state
        let previousFailure = failureMessage

        if case .loaded = previousState {
            state = previousState
        } else {
            state = .loading
        }
        failureMessage = nil

        do {
            let document =
                try await renderer.render(request)
            guard
                !Task.isCancelled,
                generation == loadGeneration
            else {
                return
            }
            state = .loaded(document)
        } catch is CancellationError {
            guard generation == loadGeneration else {
                return
            }
            state = previousState
            failureMessage = previousFailure
        } catch {
            guard generation == loadGeneration else {
                return
            }
            let message = error.localizedDescription
            if case .loaded = previousState {
                state = previousState
                failureMessage = message
            } else {
                state = .failed(message)
                failureMessage = message
            }
        }
    }
}
