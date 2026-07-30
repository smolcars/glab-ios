import CryptoKit
import Foundation

nonisolated struct GitLabDiffRequest:
    Equatable,
    Sendable
{
    let accountID: GitLabAccountID
    let resource:
        GitLabDiffResourceIdentity
    let headSHA: String
    let oldPath: String
    let newPath: String
    let source: String

    init(
        accountID: GitLabAccountID,
        route: GitLabMergeRequestRoute,
        headSHA: String,
        oldPath: String,
        newPath: String,
        source: String
    ) {
        self.init(
            accountID: accountID,
            resource: .mergeRequest(route),
            headSHA: headSHA,
            oldPath: oldPath,
            newPath: newPath,
            source: source
        )
    }

    init(
        accountID: GitLabAccountID,
        projectID: Int,
        commitSHA: String,
        oldPath: String,
        newPath: String,
        source: String
    ) {
        self.init(
            accountID: accountID,
            resource: .commit(
                projectID: projectID,
                sha: commitSHA
            ),
            headSHA: commitSHA,
            oldPath: oldPath,
            newPath: newPath,
            source: source
        )
    }

    private init(
        accountID: GitLabAccountID,
        resource:
            GitLabDiffResourceIdentity,
        headSHA: String,
        oldPath: String,
        newPath: String,
        source: String
    ) {
        self.accountID = accountID
        self.resource = resource
        self.headSHA = headSHA
        self.oldPath = oldPath
        self.newPath = newPath
        self.source = source
    }
}

nonisolated struct GitLabDiffCacheKey:
    Equatable,
    Hashable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    let accountID: GitLabAccountID
    let resource:
        GitLabDiffResourceIdentity
    let headSHA: String
    let oldPath: String
    let newPath: String
    let parserVersion: Int
    let sourceDigest: Data

    init(
        request: GitLabDiffRequest,
        parserVersion: Int
    ) {
        accountID = request.accountID
        resource = request.resource
        headSHA = request.headSHA
        oldPath = request.oldPath
        newPath = request.newPath
        self.parserVersion = parserVersion
        sourceDigest = Data(
            SHA256.hash(
                data: Data(request.source.utf8)
            )
        )
    }

    var description: String {
        "GitLabDiffCacheKey(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

nonisolated protocol GitLabDiffRendering:
    Sendable
{
    func render(
        _ request: GitLabDiffRequest
    ) async throws -> GitLabParsedDiffDocument
}

actor GitLabDiffRenderer:
    GitLabDiffRendering
{
    typealias Parser =
        @Sendable (
            String
        ) async throws -> GitLabParsedDiffDocument

    private struct CacheEntry {
        let document: GitLabParsedDiffDocument
        let renderID: UInt64
        var lastAccess: UInt64
    }

    private struct InFlightRender {
        let identifier: UInt64
        let task:
            Task<GitLabParsedDiffDocument, any Error>
        var waiters: Set<UUID>
    }

    private let maximumDocumentCount: Int
    private let maximumEstimatedCost: Int
    private let parserVersion: Int
    private let parser: Parser
    private var cache:
        [GitLabDiffCacheKey: CacheEntry] = [:]
    private var inFlight:
        [GitLabDiffCacheKey: InFlightRender] = [:]
    private var accessCounter: UInt64 = 0
    private var renderCounter: UInt64 = 0

    init(
        maximumDocumentCount: Int = 8,
        maximumEstimatedCost: Int =
            16 * 1_024 * 1_024,
        parserVersion: Int = 1,
        parser: @escaping Parser =
            GitLabUnifiedDiffParser.parse
    ) {
        precondition(maximumDocumentCount > 0)
        precondition(maximumEstimatedCost > 0)
        precondition(parserVersion > 0)
        self.maximumDocumentCount =
            maximumDocumentCount
        self.maximumEstimatedCost =
            maximumEstimatedCost
        self.parserVersion = parserVersion
        self.parser = parser
    }

    func render(
        _ request: GitLabDiffRequest
    ) async throws -> GitLabParsedDiffDocument {
        try Task.checkCancellation()
        let key = GitLabDiffCacheKey(
            request: request,
            parserVersion: parserVersion
        )

        if var cached = cache[key] {
            cached.lastAccess = nextAccess()
            cache[key] = cached
            return cached.document
        }

        let waiterID = UUID()
        let render = registerRender(
            for: key,
            source: request.source,
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
                    renderID: render.identifier
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
                    renderID: render.identifier
                )
            }
        }
    }

    var cacheEntryCount: Int {
        cache.count
    }

    var cacheEstimatedCost: Int {
        cache.values.reduce(0) {
            $0 + $1.document.estimatedCacheCost
        }
    }

    var inFlightCount: Int {
        inFlight.count
    }

    private func registerRender(
        for key: GitLabDiffCacheKey,
        source: String,
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
                try await parser(source)
            },
            waiters: [waiterID]
        )
        inFlight[key] = render
        return render
    }

    private func completeRender(
        _ document: GitLabParsedDiffDocument,
        key: GitLabDiffCacheKey,
        renderID: UInt64
    ) {
        guard
            inFlight[key]?.identifier == renderID
        else {
            return
        }

        inFlight[key] = nil
        guard
            !hasNewerCachedVariant(
                than: renderID,
                for: key
            )
        else {
            return
        }
        removeStaleEntries(for: key)
        guard
            document.estimatedCacheCost
                <= maximumEstimatedCost
        else {
            return
        }

        cache[key] = CacheEntry(
            document: document,
            renderID: renderID,
            lastAccess: nextAccess()
        )
        evictIfNeeded()
    }

    private func cancelWaiter(
        _ waiterID: UUID,
        key: GitLabDiffCacheKey,
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
        for key: GitLabDiffCacheKey
    ) {
        cache = cache.filter {
            $0.key == key
                || !isSameFile(
                    $0.key,
                    key
                )
        }
    }

    private func hasNewerCachedVariant(
        than renderID: UInt64,
        for key: GitLabDiffCacheKey
    ) -> Bool {
        cache.contains {
            isSameFile($0.key, key)
                && $0.value.renderID > renderID
        }
    }

    private func isSameFile(
        _ first: GitLabDiffCacheKey,
        _ second: GitLabDiffCacheKey
    ) -> Bool {
        first.accountID == second.accountID
            && first.resource == second.resource
            && first.oldPath == second.oldPath
            && first.newPath == second.newPath
    }

    private func evictIfNeeded() {
        while
            cache.count > maximumDocumentCount
                || cacheEstimatedCost
                    > maximumEstimatedCost
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
