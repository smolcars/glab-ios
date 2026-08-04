import Foundation
import Observation

nonisolated enum GitLabUserProfileState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded(GitLabUserProfile)
    case failed(GitLabSessionClientError)
}

nonisolated enum GitLabUserGPGKeysState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case loaded([GitLabUserGPGKey])
    case failed(GitLabSessionClientError)
}

nonisolated enum GitLabUserFollowFailure:
    Equatable,
    LocalizedError,
    Sendable
{
    case readOnly
    case accountChanged
    case mutation(
        GitLabSessionClientError,
        GitLabMutationDeliveryCertainty
    )

    var errorDescription: String? {
        switch self {
        case .readOnly:
            "Following users requires GitLab API write access."
        case .accountChanged:
            "The active GitLab account changed."
        case let .mutation(error, certainty):
            if certainty == .deliveryUnknown {
                "GitLab may have received this change. "
                    + "The profile was refreshed before another attempt. "
                    + error.localizedDescription
            } else {
                error.localizedDescription
            }
        }
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .mutation(error, _) = self,
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }
}

@MainActor
@Observable
final class GitLabUserProfileModel {
    let route: GitLabUserRoute
    let accountID: GitLabAccountID
    let apiAccess: GitLabAPIAccess
    let currentUserID: Int

    private(set) var state =
        GitLabUserProfileState.idle
    private(set) var refreshError:
        GitLabSessionClientError?
    private(set) var status:
        GitLabUserStatus?
    private(set) var gpgKeysState =
        GitLabUserGPGKeysState.idle
    private(set) var isMutatingFollow = false
    private(set) var followFailure:
        GitLabUserFollowFailure?

    @ObservationIgnored
    private let service:
        any GitLabUserServing
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private var hasLoaded = false

    init(
        route: GitLabUserRoute,
        accountID: GitLabAccountID,
        apiAccess: GitLabAPIAccess,
        currentUserID: Int,
        service: any GitLabUserServing,
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.route = route
        self.accountID = accountID
        self.apiAccess = apiAccess
        self.currentUserID = currentUserID
        self.service = service
        self.isAccountCurrent = isAccountCurrent
    }

    var profile: GitLabUserProfile? {
        guard case let .loaded(profile) = state else {
            return nil
        }
        return profile
    }

    var isCurrentUser: Bool {
        route.id == currentUserID
    }

    var isFollowed: Bool? {
        profile?.isFollowed
    }

    var canToggleFollow: Bool {
        apiAccess.canWrite
            && !isCurrentUser
            && isFollowed != nil
            && !isMutatingFollow
            && isAccountCurrent()
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        if refreshError?.requiresReauthentication == true {
            return refreshError
        }
        if
            case let .failed(error) = state,
            error.requiresReauthentication
        {
            return error
        }
        if
            case let .failed(error) = gpgKeysState,
            error.requiresReauthentication
        {
            return error
        }
        return followFailure?.authenticationFailure
    }

    func loadIfNeeded() async {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        await loadProfile(
            refreshBehavior: .ifStale
        )
    }

    func refresh() async {
        hasLoaded = true
        await loadProfile(
            refreshBehavior: .always
        )
    }

    func retryGPGKeys() async {
        await loadGPGKeys()
    }

    func toggleFollow() async {
        guard !isMutatingFollow else {
            return
        }
        followFailure = nil

        guard isAccountCurrent() else {
            followFailure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            followFailure = .readOnly
            return
        }
        guard
            !isCurrentUser,
            let currentValue = isFollowed
        else {
            return
        }

        let desiredValue = !currentValue
        isMutatingFollow = true
        defer {
            isMutatingFollow = false
        }

        do {
            try await service.setFollowed(
                desiredValue,
                userID: route.id
            )
            guard isAccountCurrent() else {
                followFailure = .accountChanged
                return
            }
            applyFollowState(desiredValue)
        } catch {
            guard isAccountCurrent() else {
                return
            }
            let certainty =
                error.mutationDeliveryCertainty
            if certainty == .deliveryUnknown {
                await loadProfile(
                    refreshBehavior: .always,
                    loadsAuxiliaryData: false
                )
            }
            followFailure = .mutation(
                error,
                certainty
            )
        }
    }

    func dismissFollowFailure() {
        followFailure = nil
    }

    private func loadProfile(
        refreshBehavior:
            GitLabCacheRefreshBehavior,
        loadsAuxiliaryData: Bool = true
    ) async {
        let previousState = state
        let previousRefreshError = refreshError
        if profile == nil {
            state = .loading
        }
        refreshError = nil

        do {
            try await service.loadProfile(
                userID: route.id,
                refreshBehavior:
                    refreshBehavior
            ) { [weak self] event in
                await self?.apply(event)
            }

            guard !Task.isCancelled else {
                state = previousState
                refreshError = previousRefreshError
                return
            }

            if loadsAuxiliaryData {
                await loadAuxiliaryData()
            }
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                state = previousState
                refreshError = previousRefreshError
                return
            }

            if profile != nil {
                refreshError = error
                if loadsAuxiliaryData {
                    await loadAuxiliaryData()
                }
            } else {
                state = .failed(error)
            }
        }
    }

    private func loadAuxiliaryData() async {
        let service = service
        let userID = route.id
        if case .loaded = gpgKeysState {
            // Keep existing keys visible while refreshing.
        } else {
            gpgKeysState = .loading
        }

        await withTaskGroup(
            of: AuxiliaryResult.self
        ) { group in
            group.addTask {
                do {
                    return .status(
                        .success(
                            try await service.loadStatus(
                                userID: userID
                            )
                        )
                    )
                } catch {
                    let sessionError =
                        error as? GitLabSessionClientError
                        ?? .api(.transport)
                    return .status(.failure(sessionError))
                }
            }
            group.addTask {
                do {
                    return .gpgKeys(
                        .success(
                            try await service.loadGPGKeys(
                                userID: userID
                            )
                        )
                    )
                } catch {
                    let sessionError =
                        error as? GitLabSessionClientError
                        ?? .api(.transport)
                    return .gpgKeys(.failure(sessionError))
                }
            }

            for await result in group {
                guard
                    !Task.isCancelled,
                    isAccountCurrent()
                else {
                    continue
                }
                switch result {
                case let .status(.success(status)):
                    self.status = status
                case .status(.failure):
                    break
                case let .gpgKeys(.success(keys)):
                    gpgKeysState = .loaded(keys)
                case let .gpgKeys(.failure(error)):
                    gpgKeysState = .failed(error)
                }
            }
        }
    }

    private func loadGPGKeys() async {
        let previousState = gpgKeysState
        gpgKeysState = .loading
        do {
            let keys = try await service.loadGPGKeys(
                userID: route.id
            )
            guard
                !Task.isCancelled,
                isAccountCurrent()
            else {
                gpgKeysState = previousState
                return
            }
            gpgKeysState = .loaded(keys)
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled),
                isAccountCurrent()
            else {
                gpgKeysState = previousState
                return
            }
            gpgKeysState = .failed(error)
        }
    }

    private func apply(
        _ event:
            GitLabAPIResponseEvent<GitLabUserProfile>
    ) {
        state = .loaded(event.value)
        refreshError = nil
    }

    private func applyFollowState(
        _ isFollowed: Bool
    ) {
        guard var profile else {
            return
        }
        let previousValue = profile.isFollowed
        profile.isFollowed = isFollowed
        if
            previousValue != isFollowed,
            let followers = profile.followers
        {
            profile.followers = max(
                0,
                followers + (isFollowed ? 1 : -1)
            )
        }
        state = .loaded(profile)
        refreshError = nil
    }

    private nonisolated enum AuxiliaryResult:
        Sendable
    {
        case status(
            Result<
                GitLabUserStatus,
                GitLabSessionClientError
            >
        )
        case gpgKeys(
            Result<
                [GitLabUserGPGKey],
                GitLabSessionClientError
            >
        )
    }
}
