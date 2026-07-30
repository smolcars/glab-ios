import Foundation
import Observation

nonisolated enum GitLabIssuePlanningModelState:
    Equatable,
    Sendable
{
    case idle
    case loading
    case unavailable
    case supported(
        GitLabIssuePlanningSnapshot
    )
}

nonisolated enum GitLabIssuePlanningModelFailure:
    Equatable,
    Sendable,
    CustomStringConvertible
{
    case load(GitLabSessionClientError)
    case readOnly
    case permissionDenied
    case stale
    case mutation(
        GitLabSessionClientError,
        certainty:
            GitLabMutationDeliveryCertainty
    )
    case rejected
    case deliveryUnknown
    case reconciliation(
        GitLabSessionClientError
    )
    case notApplied

    var description: String {
        switch self {
        case .load:
            "Couldn’t load issue planning fields."
        case .readOnly:
            "This account has read-only API access."
        case .permissionDenied:
            "GitLab does not allow this account to update issue planning."
        case .stale:
            "These planning fields changed on GitLab. Review the latest values and try again."
        case let .mutation(error, certainty):
            certainty == .deliveryUnknown
                ? "GitLab may have applied this change. Check GitLab before trying again."
                : error.description
        case .rejected:
            "GitLab rejected this planning change."
        case .deliveryUnknown:
            "GitLab may have applied this change. Check GitLab before trying again."
        case .reconciliation:
            "The change was sent, but the latest issue could not be verified."
        case .notApplied:
            "GitLab did not apply this planning change."
        }
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        let error:
            GitLabSessionClientError? =
            switch self {
            case let .load(error),
                 let .reconciliation(error),
                 let .mutation(error, _):
                error
            default:
                nil
            }
        return error?.requiresReauthentication == true
            ? error
            : nil
    }
}

@MainActor
@Observable
final class GitLabIssuePlanningModel {
    private(set) var state:
        GitLabIssuePlanningModelState =
            .idle
    private(set) var milestones:
        [GitLabIssueMilestone] = []
    private(set) var iterations:
        [GitLabIssueIteration] = []
    private(set) var optionsError:
        GitLabSessionClientError?
    private(set) var failure:
        GitLabIssuePlanningModelFailure?
    private(set) var isLoadingOptions =
        false
    private(set) var isSaving = false
    private(set) var isCheckingGitLab =
        false

    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let service:
        any GitLabResourceEditing
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onIssueReconciled:
        @MainActor (GitLabIssue) -> Void
    @ObservationIgnored
    private var issue: GitLabIssue
    @ObservationIgnored
    private var pendingChange:
        GitLabIssuePlanningChange?

    init(
        issue: GitLabIssue,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabResourceEditing,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onIssueReconciled:
            @escaping @MainActor (
                GitLabIssue
            ) -> Void
    ) {
        self.issue = issue
        self.apiAccess = apiAccess
        self.service = service
        self.isAccountCurrent =
            isAccountCurrent
        self.onIssueReconciled =
            onIssueReconciled
        milestones =
            issue.milestone.map { [$0] }
            ?? []
        iterations =
            issue.iteration.map { [$0] }
            ?? []
    }

    var snapshot:
        GitLabIssuePlanningSnapshot?
    {
        guard
            case let .supported(snapshot) =
                state
        else {
            return nil
        }
        return snapshot
    }

    var selectedMilestoneID: Int? {
        if let snapshot {
            snapshot.milestoneID
        } else {
            issue.milestone?.id
        }
    }

    var selectedIterationID: Int? {
        if let snapshot {
            snapshot.iterationID
        } else {
            issue.iteration?.id
        }
    }

    var selectedMilestoneTitle: String {
        milestones.first {
            $0.id == selectedMilestoneID
        }?.title
            ?? issue.milestone?.title
            ?? "None"
    }

    var selectedIterationTitle: String {
        iterations.first {
            $0.id == selectedIterationID
        }?.displayTitle
            ?? issue.iteration?
                .displayTitle
            ?? "None"
    }

    var isBusy: Bool {
        isLoadingOptions
            || isSaving
            || isCheckingGitLab
            || state == .loading
    }

    var requiresDeliveryCheck: Bool {
        pendingChange != nil
    }

    var canEdit: Bool {
        apiAccess.canWrite
            && isAccountCurrent()
            && snapshot?.canUpdate == true
            && !isBusy
            && !requiresDeliveryCheck
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
            ?? (
                optionsError?
                    .requiresReauthentication
                    == true
                ? optionsError
                : nil
            )
    }

    func load() async {
        guard
            state == .idle
                || failure != nil
                || optionsError != nil
        else {
            return
        }
        guard isAccountCurrent() else {
            return
        }
        state = .loading
        failure = nil
        optionsError = nil
        isLoadingOptions = true
        let service = service
        let issue = issue

        async let milestoneResult:
            Result<
                [GitLabIssueMilestone],
                GitLabSessionClientError
            > = Self.capture {
                try await service
                    .loadIssueMilestones(
                        projectID:
                            issue.projectID
                    )
            }
        async let iterationResult:
            Result<
                [GitLabIssueIteration],
                GitLabSessionClientError
            > = Self.capture {
                try await service
                    .loadIssueIterations(
                        projectID:
                            issue.projectID
                    )
            }
        async let planningResult:
            Result<
                GitLabIssuePlanningAvailability,
                GitLabSessionClientError
            > = Self.capture {
                try await service
                    .loadIssuePlanning(
                        for: issue
                    )
            }
        let (
            loadedMilestones,
            loadedIterations,
            loadedPlanning
        ) = await (
            milestoneResult,
            iterationResult,
            planningResult
        )
        isLoadingOptions = false
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        switch loadedMilestones {
        case let .success(values):
            milestones =
                Self.includingCurrent(
                    issue.milestone,
                    in: values
                )
        case let .failure(error):
            optionsError = error
        }
        switch loadedIterations {
        case let .success(values):
            iterations =
                Self.includingCurrent(
                    issue.iteration,
                    in: values
                )
        case let .failure(error):
            optionsError =
                optionsError ?? error
        }
        switch loadedPlanning {
        case let .success(.supported(snapshot)):
            state = .supported(snapshot)
        case .success(.unavailable):
            state = .unavailable
        case let .failure(error):
            state = .unavailable
            failure = .load(error)
        }
    }

    func selectMilestone(
        _ milestone:
            GitLabIssueMilestone?
    ) async {
        if
            let milestone,
            !milestones.contains(milestone)
        {
            failure = .stale
            return
        }
        await apply(
            .milestone(milestone?.id)
        )
    }

    func selectIteration(
        _ iteration:
            GitLabIssueIteration?
    ) async {
        if
            let iteration,
            !iterations.contains(iteration)
        {
            failure = .stale
            return
        }
        await apply(
            .iteration(iteration?.id)
        )
    }

    func checkGitLab() async {
        guard
            let pendingChange,
            let baseline = snapshot,
            !isBusy,
            isAccountCurrent()
        else {
            return
        }
        isCheckingGitLab = true
        failure = nil
        defer {
            isCheckingGitLab = false
        }
        await service.invalidateAffectedReads(
            for: .issue(issue.route)
        )
        do {
            async let planning =
                service.refreshIssuePlanning(
                    projectPath:
                        baseline.projectPath,
                    issueIID:
                        baseline.issueIID
                )
            async let latest =
                service.loadLatest(
                    .issue(issue.route)
                )
            let (
                planningAvailability,
                result
            ) = try await (
                planning,
                latest
            )
            guard
                case let .supported(
                    refreshed
                ) = planningAvailability,
                case let .issue(
                    latestIssue
                ) = result,
                latestIssue.route
                    == issue.route
            else {
                failure = .notApplied
                return
            }
            state = .supported(refreshed)
            issue = latestIssue
            self.pendingChange = nil
            onIssueReconciled(latestIssue)
            if
                !Self.matches(
                    pendingChange,
                    snapshot: refreshed,
                    issue: latestIssue
                )
            {
                failure = .notApplied
            }
        } catch let error {
            failure =
                .reconciliation(
                    error
                        as? GitLabSessionClientError
                    ?? .api(.transport)
                )
        }
    }

    private func apply(
        _ change:
            GitLabIssuePlanningChange
    ) async {
        guard
            !isBusy,
            !requiresDeliveryCheck,
            isAccountCurrent(),
            let baseline = snapshot
        else {
            return
        }
        failure = nil
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        guard baseline.canUpdate else {
            failure = .permissionDenied
            return
        }
        guard
            !Self.matches(
                change,
                snapshot: baseline
            )
        else {
            return
        }

        isSaving = true
        defer {
            isSaving = false
        }
        do {
            let availability =
                try await service
                    .refreshIssuePlanning(
                        projectPath:
                            baseline.projectPath,
                        issueIID:
                            baseline.issueIID
                    )
            guard
                case let .supported(
                    fresh
                ) = availability,
                fresh == baseline
            else {
                if
                    case let .supported(
                        fresh
                    ) = availability
                {
                    state = .supported(fresh)
                }
                failure = .stale
                return
            }

            pendingChange = change
            let outcome =
                try await service
                    .updateIssuePlanning(
                        from: fresh,
                        change: change
                    )
            switch outcome {
            case let .updated(updated):
                guard
                    updated
                        == fresh.applying(
                            change
                        )
                else {
                    failure =
                        .deliveryUnknown
                    return
                }
                state = .supported(updated)
                await reconcile(
                    change,
                    snapshot: updated
                )
            case .rejected:
                pendingChange = nil
                failure = .rejected
            case .deliveryUnknown:
                failure = .deliveryUnknown
            }
        } catch let error {
            let certainty =
                error
                    .mutationDeliveryCertainty
            if certainty == .rejected {
                pendingChange = nil
            }
            failure =
                .mutation(
                    error,
                    certainty: certainty
                )
        }
    }

    private func reconcile(
        _ change:
            GitLabIssuePlanningChange,
        snapshot:
            GitLabIssuePlanningSnapshot
    ) async {
        await service.invalidateAffectedReads(
            for: .issue(issue.route)
        )
        do {
            let result =
                try await service.loadLatest(
                    .issue(issue.route)
                )
            guard
                case let .issue(
                    latestIssue
                ) = result,
                latestIssue.route
                    == issue.route,
                Self.matches(
                    change,
                    snapshot: snapshot,
                    issue: latestIssue
                )
            else {
                failure = .notApplied
                return
            }
            issue = latestIssue
            pendingChange = nil
            failure = nil
            onIssueReconciled(latestIssue)
        } catch let error {
            failure =
                .reconciliation(error)
        }
    }

    private static func matches(
        _ change:
            GitLabIssuePlanningChange,
        snapshot:
            GitLabIssuePlanningSnapshot
    ) -> Bool {
        switch change {
        case let .milestone(id):
            snapshot.milestoneID == id
        case let .iteration(id):
            snapshot.iterationID == id
        }
    }

    private static func matches(
        _ change:
            GitLabIssuePlanningChange,
        snapshot:
            GitLabIssuePlanningSnapshot,
        issue: GitLabIssue
    ) -> Bool {
        guard matches(
            change,
            snapshot: snapshot
        ) else {
            return false
        }
        switch change {
        case let .milestone(id):
            return issue.milestone?.id == id
        case let .iteration(id):
            return issue.iteration?.id == id
        }
    }

    private static func includingCurrent<
        Option: Identifiable
    >(
        _ current: Option?,
        in options: [Option]
    ) -> [Option] {
        guard
            let current,
            !options.contains(
                where: {
                    $0.id == current.id
                }
            )
        else {
            return options
        }
        return [current] + options
    }

    nonisolated private static func capture<
        Value: Sendable
    >(
        _ operation:
            @escaping @Sendable () async throws
                -> Value
    ) async -> Result<
        Value,
        GitLabSessionClientError
    > {
        do {
            return .success(
                try await operation()
            )
        } catch {
            return .failure(
                error
                    as? GitLabSessionClientError
                ?? .api(.transport)
            )
        }
    }
}
