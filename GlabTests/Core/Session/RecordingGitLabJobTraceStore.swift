import Foundation
@testable import Glab

actor RecordingGitLabJobTraceStore:
    GitLabJobTraceStoring
{
    private(set) var prepareCallCount = 0
    private(set) var removedAccountIDs:
        [GitLabAccountID] = []

    func prepare() {
        prepareCallCount += 1
    }

    func descriptor(
        for key: GitLabJobTraceKey
    ) -> GitLabJobTraceDescriptor? {
        nil
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        removedAccountIDs.append(accountID)
    }
}

actor GatedAccountRemovalResponseCache:
    GitLabResponseCaching
{
    private var hasStartedRemoval = false
    private var removalContinuation:
        CheckedContinuation<Void, Never>?

    func response(
        for key: GitLabResponseCacheKey
    ) -> GitLabCachedResponse? {
        nil
    }

    func store(
        _ response: GitLabCachedResponse,
        for key: GitLabResponseCacheKey
    ) {}

    func remove(
        for key: GitLabResponseCacheKey
    ) {}

    func removeAll(
        for account: GitLabCacheAccount
    ) async {
        hasStartedRemoval = true
        await withCheckedContinuation {
            removalContinuation = $0
        }
    }

    func waitUntilRemovalStarts() async {
        while !hasStartedRemoval {
            await Task.yield()
        }
    }

    func finishRemoval() {
        removalContinuation?.resume()
        removalContinuation = nil
    }
}
