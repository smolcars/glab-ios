import Foundation
import Observation

@MainActor
@Observable
final class
    GitLabMergeRequestPipelineCreationModel
{
    let accountID: GitLabAccountID
    let route: GitLabMergeRequestRoute
    let apiAccess: GitLabAPIAccess

    private(set) var showsConfirmation =
        false
    private(set) var isCreating = false
    private(set) var failure:
        GitLabPipelineActionFailure?

    @ObservationIgnored
    private let service:
        any GitLabPipelineActionServing
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let isMergeRequestOpen:
        @MainActor () -> Bool
    @ObservationIgnored
    private let reconcile:
        @MainActor (GitLabPipeline) -> Void
    @ObservationIgnored
    private let refresh:
        @MainActor () async -> Void

    init(
        accountID: GitLabAccountID,
        route: GitLabMergeRequestRoute,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabPipelineActionServing,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        isMergeRequestOpen:
            @escaping @MainActor () -> Bool,
        reconcile:
            @escaping @MainActor (
                GitLabPipeline
            ) -> Void,
        refresh:
            @escaping @MainActor () async -> Void
    ) {
        self.accountID = accountID
        self.route = route
        self.apiAccess = apiAccess
        self.service = service
        self.isAccountCurrent =
            isAccountCurrent
        self.isMergeRequestOpen =
            isMergeRequestOpen
        self.reconcile = reconcile
        self.refresh = refresh
    }

    var canCreate: Bool {
        apiAccess.canWrite
            && isAccountCurrent()
            && isMergeRequestOpen()
            && !isCreating
            && !showsConfirmation
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    func request() {
        guard canCreate else {
            failure = preflightFailure
            return
        }
        failure = nil
        showsConfirmation = true
    }

    func dismissConfirmation() {
        guard !isCreating else {
            return
        }
        showsConfirmation = false
    }

    func dismissFailure() {
        failure = nil
    }

    func confirm() async {
        guard
            showsConfirmation,
            !isCreating
        else {
            return
        }
        showsConfirmation = false
        failure = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard isMergeRequestOpen() else {
            failure = .stale
            return
        }

        isCreating = true
        defer {
            isCreating = false
        }

        do {
            let pipeline =
                try await service
                .createMergeRequestPipeline(
                    at: route
                )
            guard isAccountCurrent() else {
                return
            }
            reconcile(pipeline)
            await refresh()
        } catch {
            guard isAccountCurrent() else {
                return
            }
            await refresh()
            failure = .mutation(
                error,
                error
                    .mutationDeliveryCertainty
            )
        }
    }
}

private extension
    GitLabMergeRequestPipelineCreationModel
{
    var preflightFailure:
        GitLabPipelineActionFailure
    {
        if !isAccountCurrent() {
            return .accountChanged
        }
        if !apiAccess.canWrite {
            return .readOnly
        }
        return .stale
    }
}
