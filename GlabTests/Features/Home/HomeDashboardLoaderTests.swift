import Foundation
import Testing
@testable import Glab

@Suite("Home dashboard loader")
struct HomeDashboardLoaderTests {
    @Test("Starts every dashboard request independently")
    func startsRequestsConcurrently() async throws {
        let client = GatedDashboardRequestSender()
        let loader = LiveHomeDashboardLoader(client: client)

        let load = Task {
            try await loader.load()
        }

        await client.waitUntilRequestCount(6)
        #expect(await client.requestCount == 6)

        await client.releaseAll()
        let result = try await load.value

        #expect(result.user.isSuccess)
        #expect(
            HomeDashboardSection.allCases.allSatisfy {
                result.sections[$0]?.isSuccess == true
            }
        )
    }
}

private extension HomeDashboardLoaderTests {
    actor GatedDashboardRequestSender: GitLabSessionRequestSending {
        private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
        private var countWaiters:
            [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
        private(set) var requestCount = 0

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

private extension Result {
    var isSuccess: Bool {
        if case .success = self {
            true
        } else {
            false
        }
    }
}
