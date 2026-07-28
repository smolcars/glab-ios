import Foundation
import Testing
@testable import Glab

@Suite("Home dashboard loader")
struct HomeDashboardLoaderTests {
    @Test("Starts every dashboard request independently")
    func startsRequestsConcurrently() async throws {
        let client = GatedDashboardRequestSender()
        let loader = LiveHomeDashboardLoader(client: client)
        let updates = DashboardUpdateCollector()

        let load = Task {
            try await loader.load(
                refreshBehavior: .ifStale
            ) {
                await updates.append($0)
            }
        }

        await client.waitUntilRequestCount(6)
        #expect(await client.requestCount == 6)
        #expect(await updates.updates.count == 6)

        await client.releaseAll()
        try await load.value

        let receivedUpdates = await updates.updates
        #expect(receivedUpdates.count == 12)
        #expect(
            receivedUpdates.contains {
                if case .user(.success) = $0 {
                    true
                } else {
                    false
                }
            }
        )
        #expect(
            HomeDashboardSection.allCases.allSatisfy { section in
                receivedUpdates.contains {
                    if case let .section(
                        receivedSection,
                        .success
                    ) = $0 {
                        receivedSection == section
                    } else {
                        false
                    }
                }
            }
        )
    }
}

private extension HomeDashboardLoaderTests {
    actor DashboardUpdateCollector {
        private(set) var updates: [HomeDashboardLoadUpdate] = []

        func append(_ update: HomeDashboardLoadUpdate) {
            updates.append(update)
        }
    }

    actor GatedDashboardRequestSender: GitLabSessionRequestSending {
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
        private var countWaiters:
            [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        private(set) var requestCount = 0
        private(set) var refreshBehaviors:
            [GitLabCacheRefreshBehavior] = []

        func send<Response>(
            _ endpoint: GitLabAPIRequest<Response>
        ) async throws(GitLabSessionClientError) -> Response {
            requestCount += 1
            let readyWaiters = countWaiters.filter {
                requestCount >= $0.count
            }
            countWaiters.removeAll {
                requestCount >= $0.count
            }
            readyWaiters.forEach {
                $0.continuation.resume()
            }

            await withCheckedContinuation {
                releaseContinuations.append($0)
            }

            return response(for: Response.self)
        }

        func loadResponse<Response>(
            _ endpoint: GitLabAPIRequest<Response>,
            cachePolicy: GitLabResponseCachePolicy,
            refreshBehavior: GitLabCacheRefreshBehavior,
            onResponse:
                @escaping @Sendable (
                    GitLabAPIResponseEvent<Response>
                ) async -> Void
        ) async throws(GitLabSessionClientError) {
            requestCount += 1
            refreshBehaviors.append(refreshBehavior)
            await onResponse(
                GitLabAPIResponseEvent(
                    value: response(for: Response.self),
                    metadata: GitLabResponseMetadata(),
                    source: .cache(.stale)
                )
            )

            let readyWaiters = countWaiters.filter {
                requestCount >= $0.count
            }
            countWaiters.removeAll {
                requestCount >= $0.count
            }
            readyWaiters.forEach {
                $0.continuation.resume()
            }

            await withCheckedContinuation {
                releaseContinuations.append($0)
            }

            await onResponse(
                GitLabAPIResponseEvent(
                    value: response(for: Response.self),
                    metadata: GitLabResponseMetadata(),
                    source: .network
                )
            )
        }

        func waitUntilRequestCount(_ count: Int) async {
            guard requestCount < count else {
                return
            }

            await withCheckedContinuation {
                countWaiters.append((count, $0))
            }
        }

        func releaseAll() {
            let continuations = releaseContinuations
            releaseContinuations.removeAll()
            continuations.forEach {
                $0.resume()
            }
        }

        private func response<Response>(
            for type: Response.Type
        ) -> Response {
            if type == GitLabAuthenticatedUser.self {
                return GitLabAuthenticatedUser(
                    id: 42,
                    username: "octocat",
                    name: "The Octocat",
                    avatarURL: nil
                ) as! Response
            }
            if type == [GitLabHomeIssue].self {
                return [GitLabHomeIssue]() as! Response
            }
            if type == [GitLabHomeMergeRequest].self {
                return [GitLabHomeMergeRequest]() as! Response
            }
            if type == [GitLabHomeProject].self {
                return [GitLabHomeProject]() as! Response
            }

            preconditionFailure("Unexpected dashboard response type")
        }
    }
}
