import Foundation
import Observation

@MainActor
final class GitLabProjectStarStateStore {
    private struct Key: Hashable {
        let accountID: GitLabAccountID
        let pathWithNamespace: String
    }

    private var states: [Key: Bool] = [:]

    func isStarred(
        for accountID: GitLabAccountID,
        pathWithNamespace: String
    ) -> Bool? {
        states[
            Key(
                accountID: accountID,
                pathWithNamespace:
                    pathWithNamespace
            )
        ]
    }

    func setIsStarred(
        _ isStarred: Bool,
        for accountID: GitLabAccountID,
        pathWithNamespace: String
    ) {
        states[
            Key(
                accountID: accountID,
                pathWithNamespace:
                    pathWithNamespace
            )
        ] = isStarred
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        states = states.filter {
            $0.key.accountID != accountID
        }
    }
}

nonisolated enum GitLabProjectStarState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case ready(isStarred: Bool)
    case failed(GitLabSessionClientError)
}

nonisolated enum GitLabProjectStarFailure:
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
            "Starring projects requires GitLab API write access."
        case .accountChanged:
            "The active GitLab account changed."
        case let .mutation(error, certainty):
            if certainty == .deliveryUnknown {
                "GitLab may have received this change. "
                    + "Verify the current star state before trying again. "
                    + error.localizedDescription
            } else {
                error.localizedDescription
            }
        }
    }

    var requiresProjectRefresh: Bool {
        guard case let .mutation(_, certainty) = self else {
            return false
        }
        return certainty == .deliveryUnknown
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

nonisolated struct GitLabProjectStarChange:
    Equatable,
    Sendable
{
    let project: GitLabProject
    let isStarred: Bool
}

@MainActor
@Observable
final class GitLabProjectStarModel {
    let accountID: GitLabAccountID
    let apiAccess: GitLabAPIAccess

    private(set) var state:
        GitLabProjectStarState
    private(set) var isMutating = false
    private(set) var failure:
        GitLabProjectStarFailure?

    @ObservationIgnored
    private let service:
        any GitLabProjectStarringServing
    @ObservationIgnored
    private let stateStore:
        GitLabProjectStarStateStore
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private var hasLoaded = false

    init(
        accountID: GitLabAccountID,
        apiAccess: GitLabAPIAccess,
        projectPathWithNamespace: String,
        initialIsStarred: Bool? = nil,
        service:
            any GitLabProjectStarringServing,
        stateStore:
            GitLabProjectStarStateStore,
        isAccountCurrent:
            @escaping @MainActor () -> Bool
    ) {
        self.accountID = accountID
        self.apiAccess = apiAccess
        self.service = service
        self.stateStore = stateStore
        self.isAccountCurrent =
            isAccountCurrent
        let isStarred =
            initialIsStarred
            ?? stateStore.isStarred(
                for: accountID,
                pathWithNamespace:
                    projectPathWithNamespace
            )
        if let initialIsStarred {
            stateStore.setIsStarred(
                initialIsStarred,
                for: accountID,
                pathWithNamespace:
                    projectPathWithNamespace
            )
        }
        state = isStarred.map {
            .ready(isStarred: $0)
        } ?? .idle
    }

    var isStarred: Bool? {
        guard case let .ready(isStarred) = state else {
            return nil
        }
        return isStarred
    }

    var canToggle: Bool {
        apiAccess.canWrite
            && isAccountCurrent()
            && isStarred != nil
            && !isMutating
    }

    var canRetry: Bool {
        guard
            apiAccess.canWrite,
            isAccountCurrent(),
            !isMutating,
            case .failed = state
        else {
            return false
        }
        return true
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        if
            case let .failed(error) = state,
            error.requiresReauthentication
        {
            return error
        }
        return failure?.authenticationFailure
    }

    func loadIfNeeded(
        project: GitLabProject
    ) async {
        guard
            apiAccess.canWrite,
            !hasLoaded,
            !isMutating
        else {
            return
        }
        hasLoaded = true
        await load(
            project: project,
            showsLoading: isStarred == nil
        )
    }

    func refresh(
        project: GitLabProject
    ) async {
        guard
            apiAccess.canWrite,
            !isMutating
        else {
            return
        }
        hasLoaded = true
        await load(
            project: project,
            showsLoading: isStarred == nil
        )
    }

    func toggle(
        project: GitLabProject
    ) async -> GitLabProjectStarChange? {
        guard !isMutating else {
            return nil
        }
        failure = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return nil
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return nil
        }
        guard let isStarred else {
            return nil
        }

        let desiredState = !isStarred
        isMutating = true
        defer {
            isMutating = false
        }

        do {
            let updatedProject =
                try await service.setStarred(
                    desiredState,
                    for: project
                )
            guard isAccountCurrent() else {
                failure = .accountChanged
                return nil
            }
            stateStore.setIsStarred(
                desiredState,
                for: accountID,
                pathWithNamespace:
                    project.pathWithNamespace
            )
            state = .ready(
                isStarred: desiredState
            )
            return GitLabProjectStarChange(
                project: updatedProject,
                isStarred: desiredState
            )
        } catch {
            guard isAccountCurrent() else {
                return nil
            }
            let certainty =
                error.mutationDeliveryCertainty
            if certainty == .deliveryUnknown {
                await load(
                    project: project,
                    showsLoading: false
                )
            }
            failure = .mutation(
                error,
                certainty
            )
            return nil
        }
    }

    func dismissFailure() {
        failure = nil
    }

    private func load(
        project: GitLabProject,
        showsLoading: Bool
    ) async {
        let previousState = state
        if showsLoading {
            state = .loading
        }

        do {
            let isStarred = try await service
                .isStarred(
                    project
                )
            guard isAccountCurrent() else {
                state = previousState
                return
            }
            stateStore.setIsStarred(
                isStarred,
                for: accountID,
                pathWithNamespace:
                    project.pathWithNamespace
            )
            state = .ready(
                isStarred: isStarred
            )
        } catch {
            guard isAccountCurrent() else {
                state = previousState
                return
            }
            if case .ready = previousState {
                state = previousState
            } else {
                state = .failed(error)
            }
        }
    }
}
