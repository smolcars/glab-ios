import Foundation

actor GitLabReadRequestCoalescer {
    typealias Outcome = Result<
        GitLabRawAPIResponse,
        GitLabSessionClientError
    >

    private struct InFlightRead {
        let task: Task<Void, Never>
        var waiters: [
            UUID: CheckedContinuation<Outcome, Never>
        ]
    }

    private var reads: [
        GitLabResponseCacheKey: InFlightRead
    ] = [:]

    func response(
        for key: GitLabResponseCacheKey,
        operation:
            @escaping @Sendable () async -> Outcome
    ) async -> Outcome {
        let waiterID = UUID()

        return await withTaskCancellationHandler {
            await withCheckedContinuation {
                continuation in
                guard !Task.isCancelled else {
                    continuation.resume(
                        returning:
                            .failure(
                                .api(.cancelled)
                            )
                    )
                    return
                }

                addWaiter(
                    id: waiterID,
                    continuation: continuation,
                    key: key,
                    operation: operation
                )
            }
        } onCancel: {
            Task {
                await self.cancelWaiter(
                    id: waiterID,
                    key: key
                )
            }
        }
    }

    private func addWaiter(
        id: UUID,
        continuation:
            CheckedContinuation<Outcome, Never>,
        key: GitLabResponseCacheKey,
        operation:
            @escaping @Sendable () async -> Outcome
    ) {
        if var read = reads[key] {
            read.waiters[id] = continuation
            reads[key] = read
            return
        }

        let task = Task {
            let outcome = await operation()
            complete(
                key: key,
                outcome: outcome
            )
        }
        reads[key] = InFlightRead(
            task: task,
            waiters: [id: continuation]
        )
    }

    private func cancelWaiter(
        id: UUID,
        key: GitLabResponseCacheKey
    ) {
        guard
            var read = reads[key],
            let continuation =
                read.waiters.removeValue(forKey: id)
        else {
            return
        }

        continuation.resume(
            returning: .failure(.api(.cancelled))
        )

        if read.waiters.isEmpty {
            read.task.cancel()
            reads[key] = nil
        } else {
            reads[key] = read
        }
    }

    private func complete(
        key: GitLabResponseCacheKey,
        outcome: Outcome
    ) {
        guard let read = reads.removeValue(
            forKey: key
        ) else {
            return
        }

        for continuation in read.waiters.values {
            continuation.resume(returning: outcome)
        }
    }
}
