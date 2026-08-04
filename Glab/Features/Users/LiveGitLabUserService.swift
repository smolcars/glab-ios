import Foundation

nonisolated protocol GitLabUserServing: Sendable {
    func loadProfile(
        userID: Int,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabUserProfile>
            ) async -> Void
    ) async throws(GitLabSessionClientError)

    func loadStatus(
        userID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabUserStatus

    func loadGPGKeys(
        userID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabUserGPGKey]

    func setFollowed(
        _ isFollowed: Bool,
        userID: Int
    ) async throws(GitLabSessionClientError)
}

nonisolated struct LiveGitLabUserService:
    GitLabUserServing,
    Sendable
{
    private let client:
        any GitLabSessionRequestSending

    init(
        client: any GitLabSessionRequestSending
    ) {
        self.client = client
    }

    @concurrent
    func loadProfile(
        userID: Int,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabUserProfile>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        try await client.loadResponse(
            GitLabUserEndpoints.profile(
                userID: userID
            ),
            cachePolicy: .userProfile,
            refreshBehavior: refreshBehavior,
            onResponse: onResponse
        )
    }

    @concurrent
    func loadStatus(
        userID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabUserStatus
    {
        try await client.send(
            GitLabUserEndpoints.status(
                userID: userID
            )
        )
    }

    @concurrent
    func loadGPGKeys(
        userID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabUserGPGKey]
    {
        try await client.send(
            GitLabUserEndpoints.gpgKeys(
                userID: userID
            )
        )
    }

    @concurrent
    func setFollowed(
        _ isFollowed: Bool,
        userID: Int
    ) async throws(GitLabSessionClientError) {
        let endpoint = isFollowed
            ? GitLabUserEndpoints.follow(
                userID: userID
            )
            : GitLabUserEndpoints.unfollow(
                userID: userID
            )

        do {
            let _: GitLabEmptyResponse =
                try await client.send(endpoint)
            await client.invalidateCachedResponse(
                GitLabUserEndpoints.profile(
                    userID: userID
                )
            )
        } catch {
            if
                error.mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                await client.invalidateCachedResponse(
                    GitLabUserEndpoints.profile(
                        userID: userID
                    )
                )
            }
            throw error
        }
    }
}
