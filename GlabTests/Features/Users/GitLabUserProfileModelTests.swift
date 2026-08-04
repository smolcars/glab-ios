import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab user profile model")
struct GitLabUserProfileModelTests {
    @Test("Loads profile details and auxiliary data once")
    func loadsProfileOnce() async throws {
        let service = try UserProfileService(
            profiles: [.success(try makeTestUserProfile())]
        )
        let model = try makeModel(service: service)

        await model.loadIfNeeded()
        await model.loadIfNeeded()

        #expect(model.profile?.id == 42)
        #expect(model.status?.message == "Available")
        #expect(model.gpgKeysState == .loaded([]))
        #expect(
            await service.profileRequests == [
                UserProfileRequest(
                    userID: 42,
                    refreshBehavior: .ifStale
                )
            ]
        )
        #expect(await service.statusRequests == [42])
        #expect(await service.gpgKeyRequests == [42])
    }

    @Test("Follows and unfollows while keeping the count in sync")
    func togglesFollow() async throws {
        let service = try UserProfileService(
            profiles: [.success(try makeTestUserProfile())],
            mutationResults: [
                .success(()),
                .success(()),
            ]
        )
        let model = try makeModel(service: service)
        await model.loadIfNeeded()

        await model.toggleFollow()
        #expect(model.profile?.isFollowed == true)
        #expect(model.profile?.followers == 661)

        await model.toggleFollow()
        #expect(model.profile?.isFollowed == false)
        #expect(model.profile?.followers == 660)
        #expect(
            await service.mutationRequests == [
                UserFollowRequest(isFollowed: true, userID: 42),
                UserFollowRequest(isFollowed: false, userID: 42),
            ]
        )
    }

    @Test("Loads auxiliary data when cached profile refresh fails")
    func loadsAuxiliaryDataWithStaleProfile() async throws {
        let refreshError = GitLabSessionClientError
            .api(.connectivity(.timedOut))
        let service = try UserProfileService(
            profiles: [.success(try makeTestUserProfile())],
            profileFailureAfterResponse: refreshError
        )
        let model = try makeModel(service: service)

        await model.loadIfNeeded()

        #expect(model.profile?.id == 42)
        #expect(model.refreshError == refreshError)
        #expect(model.status?.message == "Available")
        #expect(model.gpgKeysState == .loaded([]))
    }

    @Test("Blocks follow mutations for a read-only account")
    func blocksReadOnlyFollow() async throws {
        let service = try UserProfileService(
            profiles: [.success(try makeTestUserProfile())]
        )
        let model = try makeModel(
            apiAccess: .readOnly,
            service: service
        )
        await model.loadIfNeeded()

        await model.toggleFollow()

        #expect(model.followFailure == .readOnly)
        #expect(model.profile?.isFollowed == false)
        #expect(await service.mutationRequests.isEmpty)
    }

    @Test("Preserves follow state after a rejected mutation")
    func preservesStateAfterRejectedMutation() async throws {
        let service = try UserProfileService(
            profiles: [.success(try makeTestUserProfile())],
            mutationResults: [.failure(.api(.forbidden))]
        )
        let model = try makeModel(service: service)
        await model.loadIfNeeded()

        await model.toggleFollow()

        #expect(model.profile?.isFollowed == false)
        #expect(model.profile?.followers == 660)
        #expect(
            model.followFailure
                == .mutation(.api(.forbidden), .rejected)
        )
    }
}

private extension GitLabUserProfileModelTests {
    func makeModel(
        apiAccess: GitLabAPIAccess = .readWrite,
        service: UserProfileService
    ) throws -> GitLabUserProfileModel {
        let accountID = GitLabAccountID(
            host: try GitLabHost("gitlab.example.com"),
            userID: 7
        )
        return GitLabUserProfileModel(
            route: GitLabUserRoute(
                id: 42,
                username: "alexexample",
                name: "Alex Example",
                avatarURL: nil
            ),
            accountID: accountID,
            apiAccess: apiAccess,
            currentUserID: 7,
            service: service,
            isAccountCurrent: { true }
        )
    }
}

private nonisolated struct UserProfileRequest:
    Equatable,
    Sendable
{
    let userID: Int
    let refreshBehavior: GitLabCacheRefreshBehavior
}

private nonisolated struct UserFollowRequest:
    Equatable,
    Sendable
{
    let isFollowed: Bool
    let userID: Int
}

private actor UserProfileService: GitLabUserServing {
    private var profiles: [
        Result<GitLabUserProfile, GitLabSessionClientError>
    ]
    private let status: GitLabUserStatus
    private let gpgKeys: [GitLabUserGPGKey]
    private var mutationResults: [
        Result<Void, GitLabSessionClientError>
    ]
    private let profileFailureAfterResponse:
        GitLabSessionClientError?

    private(set) var profileRequests: [UserProfileRequest] = []
    private(set) var statusRequests: [Int] = []
    private(set) var gpgKeyRequests: [Int] = []
    private(set) var mutationRequests: [UserFollowRequest] = []

    init(
        profiles: [
            Result<GitLabUserProfile, GitLabSessionClientError>
        ],
        profileFailureAfterResponse:
            GitLabSessionClientError? = nil,
        mutationResults: [
            Result<Void, GitLabSessionClientError>
        ] = []
    ) throws {
        self.profiles = profiles
        status = try JSONDecoder().decode(
            GitLabUserStatus.self,
            from: Data(
                #"{"emoji":"wave","availability":null,"message":"Available"}"#.utf8
            )
        )
        gpgKeys = []
        self.profileFailureAfterResponse =
            profileFailureAfterResponse
        self.mutationResults = mutationResults
    }

    func loadProfile(
        userID: Int,
        refreshBehavior: GitLabCacheRefreshBehavior,
        onResponse:
            @escaping @Sendable (
                GitLabAPIResponseEvent<GitLabUserProfile>
            ) async -> Void
    ) async throws(GitLabSessionClientError) {
        profileRequests.append(
            UserProfileRequest(
                userID: userID,
                refreshBehavior: refreshBehavior
            )
        )
        guard !profiles.isEmpty else {
            throw .api(.invalidResponse)
        }
        let profile = try profiles.removeFirst().get()
        await onResponse(
            GitLabAPIResponseEvent(
                value: profile,
                metadata: GitLabResponseMetadata(),
                source: .network
            )
        )
        if let profileFailureAfterResponse {
            throw profileFailureAfterResponse
        }
    }

    func loadStatus(
        userID: Int
    ) async throws(GitLabSessionClientError)
        -> GitLabUserStatus
    {
        statusRequests.append(userID)
        return status
    }

    func loadGPGKeys(
        userID: Int
    ) async throws(GitLabSessionClientError)
        -> [GitLabUserGPGKey]
    {
        gpgKeyRequests.append(userID)
        return gpgKeys
    }

    func setFollowed(
        _ isFollowed: Bool,
        userID: Int
    ) async throws(GitLabSessionClientError) {
        mutationRequests.append(
            UserFollowRequest(
                isFollowed: isFollowed,
                userID: userID
            )
        )
        guard !mutationResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        try mutationResults.removeFirst().get()
    }
}
