import Foundation

actor InMemoryGitLabResponseCache:
    GitLabResponseCaching
{
    private var responses:
        [GitLabResponseCacheKey: GitLabCachedResponse] = [:]
    private let currentDate: @Sendable () -> Date

    init(
        currentDate:
            @escaping @Sendable () -> Date = Date.init
    ) {
        self.currentDate = currentDate
    }

    func response(
        for key: GitLabResponseCacheKey
    ) -> GitLabCachedResponse? {
        guard let response = responses[key] else {
            return nil
        }

        let accessed = response.accessed(
            at: currentDate()
        )
        responses[key] = accessed
        return accessed
    }

    func store(
        _ response: GitLabCachedResponse,
        for key: GitLabResponseCacheKey
    ) {
        responses[key] = response
    }

    func remove(
        for key: GitLabResponseCacheKey
    ) {
        responses[key] = nil
    }

    func removeAll(
        for account: GitLabCacheAccount
    ) {
        responses = responses.filter {
            $0.key.account != account
        }
    }

    func responseCount() -> Int {
        responses.count
    }
}
