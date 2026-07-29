import Foundation

actor PipelinePollGate {
    private var calls = 0
    private var waiters: [
        UUID:
            CheckedContinuation<
                Void,
                any Error
            >
    ] = [:]

    var callCount: Int {
        calls
    }

    func wait() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (
                    continuation:
                        CheckedContinuation<
                            Void,
                            any Error
                        >
                ) in
                calls += 1
                if Task.isCancelled {
                    continuation.resume(
                        throwing: CancellationError()
                    )
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task {
                await self.cancel(id: id)
            }
        }
    }

    func advance() {
        guard
            let id = waiters.keys.first,
            let continuation =
                waiters.removeValue(forKey: id)
        else {
            return
        }
        continuation.resume()
    }

    func waitUntilCallCount(
        _ expected: Int
    ) async {
        while calls < expected {
            await Task.yield()
        }
    }

    private func cancel(id: UUID) {
        waiters.removeValue(forKey: id)?
            .resume(
                throwing: CancellationError()
            )
    }
}
