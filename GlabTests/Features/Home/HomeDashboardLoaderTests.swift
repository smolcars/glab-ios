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

        await client.waitUntilRequestCount(8)
        #expect(await client.requestCount == 8)
        #expect(await updates.updates.count >= 3)

        await client.releaseAll()
        try await load.value

        let receivedUpdates = await updates.updates
        #expect(receivedUpdates.count >= 10)
        #expect(
            await client.cachePolicies.filter {
                $0 == .profile
            }.count == 1
        )
        #expect(
            await client.cachePolicies.filter {
                $0 == .home
            }.count == 7
        )
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
            HomeDashboardSection.displayedCases.allSatisfy { section in
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

    @Test("Limits project previews to three rows")
    func limitsProjectPreviews() async throws {
        let projects = (1...4).map {
            GitLabHomeProject(
                id: $0,
                name: "Project \($0)",
                nameWithNamespace: "Group / Project \($0)",
                pathWithNamespace: "group/project-\($0)",
                webURL: nil
            )
        }
        let client = GatedDashboardRequestSender(
            projects: projects
        )
        let loader = LiveHomeDashboardLoader(client: client)
        let updates = DashboardUpdateCollector()

        let load = Task {
            try await loader.load(
                refreshBehavior: .ifStale
            ) {
                await updates.append($0)
            }
        }

        await client.waitUntilRequestCount(8)
        await client.releaseAll()
        try await load.value

        let recentProjectUpdates = await updates.updates.compactMap {
            if case let .section(.recentProjects, .success(items)) = $0 {
                return items
            }
            return nil
        }

        #expect(recentProjectUpdates.count == 2)
        #expect(
            recentProjectUpdates.allSatisfy {
                $0.map(\.id) == [
                    "project:1",
                    "project:2",
                    "project:3",
                ]
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
        private let projects: [GitLabHomeProject]
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
        private var countWaiters:
            [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        private(set) var requestCount = 0
        private(set) var refreshBehaviors:
            [GitLabCacheRefreshBehavior] = []
        private(set) var cachePolicies:
            [GitLabResponseCachePolicy] = []
        private var isReleased = false

        init(projects: [GitLabHomeProject] = []) {
            self.projects = projects
        }

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

            if !isReleased {
                await withCheckedContinuation {
                    releaseContinuations.append($0)
                }
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
            cachePolicies.append(cachePolicy)
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

            if !isReleased {
                await withCheckedContinuation {
                    releaseContinuations.append($0)
                }
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
            isReleased = true
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
                return projects as! Response
            }

            preconditionFailure("Unexpected dashboard response type")
        }
    }
}
