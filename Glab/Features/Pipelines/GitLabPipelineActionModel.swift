import Foundation
import Observation

nonisolated enum GitLabPipelineActionKind:
    String,
    CaseIterable,
    Equatable,
    Hashable,
    Sendable
{
    case retryPipeline
    case cancelPipeline
    case retryJob
    case cancelJob
    case playJob

    var title: String {
        switch self {
        case .retryPipeline:
            "Retry pipeline"
        case .cancelPipeline:
            "Cancel pipeline"
        case .retryJob:
            "Retry job"
        case .cancelJob:
            "Cancel job"
        case .playJob:
            "Run job"
        }
    }

    var systemImage: String {
        switch self {
        case .retryPipeline, .retryJob:
            "arrow.clockwise"
        case .cancelPipeline, .cancelJob:
            "stop.circle"
        case .playJob:
            "play.fill"
        }
    }

    var consumesRunnerResources: Bool {
        switch self {
        case .retryPipeline,
             .retryJob,
             .playJob:
            true
        case .cancelPipeline,
             .cancelJob:
            false
        }
    }
}

nonisolated struct
    GitLabPipelineActionConfirmation:
    Equatable,
    Identifiable,
    Sendable
{
    let action: GitLabPipelineActionKind
    let jobID: Int?
    let affectedJobIDs: [Int]
    let resourceName: String
    let observedStatus: GitLabCIStatus

    var id: String {
        action.rawValue
            + ":"
            + String(jobID ?? 0)
            + ":"
            + observedStatus.rawValue
    }

    var title: String {
        action.title + "?"
    }

    var message: String {
        let actionDescription =
            switch action {
            case .retryPipeline:
                "Retry \(resourceName)."
            case .cancelPipeline:
                "Stop \(resourceName)."
            case .retryJob:
                "Retry \(resourceName)."
            case .cancelJob:
                "Stop \(resourceName)."
            case .playJob:
                "Run \(resourceName)."
            }
        if action.consumesRunnerResources {
            return actionDescription
                + " This can consume CI runner resources."
        }
        return actionDescription
    }
}

nonisolated enum GitLabPipelineActionFailure:
    Equatable,
    Sendable,
    LocalizedError
{
    case readOnly
    case accountChanged
    case stale
    case mutation(
        GitLabSessionClientError,
        GitLabMutationDeliveryCertainty
    )

    var errorDescription: String? {
        switch self {
        case .readOnly:
            "This action requires GitLab API write access."
        case .accountChanged:
            "The active GitLab account changed."
        case .stale:
            "The pipeline or job changed. Review its current state before trying again."
        case let .mutation(
            error,
            certainty
        ):
            if certainty == .deliveryUnknown {
                "GitLab may have received this action. "
                    + "The latest state was refreshed; verify it before trying again. "
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
final class GitLabPipelineActionModel {
    let accountID: GitLabAccountID
    let route: GitLabPipelineRoute
    let apiAccess: GitLabAPIAccess

    private(set) var confirmation:
        GitLabPipelineActionConfirmation?
    private(set) var activeAction:
        GitLabPipelineActionKind?
    private(set) var failure:
        GitLabPipelineActionFailure?

    @ObservationIgnored
    private let service:
        any GitLabPipelineActionServing
    @ObservationIgnored
    private let traceStore:
        any GitLabJobTraceStoring
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let currentPipeline:
        @MainActor () -> GitLabPipeline?
    @ObservationIgnored
    private let currentJobs:
        @MainActor () -> [GitLabPipelineJob]
    @ObservationIgnored
    private let reconcilePipeline:
        @MainActor (GitLabPipeline) -> Void
    @ObservationIgnored
    private let reconcileJob:
        @MainActor (GitLabPipelineJob) async -> Void
    @ObservationIgnored
    private let refresh:
        @MainActor () async -> Void

    init(
        accountID: GitLabAccountID,
        route: GitLabPipelineRoute,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabPipelineActionServing,
        traceStore:
            any GitLabJobTraceStoring,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        currentPipeline:
            @escaping @MainActor () -> GitLabPipeline?,
        currentJobs:
            @escaping @MainActor () -> [GitLabPipelineJob],
        reconcilePipeline:
            @escaping @MainActor (GitLabPipeline) -> Void,
        reconcileJob:
            @escaping @MainActor (GitLabPipelineJob) async -> Void,
        refresh:
            @escaping @MainActor () async -> Void
    ) {
        self.accountID = accountID
        self.route = route
        self.apiAccess = apiAccess
        self.service = service
        self.traceStore = traceStore
        self.isAccountCurrent =
            isAccountCurrent
        self.currentPipeline =
            currentPipeline
        self.currentJobs = currentJobs
        self.reconcilePipeline =
            reconcilePipeline
        self.reconcileJob = reconcileJob
        self.refresh = refresh
    }

    var isBusy: Bool {
        activeAction != nil
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    var availablePipelineActions:
        [GitLabPipelineActionKind]
    {
        guard
            canOfferActions,
            let pipeline = currentPipeline(),
            pipeline.id == route.pipelineID,
            pipeline.projectID == nil
                || pipeline.projectID
                    == route.projectID
        else {
            return []
        }
        switch pipeline.status.rawValue {
        case "failed", "canceled":
            return [.retryPipeline]
        case "created",
             "waiting_for_resource",
             "preparing",
             "waiting_for_callback",
             "pending",
             "running",
             "scheduled":
            return [.cancelPipeline]
        default:
            return []
        }
    }

    func availableJobActions(
        for job: GitLabPipelineJob
    ) -> [GitLabPipelineActionKind] {
        guard
            canOfferActions,
            Self.job(
                job,
                belongsTo: route
            )
        else {
            return []
        }
        switch job.status.rawValue {
        case "failed", "canceled":
            return [.retryJob]
        case "manual":
            return [.playJob]
        case "created",
             "waiting_for_resource",
             "preparing",
             "waiting_for_callback",
             "pending",
             "running",
             "scheduled":
            return [.cancelJob]
        default:
            return []
        }
    }

    func request(
        _ action: GitLabPipelineActionKind,
        job: GitLabPipelineJob? = nil
    ) {
        guard
            confirmation == nil,
            activeAction == nil
        else {
            return
        }
        failure = nil

        switch action {
        case .retryPipeline,
             .cancelPipeline:
            guard
                job == nil,
                availablePipelineActions
                    .contains(action),
                let pipeline =
                    currentPipeline()
            else {
                failure =
                    preflightFailure
                return
            }
            confirmation =
                GitLabPipelineActionConfirmation(
                    action: action,
                    jobID: nil,
                    affectedJobIDs: [],
                    resourceName:
                        "pipeline #\(pipeline.iid ?? pipeline.id)",
                    observedStatus:
                        pipeline.status
                )
        case .retryJob,
             .cancelJob,
             .playJob:
            guard
                let job,
                availableJobActions(for: job)
                    .contains(action)
            else {
                failure =
                    preflightFailure
                return
            }
            confirmation =
                GitLabPipelineActionConfirmation(
                    action: action,
                    jobID: job.id,
                    affectedJobIDs: [],
                    resourceName:
                        "job “\(job.name)”",
                    observedStatus:
                        job.status
                )
        }
    }

    func dismissConfirmation() {
        guard activeAction == nil else {
            return
        }
        confirmation = nil
    }

    func dismissFailure() {
        failure = nil
    }

    func confirm(
        _ presentedConfirmation:
            GitLabPipelineActionConfirmation? = nil
    ) async {
        guard
            let pendingConfirmation =
                presentedConfirmation
                ?? confirmation,
            activeAction == nil,
            confirmation == nil
                || confirmation
                    == pendingConfirmation
        else {
            return
        }
        self.confirmation = nil
        failure = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard
            isCurrent(
                pendingConfirmation
            )
        else {
            failure = .stale
            return
        }
        let confirmation =
            snapshotAffectedJobs(
                for:
                    pendingConfirmation
            )

        activeAction = confirmation.action
        defer {
            activeAction = nil
        }

        do {
            try await perform(
                confirmation
            )
            guard isAccountCurrent() else {
                return
            }
            await refresh()
        } catch {
            guard isAccountCurrent() else {
                return
            }
            let certainty =
                error.mutationDeliveryCertainty
            if certainty == .deliveryUnknown {
                await removeAffectedTraces(
                    for: confirmation
                )
            }
            await refresh()
            failure = .mutation(
                error,
                certainty
            )
        }
    }
}

private extension GitLabPipelineActionModel {
    var canOfferActions: Bool {
        apiAccess.canWrite
            && isAccountCurrent()
            && activeAction == nil
            && confirmation == nil
    }

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

    func isCurrent(
        _ confirmation:
            GitLabPipelineActionConfirmation
    ) -> Bool {
        if let jobID =
            confirmation.jobID
        {
            guard
                let job =
                    currentJobs()
                    .first(where: {
                        $0.id == jobID
                    })
            else {
                return false
            }
            return
                job.status
                    == confirmation
                    .observedStatus
                && availableJobActions(for: job)
                    .contains(
                        confirmation.action
                    )
        }
        guard
            let pipeline =
                currentPipeline()
        else {
            return false
        }
        return
            pipeline.status
                == confirmation
                .observedStatus
            && availablePipelineActions
                .contains(
                    confirmation.action
                )
    }

    func snapshotAffectedJobs(
        for confirmation:
            GitLabPipelineActionConfirmation
    ) -> GitLabPipelineActionConfirmation {
        guard
            confirmation.action
                == .cancelPipeline
        else {
            return confirmation
        }
        return GitLabPipelineActionConfirmation(
            action: confirmation.action,
            jobID: confirmation.jobID,
            affectedJobIDs:
                currentJobs()
                .filter {
                    !$0.status.isTerminal
                }
                .map(\.id),
            resourceName:
                confirmation.resourceName,
            observedStatus:
                confirmation.observedStatus
        )
    }

    func perform(
        _ confirmation:
            GitLabPipelineActionConfirmation
    ) async throws(GitLabSessionClientError) {
        switch confirmation.action {
        case .retryPipeline:
            reconcilePipeline(
                try await service
                    .retryPipeline(at: route)
            )
        case .cancelPipeline:
            reconcilePipeline(
                try await service
                    .cancelPipeline(at: route)
            )
            await removeTraces(
                jobIDs:
                    confirmation
                    .affectedJobIDs
            )
        case .retryJob:
            await reconcileJob(
                try await service.retryJob(
                    at:
                        try jobRoute(
                            confirmation
                        )
                )
            )
        case .cancelJob:
            let route =
                try jobRoute(confirmation)
            await reconcileJob(
                try await service.cancelJob(
                    at: route
                )
            )
            await removeTrace(
                jobID: route.jobID
            )
        case .playJob:
            await reconcileJob(
                try await service.playJob(
                    at:
                        try jobRoute(
                            confirmation
                        )
                )
            )
        }
    }

    func jobRoute(
        _ confirmation:
            GitLabPipelineActionConfirmation
    ) throws(GitLabSessionClientError)
        -> GitLabJobRoute
    {
        guard
            let jobID = confirmation.jobID,
            let route =
                GitLabJobRoute(
                    projectID:
                        self.route.projectID,
                    pipelineID:
                        self.route.pipelineID,
                    jobID: jobID
                )
        else {
            throw .api(.invalidResponse)
        }
        return route
    }

    func removeTrace(
        jobID: Int?
    ) async {
        guard
            let jobID,
            let route =
                GitLabJobTraceRoute(
                    projectID:
                        self.route.projectID,
                    jobID: jobID
                )
        else {
            return
        }
        await traceStore.remove(
            for:
                GitLabJobTraceKey(
                    accountID: accountID,
                    route: route
                )
        )
    }

    func removeAffectedTraces(
        for confirmation:
            GitLabPipelineActionConfirmation
    ) async {
        switch confirmation.action {
        case .cancelPipeline:
            await removeTraces(
                jobIDs:
                    confirmation
                    .affectedJobIDs
            )
        case .cancelJob:
            await removeTrace(
                jobID:
                    confirmation.jobID
            )
        case .retryPipeline,
             .retryJob,
             .playJob:
            break
        }
    }

    func removeTraces(
        jobIDs: [Int]
    ) async {
        for jobID in jobIDs {
            await removeTrace(
                jobID: jobID
            )
        }
    }

    static func job(
        _ job: GitLabPipelineJob,
        belongsTo route:
            GitLabPipelineRoute
    ) -> Bool {
        guard let pipeline = job.pipeline else {
            return true
        }
        return pipeline.id == route.pipelineID
            && (
                pipeline.projectID == nil
                    || pipeline.projectID
                        == route.projectID
            )
    }
}
