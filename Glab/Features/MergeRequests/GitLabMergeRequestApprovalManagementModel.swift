import Foundation
import Observation

nonisolated enum
    GitLabMergeRequestApprovalManagementAction:
    Equatable,
    Sendable
{
    case approve
    case unapprove
}

nonisolated enum
    GitLabMergeRequestApprovalManagementPhase:
    Equatable,
    Sendable
{
    case idle
    case preflighting
    case mutating
    case reconciling
    case checkingGitLab
}

nonisolated struct
    GitLabMergeRequestApprovalConfirmation:
    Equatable,
    Sendable
{
    let action:
        GitLabMergeRequestApprovalManagementAction
    let headSHA: String
}

nonisolated struct
    GitLabMergeRequestApprovalRuleAdditionConfirmation:
    Equatable,
    Sendable
{
    let ruleID: Int
    let ruleName: String
    let member: GitLabProjectMember
}

nonisolated enum
    GitLabMergeRequestApprovalManagementFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case load(
        GitLabSessionClientError
    )
    case readOnly
    case accountChanged
    case unavailable
    case staleRevision
    case approvalSyncing
    case permissionDenied
    case gitLabReauthenticationRequired
    case unsafeRule(
        GitLabMergeRequestApprovalRuleLockReason
    )
    case ruleChanged
    case memberUnavailable
    case memberOptions(
        GitLabSessionClientError
    )
    case rejected(
        GitLabSessionClientError
    )
    case deliveryUnknown
    case reconciliation(
        GitLabSessionClientError
    )
    case authoritativeMismatch
    case notApplied

    var authenticationFailure:
        GitLabSessionClientError?
    {
        switch self {
        case let .load(error),
             let .memberOptions(error),
             let .reconciliation(error):
            error.requiresReauthentication
                ? error
                : nil
        case .readOnly,
             .accountChanged,
             .unavailable,
             .staleRevision,
             .approvalSyncing,
             .permissionDenied,
             .gitLabReauthenticationRequired,
             .unsafeRule,
             .ruleChanged,
             .memberUnavailable,
             .rejected,
             .deliveryUnknown,
             .authoritativeMismatch,
             .notApplied:
            nil
        }
    }

    var description: String {
        "GitLabMergeRequestApprovalManagementFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }
}

@MainActor
@Observable
final class
    GitLabMergeRequestApprovalManagementModel
{
    private(set) var phase =
        GitLabMergeRequestApprovalManagementPhase
            .idle
    private(set) var failure:
        GitLabMergeRequestApprovalManagementFailure?
    private(set) var confirmation:
        GitLabMergeRequestApprovalConfirmation?
    private(set) var selectedRule:
        GitLabMergeRequestApprovalRule?
    private(set) var availableMembers:
        [GitLabProjectMember] = []
    private(set) var ruleAdditionConfirmation:
        GitLabMergeRequestApprovalRuleAdditionConfirmation?
    private(set) var memberOptionsError:
        GitLabSessionClientError?
    private(set) var isLoadingRule = false
    private(set) var isLoadingMembers = false

    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let route:
        GitLabMergeRequestRoute
    @ObservationIgnored
    private let accountID:
        GitLabAccountID
    @ObservationIgnored
    private let service:
        any GitLabMergeRequestApprovalServing
    @ObservationIgnored
    private let currentMergeRequest:
        @MainActor () -> GitLabMergeRequest?
    @ObservationIgnored
    private let currentApprovalSummary:
        @MainActor () -> GitLabMergeRequestApprovalSummary?
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onMergeRequestReconciled:
        @MainActor (
            GitLabMergeRequest
        ) -> Void
    @ObservationIgnored
    private let onApprovalSummaryReconciled:
        @MainActor (
            GitLabMergeRequestApprovalSummary
        ) -> Void
    @ObservationIgnored
    private var pendingMutation:
        PendingMutation?
    @ObservationIgnored
    private var selectedRuleBaseline:
        GitLabMergeRequestApprovalRuleMutationSnapshot?
    @ObservationIgnored
    private var pendingRuleMutation:
        PendingRuleMutation?
    @ObservationIgnored
    private var memberNextPageURL: URL?
    @ObservationIgnored
    private var memberSearch: String?
    @ObservationIgnored
    private var memberGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var ruleGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var operationGeneration:
        UInt64 = 0

    init(
        route: GitLabMergeRequestRoute,
        accountID: GitLabAccountID,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabMergeRequestApprovalServing,
        currentMergeRequest:
            @escaping @MainActor ()
                -> GitLabMergeRequest?,
        currentApprovalSummary:
            @escaping @MainActor ()
                -> GitLabMergeRequestApprovalSummary?,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onMergeRequestReconciled:
            @escaping @MainActor (
                GitLabMergeRequest
            ) -> Void,
        onApprovalSummaryReconciled:
            @escaping @MainActor (
                GitLabMergeRequestApprovalSummary
            ) -> Void
    ) {
        self.route = route
        self.accountID = accountID
        self.apiAccess = apiAccess
        self.service = service
        self.currentMergeRequest =
            currentMergeRequest
        self.currentApprovalSummary =
            currentApprovalSummary
        self.isAccountCurrent =
            isAccountCurrent
        self.onMergeRequestReconciled =
            onMergeRequestReconciled
        self.onApprovalSummaryReconciled =
            onApprovalSummaryReconciled
    }

    var isBusy: Bool {
        phase != .idle
    }

    var hasUnresolvedMutation: Bool {
        pendingMutation != nil
            || pendingRuleMutation != nil
    }

    var canLoadMoreMembers: Bool {
        memberNextPageURL != nil
            && !isLoadingMembers
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    var canApprove: Bool {
        canRequest(.approve)
    }

    var canUnapprove: Bool {
        canRequest(.unapprove)
    }

    func beginAddingApprover(
        to rule:
            GitLabMergeRequestApprovalRule
    ) async {
        guard
            phase == .idle,
            !isLoadingRule,
            pendingMutation == nil,
            pendingRuleMutation == nil,
            confirmation == nil,
            ruleAdditionConfirmation == nil
        else {
            return
        }
        failure = nil
        memberOptionsError = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        let presentation =
            GitLabMergeRequestApprovalRulePresentation(
                rule: rule
            )
        guard
            case .editable =
                presentation.editability,
            let ruleID = rule.id,
            ruleID > 0
        else {
            failure =
                Self.unsafeRuleFailure(
                    presentation
                        .editability
                )
            return
        }

        ruleGeneration &+= 1
        let generation =
            ruleGeneration
        isLoadingRule = true
        defer {
            if
                ruleGeneration
                    == generation
            {
                isLoadingRule = false
            }
        }

        let freshRule:
            GitLabMergeRequestApprovalRule
        do {
            freshRule =
                try await service
                    .loadApprovalRule(
                        at: route,
                        ruleID: ruleID
                    )
        } catch {
            guard canPublishRule(generation) else {
                return
            }
            failure = .load(error)
            return
        }

        guard canPublishRule(generation) else {
            return
        }
        guard
            freshRule.id == ruleID,
            let baseline =
                GitLabMergeRequestApprovalRuleMutationSnapshot(
                    rule: freshRule
                )
        else {
            failure = .ruleChanged
            return
        }

        selectedRule = freshRule
        selectedRuleBaseline = baseline
        ruleAdditionConfirmation = nil
        availableMembers = []
        memberNextPageURL = nil
        memberSearch = nil
        await loadMembers(
            search: nil
        )
    }

    func searchMembers(
        _ search: String
    ) async {
        await loadMembers(
            search:
                Self.normalizedSearch(
                    search
                )
        )
    }

    func loadNextMembersPage() async {
        guard
            let memberNextPageURL,
            let baseline =
                selectedRuleBaseline,
            !isLoadingMembers,
            isAccountCurrent()
        else {
            return
        }
        let generation =
            memberGeneration
        let search = memberSearch
        isLoadingMembers = true
        defer {
            if
                memberGeneration
                    == generation
            {
                isLoadingMembers = false
            }
        }

        do {
            let page =
                try await service
                    .loadMembersPage(
                        projectID:
                            route.projectID,
                        search: search,
                        after:
                            memberNextPageURL
                    )
            guard
                canPublishMembers(
                    generation,
                    baseline: baseline
                )
            else {
                return
            }
            availableMembers =
                Self.mergedMembers(
                    availableMembers,
                    candidates(
                        from: page.items,
                        baseline: baseline
                    )
                )
            self.memberNextPageURL =
                page.nextPageURL
            memberOptionsError = nil
            if case .memberOptions =
                failure
            {
                failure = nil
            }
        } catch {
            guard
                canPublishMembers(
                    generation,
                    baseline: baseline
                )
            else {
                return
            }
            memberOptionsError = error
            failure = .memberOptions(error)
        }
    }

    func selectApprover(
        _ member: GitLabProjectMember
    ) {
        guard
            phase == .idle,
            pendingMutation == nil,
            pendingRuleMutation == nil,
            confirmation == nil,
            let rule = selectedRule,
            let ruleID = rule.id,
            let ruleName = rule.name,
            member.isActive,
            availableMembers.contains(
                where: {
                    $0.id == member.id
                }
            )
        else {
            return
        }

        ruleAdditionConfirmation =
            GitLabMergeRequestApprovalRuleAdditionConfirmation(
                ruleID: ruleID,
                ruleName: ruleName,
                member: member
            )
    }

    func cancelRuleAddition() {
        guard
            phase == .idle,
            pendingRuleMutation == nil
        else {
            return
        }
        ruleAdditionConfirmation = nil
        selectedRule = nil
        selectedRuleBaseline = nil
        availableMembers = []
        memberNextPageURL = nil
        memberSearch = nil
        memberOptionsError = nil
        isLoadingRule = false
        isLoadingMembers = false
        memberGeneration &+= 1
        ruleGeneration &+= 1
    }

    func cancelRuleAdditionConfirmation() {
        guard
            phase == .idle,
            pendingRuleMutation == nil
        else {
            return
        }
        ruleAdditionConfirmation = nil
    }

    func requestApprove() {
        request(.approve)
    }

    func requestUnapprove() {
        request(.unapprove)
    }

    func cancelConfirmation() {
        confirmation = nil
    }

    func confirmAction() async {
        guard
            phase == .idle,
            pendingMutation == nil,
            pendingRuleMutation == nil,
            let confirmation
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
            let rendered =
                currentMergeRequest(),
            rendered.route == route,
            rendered.stateKind == .opened,
            rendered.diffHeadSHA
                == confirmation.headSHA
        else {
            failure = .staleRevision
            return
        }
        guard
            !Self.isApprovalSyncing(
                rendered
            )
        else {
            failure = .approvalSyncing
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        phase = .preflighting
        defer {
            if
                operationGeneration
                    == generation
            {
                phase = .idle
            }
        }

        let freshMergeRequest:
            GitLabMergeRequest
        do {
            freshMergeRequest =
                try await service
                    .loadLatestMergeRequest(
                        at: route
                    )
        } catch {
            publishReadFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onMergeRequestReconciled(
            freshMergeRequest
        )
        guard
            freshMergeRequest.route
                == route
        else {
            failure =
                .authoritativeMismatch
            return
        }
        guard
            freshMergeRequest.stateKind
                == .opened,
            freshMergeRequest.diffHeadSHA
                == confirmation.headSHA
        else {
            failure = .staleRevision
            return
        }
        guard
            !Self.isApprovalSyncing(
                freshMergeRequest
            )
        else {
            failure = .approvalSyncing
            return
        }

        let freshSummary:
            GitLabMergeRequestApprovalSummary
        do {
            freshSummary =
                try await service
                    .loadApprovalSummary(
                        at: route
                    )
        } catch {
            publishReadFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onApprovalSummaryReconciled(
            freshSummary
        )
        guard
            Self.requiresMutation(
                confirmation.action,
                summary: freshSummary,
                userID: accountID.userID
            )
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let pending =
            PendingMutation(
                action:
                    confirmation.action,
                route: route,
                headSHA:
                    confirmation.headSHA,
                userID:
                    accountID.userID
            )
        pendingMutation = pending
        failure = .deliveryUnknown
        phase = .mutating

        do {
            switch confirmation.action {
            case .approve:
                _ = try await service.approve(
                    at: route,
                    sha:
                        confirmation.headSHA
                )
            case .unapprove:
                _ = try await service
                    .unapprove(at: route)
            }
        } catch {
            handleMutationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        phase = .reconciling
        await reconcilePendingMutation(
            generation: generation
        )
    }

    func confirmRuleAddition() async {
        guard
            phase == .idle,
            pendingMutation == nil,
            pendingRuleMutation == nil,
            confirmation == nil,
            let confirmation =
                ruleAdditionConfirmation,
            let baseline =
                selectedRuleBaseline,
            baseline.ruleID
                == confirmation.ruleID
        else {
            return
        }
        ruleAdditionConfirmation = nil
        failure = nil

        guard isAccountCurrent() else {
            failure = .accountChanged
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        phase = .preflighting
        defer {
            if
                operationGeneration
                    == generation
            {
                phase = .idle
            }
        }

        let freshRule:
            GitLabMergeRequestApprovalRule
        do {
            freshRule =
                try await service
                    .loadApprovalRule(
                        at: route,
                        ruleID:
                            confirmation
                                .ruleID
                    )
        } catch {
            publishReadFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        guard
            let freshBaseline =
                GitLabMergeRequestApprovalRuleMutationSnapshot(
                    rule: freshRule
                ),
            baseline.hasSameBaseline(
                as: freshBaseline
            )
        else {
            selectedRule = freshRule
            selectedRuleBaseline =
                GitLabMergeRequestApprovalRuleMutationSnapshot(
                    rule: freshRule
                )
            failure = .ruleChanged
            return
        }
        guard
            !freshBaseline.userIDs
                .contains(
                    confirmation.member.id
                ),
            !(freshRule
                .eligibleApprovers
                ?? [])
                .contains(
                    where: {
                        $0.id
                            == confirmation
                            .member.id
                    }
                ),
            let replacement =
                freshBaseline
                .replacement(
                    adding:
                        confirmation
                            .member.id
                )
        else {
            selectedRule = freshRule
            selectedRuleBaseline =
                freshBaseline
            failure =
                .memberUnavailable
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let pending =
            PendingRuleMutation(
                route: route,
                baseline: freshBaseline,
                member:
                    confirmation.member
            )
        pendingRuleMutation = pending
        failure = .deliveryUnknown
        phase = .mutating

        let response:
            GitLabMergeRequestApprovalRule
        do {
            response =
                try await service
                    .updateApprovalRule(
                        at: route,
                        ruleID:
                            freshBaseline
                                .ruleID,
                        replacement:
                            replacement
                    )
        } catch {
            handleRuleMutationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        guard
            freshBaseline.result(
                for: response,
                adding:
                    confirmation.member.id
            ) == .applied
        else {
            failure = .deliveryUnknown
            return
        }

        phase = .reconciling
        await reconcilePendingRuleMutation(
            generation: generation
        )
    }

    func checkGitLab() async {
        guard
            phase == .idle,
            (
                pendingMutation != nil
                    || pendingRuleMutation
                    != nil
            ),
            isAccountCurrent()
        else {
            return
        }

        operationGeneration &+= 1
        let generation =
            operationGeneration
        phase = .checkingGitLab
        defer {
            if
                operationGeneration
                    == generation
            {
                phase = .idle
            }
        }

        if pendingRuleMutation != nil {
            await reconcilePendingRuleMutation(
                generation: generation
            )
        } else {
            await reconcilePendingMutation(
                generation: generation
            )
        }
    }
}

private extension
    GitLabMergeRequestApprovalManagementModel
{
    nonisolated struct PendingMutation:
        Equatable,
        Sendable
    {
        let action:
            GitLabMergeRequestApprovalManagementAction
        let route:
            GitLabMergeRequestRoute
        let headSHA: String
        let userID: Int
    }

    nonisolated struct PendingRuleMutation:
        Equatable,
        Sendable
    {
        let route:
            GitLabMergeRequestRoute
        let baseline:
            GitLabMergeRequestApprovalRuleMutationSnapshot
        let member: GitLabProjectMember
    }

    func request(
        _ action:
            GitLabMergeRequestApprovalManagementAction
    ) {
        guard
            phase == .idle,
            confirmation == nil,
            pendingMutation == nil,
            pendingRuleMutation == nil,
            selectedRule == nil,
            ruleAdditionConfirmation
                == nil
        else {
            return
        }
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
            let mergeRequest =
                currentMergeRequest(),
            mergeRequest.route == route,
            mergeRequest.stateKind
                == .opened,
            let headSHA =
                mergeRequest.diffHeadSHA,
            let summary =
                currentApprovalSummary()
        else {
            failure = .unavailable
            return
        }
        guard
            !Self.isApprovalSyncing(
                mergeRequest
            )
        else {
            failure = .approvalSyncing
            return
        }
        guard
            Self.requiresMutation(
                action,
                summary: summary,
                userID:
                    accountID.userID
            )
        else {
            return
        }

        confirmation =
            GitLabMergeRequestApprovalConfirmation(
                action: action,
                headSHA: headSHA
            )
    }

    func canRequest(
        _ action:
            GitLabMergeRequestApprovalManagementAction
    ) -> Bool {
        guard
            apiAccess.canWrite,
            isAccountCurrent(),
            phase == .idle,
            confirmation == nil,
            pendingMutation == nil,
            pendingRuleMutation == nil,
            selectedRule == nil,
            ruleAdditionConfirmation
                == nil,
            let mergeRequest =
                currentMergeRequest(),
            mergeRequest.route == route,
            mergeRequest.stateKind
                == .opened,
            mergeRequest.diffHeadSHA != nil,
            !Self.isApprovalSyncing(
                mergeRequest
            ),
            let summary =
                currentApprovalSummary()
        else {
            return false
        }
        return Self.requiresMutation(
            action,
            summary: summary,
            userID: accountID.userID
        )
    }

    func loadMembers(
        search: String?
    ) async {
        guard
            let baseline =
                selectedRuleBaseline,
            isAccountCurrent()
        else {
            return
        }

        memberGeneration &+= 1
        let generation =
            memberGeneration
        memberSearch = search
        memberNextPageURL = nil
        availableMembers = []
        isLoadingMembers = true
        defer {
            if
                memberGeneration
                    == generation
            {
                isLoadingMembers = false
            }
        }

        do {
            let page =
                try await service
                    .loadMembersPage(
                        projectID:
                            route.projectID,
                        search: search,
                        after: nil
                    )
            guard
                canPublishMembers(
                    generation,
                    baseline: baseline
                )
            else {
                return
            }
            availableMembers =
                candidates(
                    from: page.items,
                    baseline: baseline
                )
            memberNextPageURL =
                page.nextPageURL
            memberOptionsError = nil
            if case .memberOptions =
                failure
            {
                failure = nil
            }
        } catch {
            guard
                canPublishMembers(
                    generation,
                    baseline: baseline
                )
            else {
                return
            }
            memberOptionsError = error
            failure = .memberOptions(error)
        }
    }

    func candidates(
        from members:
            [GitLabProjectMember],
        baseline:
            GitLabMergeRequestApprovalRuleMutationSnapshot
    ) -> [GitLabProjectMember] {
        let eligibleIDs =
            Set(
                (
                    selectedRule?
                        .eligibleApprovers
                        ?? []
                ).map(\.id)
            )
        var seen: Set<Int> = []
        return members.filter {
            $0.id > 0
                && $0.isActive
                && !baseline.userIDs
                    .contains($0.id)
                && !eligibleIDs
                    .contains($0.id)
                && seen.insert($0.id)
                    .inserted
        }
    }

    func reconcilePendingRuleMutation(
        generation: UInt64
    ) async {
        guard
            let pending =
                pendingRuleMutation
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let rule:
            GitLabMergeRequestApprovalRule
        do {
            rule =
                try await service
                    .loadApprovalRule(
                        at: pending.route,
                        ruleID:
                            pending.baseline
                                .ruleID
                    )
        } catch {
            publishReconciliationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        selectedRule = rule
        selectedRuleBaseline =
            GitLabMergeRequestApprovalRuleMutationSnapshot(
                rule: rule
            )

        switch pending.baseline.result(
            for: rule,
            adding: pending.member.id
        ) {
        case .applied:
            pendingRuleMutation = nil
            availableMembers.removeAll {
                $0.id == pending.member.id
            }
            failure = nil
            await refreshApprovalOwners(
                generation: generation
            )
        case .unapplied:
            pendingRuleMutation = nil
            failure = .notApplied
        case .stale:
            pendingRuleMutation = nil
            failure = .ruleChanged
        }
    }

    func refreshApprovalOwners(
        generation: UInt64
    ) async {
        let mergeRequest:
            GitLabMergeRequest
        let summary:
            GitLabMergeRequestApprovalSummary
        do {
            mergeRequest =
                try await service
                    .loadLatestMergeRequest(
                        at: route
                    )
            summary =
                try await service
                    .loadApprovalSummary(
                        at: route
                    )
        } catch {
            guard canPublish(generation) else {
                return
            }
            failure =
                .reconciliation(error)
            return
        }

        guard
            canPublish(generation),
            mergeRequest.route == route
        else {
            if canPublish(generation) {
                failure =
                    .authoritativeMismatch
            }
            return
        }
        onMergeRequestReconciled(
            mergeRequest
        )
        onApprovalSummaryReconciled(
            summary
        )
    }

    func reconcilePendingMutation(
        generation: UInt64
    ) async {
        guard
            let pending =
                pendingMutation
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let mergeRequest:
            GitLabMergeRequest
        do {
            mergeRequest =
                try await service
                    .loadLatestMergeRequest(
                        at: pending.route
                    )
        } catch {
            publishReconciliationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onMergeRequestReconciled(
            mergeRequest
        )
        guard
            mergeRequest.route
                == pending.route
        else {
            failure =
                .authoritativeMismatch
            return
        }
        guard
            mergeRequest.diffHeadSHA
                == pending.headSHA
        else {
            pendingMutation = nil
            failure = .staleRevision
            return
        }

        let summary:
            GitLabMergeRequestApprovalSummary
        do {
            summary =
                try await service
                    .loadApprovalSummary(
                        at: pending.route
                    )
        } catch {
            publishReconciliationFailure(
                error,
                generation: generation
            )
            return
        }

        guard canPublish(generation) else {
            return
        }
        onApprovalSummaryReconciled(
            summary
        )
        let isApproved =
            Self.isApproved(
                userID: pending.userID,
                in: summary
            )
        let wasApplied =
            switch pending.action {
            case .approve:
                isApproved
            case .unapprove:
                !isApproved
            }

        pendingMutation = nil
        failure =
            wasApplied
            ? nil
            : .notApplied
    }

    func publishReadFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard canPublish(generation) else {
            return
        }
        failure = .load(error)
    }

    func publishReconciliationFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard canPublish(generation) else {
            return
        }
        failure =
            .reconciliation(error)
    }

    func handleMutationFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard
            operationGeneration
                == generation
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        switch error {
        case .api(
            .validation(
                statusCode: 409
            )
        ):
            pendingMutation = nil
            failure = .staleRevision
        case .api(.forbidden):
            pendingMutation = nil
            failure = .permissionDenied
        case .api(.unauthenticated):
            pendingMutation = nil
            failure =
                .gitLabReauthenticationRequired
        default:
            if
                error.mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                failure = .deliveryUnknown
            } else {
                pendingMutation = nil
                failure = .rejected(error)
            }
        }
    }

    func handleRuleMutationFailure(
        _ error:
            GitLabSessionClientError,
        generation: UInt64
    ) {
        guard
            operationGeneration
                == generation
        else {
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        switch error {
        case .api(
            .validation(
                statusCode: 409
            )
        ):
            pendingRuleMutation = nil
            failure = .ruleChanged
        case .api(.forbidden):
            pendingRuleMutation = nil
            failure = .permissionDenied
        case .api(.unauthenticated):
            pendingRuleMutation = nil
            failure =
                .gitLabReauthenticationRequired
        default:
            if
                error.mutationDeliveryCertainty
                    == .deliveryUnknown
            {
                failure = .deliveryUnknown
            } else {
                pendingRuleMutation = nil
                failure = .rejected(error)
            }
        }
    }

    func canPublish(
        _ generation: UInt64
    ) -> Bool {
        operationGeneration == generation
            && !Task.isCancelled
            && isAccountCurrent()
    }

    func canPublishRule(
        _ generation: UInt64
    ) -> Bool {
        ruleGeneration == generation
            && !Task.isCancelled
            && isAccountCurrent()
    }

    func canPublishMembers(
        _ generation: UInt64,
        baseline:
            GitLabMergeRequestApprovalRuleMutationSnapshot
    ) -> Bool {
        memberGeneration == generation
            && selectedRuleBaseline
                == baseline
            && !Task.isCancelled
            && isAccountCurrent()
    }

    nonisolated static func
        unsafeRuleFailure(
            _ editability:
                GitLabMergeRequestApprovalRuleEditability
        ) -> GitLabMergeRequestApprovalManagementFailure
    {
        switch editability {
        case .editable:
            .ruleChanged
        case let .locked(reason):
            .unsafeRule(reason)
        }
    }

    nonisolated static func mergedMembers(
        _ existing:
            [GitLabProjectMember],
        _ added:
            [GitLabProjectMember]
    ) -> [GitLabProjectMember] {
        var seen =
            Set(existing.map(\.id))
        return existing
            + added.filter {
                seen.insert($0.id)
                    .inserted
            }
    }

    nonisolated static func normalizedSearch(
        _ search: String
    ) -> String? {
        let normalized =
            search.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        return normalized.isEmpty
            ? nil
            : normalized
    }

    nonisolated static func
        requiresMutation(
            _ action:
                GitLabMergeRequestApprovalManagementAction,
            summary:
                GitLabMergeRequestApprovalSummary,
            userID: Int
        ) -> Bool
    {
        let approved = isApproved(
            userID: userID,
            in: summary
        )
        return switch action {
        case .approve:
            !approved
        case .unapprove:
            approved
        }
    }

    nonisolated static func isApproved(
        userID: Int,
        in summary:
            GitLabMergeRequestApprovalSummary
    ) -> Bool {
        summary.approvedBy.contains {
            $0.user?.id == userID
        }
    }

    nonisolated static func
        isApprovalSyncing(
            _ mergeRequest:
                GitLabMergeRequest
        ) -> Bool
    {
        let status =
            mergeRequest
                .detailedMergeStatus?
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .lowercased()
        return status == "checking"
            || status
                == "approvals_syncing"
    }
}
