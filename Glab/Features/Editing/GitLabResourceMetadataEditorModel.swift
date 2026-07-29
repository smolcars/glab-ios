import Foundation
import Observation

nonisolated enum GitLabResourceMetadataEditorFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case validation(
        GitLabResourceMetadataValidationError
    )
    case readOnly
    case freshness(GitLabSessionClientError)
    case mutation(
        GitLabSessionClientError,
        certainty:
            GitLabMutationDeliveryCertainty
    )
    case invalidAuthoritativeResponse
    case notApplied

    var description: String {
        switch self {
        case let .validation(error):
            error.description
        case .readOnly:
            "This account has read-only API access."
        case .freshness:
            "Couldn’t verify the latest GitLab metadata."
        case let .mutation(error, certainty):
            certainty == .deliveryUnknown
                ? "GitLab may have applied the change. Check GitLab before trying again."
                : error.description
        case .invalidAuthoritativeResponse:
            "GitLab returned metadata that could not be verified."
        case .notApplied:
            "GitLab did not apply the change. Review the latest metadata before trying again."
        }
    }

    var debugDescription: String {
        description
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        let error:
            GitLabSessionClientError? =
            switch self {
            case let .freshness(error):
                error
            case let .mutation(error, _):
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
final class GitLabResourceMetadataEditorModel {
    private(set) var selectedLabelNames:
        [String]
    private(set) var selectedAssigneeIDs:
        [Int]
    private(set) var selectedReviewerIDs:
        [Int]
    private(set) var labels:
        [GitLabProjectLabel] = []
    private(set) var members:
        [GitLabProjectMember] = []
    private(set) var isLoadingOptions = false
    private(set) var isSaving = false
    private(set) var isCheckingDelivery = false
    private(set) var didSucceed = false
    private(set) var failure:
        GitLabResourceMetadataEditorFailure?
    private(set) var optionsError:
        GitLabSessionClientError?

    let apiAccess: GitLabAPIAccess
    let supportsReviewers: Bool

    @ObservationIgnored
    private let accountID: GitLabAccountID
    @ObservationIgnored
    private let service:
        any GitLabResourceEditing
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onSuccess:
        @MainActor (
            GitLabResourceEditResult
        ) -> Void
    @ObservationIgnored
    private var baseline:
        GitLabResourceEditResult
    @ObservationIgnored
    private var pendingIntent:
        GitLabResourceMetadataIntent?
    @ObservationIgnored
    private var labelNextPageURL: URL?
    @ObservationIgnored
    private var memberNextPageURL: URL?
    @ObservationIgnored
    private var labelSearch: String?
    @ObservationIgnored
    private var memberSearch: String?

    init(
        accountID: GitLabAccountID,
        baseline: GitLabResourceEditResult,
        apiAccess: GitLabAPIAccess,
        service: any GitLabResourceEditing,
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onSuccess:
            @escaping @MainActor (
                GitLabResourceEditResult
            ) -> Void
    ) {
        self.accountID = accountID
        self.baseline = baseline
        self.apiAccess = apiAccess
        self.service = service
        self.isAccountCurrent =
            isAccountCurrent
        self.onSuccess = onSuccess
        let values =
            GitLabResourceMetadataValues(
                baseline
            )
        selectedLabelNames = values?.labels ?? []
        selectedAssigneeIDs =
            values?.assigneeIDs ?? []
        selectedReviewerIDs =
            values?.reviewerIDs ?? []
        supportsReviewers =
            if case .mergeRequest = baseline {
                true
            } else {
                false
            }
    }

    var target: GitLabResourceEditTarget {
        baseline.snapshot.target
    }

    var projectID: Int {
        target.projectID
    }

    var isBusy: Bool {
        isSaving || isCheckingDelivery
    }

    var requiresDeliveryCheck: Bool {
        pendingIntent != nil
    }

    var isDirty: Bool {
        currentIntent(stateEvent: nil)
            .hasChanges
    }

    var canSave: Bool {
        apiAccess.canWrite
            && isAccountCurrent()
            && !isBusy
            && !requiresDeliveryCheck
            && isDirty
    }

    var availableStateEvent:
        GitLabResourceStateEvent?
    {
        switch
            GitLabResourceMetadataValues(
                baseline
            )?.state
        {
        case .opened:
            .close
        case .closed:
            .reopen
        case .unsupported, nil:
            nil
        }
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

    func toggleLabel(
        _ label: GitLabProjectLabel
    ) {
        guard
            label.archived != true,
            !label.name.isEmpty,
            !isBusy
        else {
            return
        }
        toggle(
            label.name,
            in: &selectedLabelNames
        )
        clearEditableFailure()
    }

    func addLabel(named name: String) {
        let normalized =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            !normalized.isEmpty,
            !selectedLabelNames
                .contains(normalized),
            !isBusy
        else {
            return
        }
        selectedLabelNames.append(normalized)
        clearEditableFailure()
    }

    func toggleAssignee(
        _ member: GitLabProjectMember
    ) {
        guard
            member.id > 0,
            member.isActive,
            !isBusy
        else {
            return
        }
        toggle(
            member.id,
            in: &selectedAssigneeIDs
        )
        clearEditableFailure()
    }

    func toggleReviewer(
        _ member: GitLabProjectMember
    ) {
        guard
            supportsReviewers,
            member.id > 0,
            member.isActive,
            !isBusy
        else {
            return
        }
        toggle(
            member.id,
            in: &selectedReviewerIDs
        )
        clearEditableFailure()
    }

    func loadOptions() async {
        guard
            !isLoadingOptions,
            isAccountCurrent()
        else {
            return
        }
        isLoadingOptions = true
        optionsError = nil
        defer {
            isLoadingOptions = false
        }

        do {
            async let labelPage =
                service.loadLabelsPage(
                    projectID: projectID,
                    search: nil,
                    after: nil
                )
            async let memberPage =
                service.loadMembersPage(
                    projectID: projectID,
                    search: nil,
                    after: nil
                )
            let (loadedLabels, loadedMembers) =
                try await (
                    labelPage,
                    memberPage
                )
            guard
                !Task.isCancelled,
                isAccountCurrent()
            else {
                return
            }
            applyLabels(loadedLabels)
            applyMembers(loadedMembers)
            labelSearch = nil
            memberSearch = nil
        } catch {
            let error =
                error as?
                    GitLabSessionClientError
                ?? .api(.invalidResponse)
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }
            optionsError = error
        }
    }

    func searchLabels(
        _ search: String
    ) async {
        let normalized =
            Self.normalizedSearch(search)
        labelSearch = normalized
        do {
            let page =
                try await service
                    .loadLabelsPage(
                        projectID: projectID,
                        search: normalized,
                        after: nil
                    )
            guard
                !Task.isCancelled,
                labelSearch == normalized,
                isAccountCurrent()
            else {
                return
            }
            applyLabels(page)
        } catch {
            recordOptionsError(error)
        }
    }

    func searchMembers(
        _ search: String
    ) async {
        let normalized =
            Self.normalizedSearch(search)
        memberSearch = normalized
        do {
            let page =
                try await service
                    .loadMembersPage(
                        projectID: projectID,
                        search: normalized,
                        after: nil
                    )
            guard
                !Task.isCancelled,
                memberSearch == normalized,
                isAccountCurrent()
            else {
                return
            }
            applyMembers(page)
        } catch {
            recordOptionsError(error)
        }
    }

    func loadNextLabelsPage() async {
        guard let labelNextPageURL else {
            return
        }
        do {
            let page =
                try await service
                    .loadLabelsPage(
                        projectID: projectID,
                        search: labelSearch,
                        after: labelNextPageURL
                    )
            guard
                !Task.isCancelled,
                isAccountCurrent()
            else {
                return
            }
            labels = Self.merged(
                labels,
                page.items.filter {
                    $0.archived != true
                },
                identity: \.id
            )
            self.labelNextPageURL =
                page.nextPageURL
        } catch {
            recordOptionsError(error)
        }
    }

    func loadNextMembersPage() async {
        guard let memberNextPageURL else {
            return
        }
        do {
            let page =
                try await service
                    .loadMembersPage(
                        projectID: projectID,
                        search: memberSearch,
                        after: memberNextPageURL
                    )
            guard
                !Task.isCancelled,
                isAccountCurrent()
            else {
                return
            }
            members = Self.merged(
                members,
                page.items.filter(\.isActive),
                identity: \.id
            )
            self.memberNextPageURL =
                page.nextPageURL
        } catch {
            recordOptionsError(error)
        }
    }

    func save() async {
        await submit(
            stateEvent: nil
        )
    }

    func changeState(
        _ event: GitLabResourceStateEvent
    ) async {
        guard availableStateEvent == event else {
            failure =
                .validation(.noChanges)
            return
        }
        await submit(
            stateEvent: event
        )
    }

    func checkGitLab() async {
        guard
            let pendingIntent,
            !isCheckingDelivery,
            isAccountCurrent()
        else {
            return
        }
        isCheckingDelivery = true
        defer {
            isCheckingDelivery = false
        }

        do {
            let latest =
                try await service.loadLatest(
                    target
                )
            guard
                let latestValues =
                    validValues(latest)
            else {
                failure =
                    .invalidAuthoritativeResponse
                return
            }
            if pendingIntent.matches(
                latestValues
            ) {
                self.pendingIntent = nil
                await completeSuccess(latest)
            } else {
                self.pendingIntent = nil
                apply(
                    latest,
                    preserving:
                        pendingIntent
                )
                failure = .notApplied
            }
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }
            failure = .freshness(error)
        }
    }

    private func submit(
        stateEvent:
            GitLabResourceStateEvent?
    ) async {
        guard
            !isBusy,
            !requiresDeliveryCheck,
            isAccountCurrent()
        else {
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }
        let intent =
            currentIntent(
                stateEvent: stateEvent
            )
        guard intent.hasChanges else {
            failure =
                .validation(.noChanges)
            return
        }

        isSaving = true
        didSucceed = false
        failure = nil
        defer {
            isSaving = false
        }

        let latest:
            GitLabResourceEditResult
        do {
            latest =
                try await service.loadLatest(
                    target
                )
        } catch {
            guard
                !Task.isCancelled,
                error != .api(.cancelled)
            else {
                return
            }
            failure = .freshness(error)
            return
        }
        guard
            let latestValues =
                validValues(latest)
        else {
            failure =
                .invalidAuthoritativeResponse
            return
        }
        if intent.matches(latestValues) {
            await completeSuccess(latest)
            return
        }

        let changes =
            intent.changes(
                rebasedOnto:
                    latestValues
            )
        do {
            let result =
                try await service
                    .updateMetadata(
                        target,
                        changes: changes
                    )
            guard
                let resultValues =
                    validValues(result),
                intent.matches(resultValues)
            else {
                failure =
                    .invalidAuthoritativeResponse
                return
            }
            await completeSuccess(result)
        } catch {
            let certainty =
                error.mutationDeliveryCertainty
            if certainty == .deliveryUnknown {
                pendingIntent = intent
            }
            failure =
                .mutation(
                    error,
                    certainty: certainty
                )
        }
    }

    private func completeSuccess(
        _ result: GitLabResourceEditResult
    ) async {
        await service.invalidateAffectedReads(
            for: target
        )
        guard isAccountCurrent() else {
            return
        }
        baseline = result
        let values =
            GitLabResourceMetadataValues(
                result
            )
        selectedLabelNames =
            values?.labels ?? []
        selectedAssigneeIDs =
            values?.assigneeIDs ?? []
        selectedReviewerIDs =
            values?.reviewerIDs ?? []
        failure = nil
        didSucceed = true
        onSuccess(result)
    }

    private func currentIntent(
        stateEvent:
            GitLabResourceStateEvent?
    ) -> GitLabResourceMetadataIntent {
        let baselineValues =
            GitLabResourceMetadataValues(
                baseline
            )
        return GitLabResourceMetadataIntent(
            baseline:
                baselineValues,
            selectedLabels:
                selectedLabelNames,
            selectedAssignees:
                selectedAssigneeIDs,
            selectedReviewers:
                selectedReviewerIDs,
            stateEvent: stateEvent
        )
    }

    private func validValues(
        _ result: GitLabResourceEditResult
    ) -> GitLabResourceMetadataValues? {
        guard
            result.snapshot.target == target,
            result.snapshot.resourceID
                == baseline.snapshot.resourceID
        else {
            return nil
        }
        return GitLabResourceMetadataValues(
            result
        )
    }

    private func apply(
        _ result: GitLabResourceEditResult,
        preserving intent:
            GitLabResourceMetadataIntent
    ) {
        guard
            let values =
                GitLabResourceMetadataValues(
                    result
                )
        else {
            return
        }
        baseline = result
        selectedLabelNames =
            intent.rebasedLabels(
                onto: values.labels
            )
        selectedAssigneeIDs =
            intent.rebasedAssignees(
                onto:
                    values.assigneeIDs
            )
        selectedReviewerIDs =
            intent.rebasedReviewers(
                onto:
                    values.reviewerIDs
            )
    }

    private func applyLabels(
        _ page:
            GitLabResourcePage<
                GitLabProjectLabel
            >
    ) {
        labels = page.items.filter {
            $0.archived != true
        }
        labelNextPageURL =
            page.nextPageURL
        optionsError = nil
    }

    private func applyMembers(
        _ page:
            GitLabResourcePage<
                GitLabProjectMember
            >
    ) {
        members = page.items.filter(\.isActive)
        memberNextPageURL =
            page.nextPageURL
        optionsError = nil
    }

    private func recordOptionsError(
        _ error: GitLabSessionClientError
    ) {
        guard
            !Task.isCancelled,
            error != .api(.cancelled)
        else {
            return
        }
        optionsError = error
    }

    private func clearEditableFailure() {
        switch failure {
        case .validation,
             .notApplied:
            failure = nil
        default:
            break
        }
    }

    private func toggle<Value: Equatable>(
        _ value: Value,
        in values: inout [Value]
    ) {
        if
            let index =
                values.firstIndex(of: value)
        {
            values.remove(at: index)
        } else {
            values.append(value)
        }
    }

    private static func normalizedSearch(
        _ value: String
    ) -> String? {
        let normalized =
            value.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        return normalized.isEmpty
            ? nil
            : normalized
    }

    private static func merged<Item, ID>(
        _ current: [Item],
        _ incoming: [Item],
        identity: KeyPath<Item, ID>
    ) -> [Item] where ID: Hashable {
        var result = current
        var indices = Dictionary(
            uniqueKeysWithValues:
                current.enumerated().map {
                    (
                        $0.element[
                            keyPath: identity
                        ],
                        $0.offset
                    )
                }
        )
        for item in incoming {
            let id =
                item[keyPath: identity]
            if let index = indices[id] {
                result[index] = item
            } else {
                indices[id] = result.count
                result.append(item)
            }
        }
        return result
    }
}

private nonisolated enum GitLabEditableResourceState:
    Equatable,
    Sendable
{
    case opened
    case closed
    case unsupported
}

private nonisolated struct GitLabResourceMetadataValues:
    Equatable,
    Sendable
{
    let labels: [String]
    let assigneeIDs: [Int]
    let reviewerIDs: [Int]
    let state: GitLabEditableResourceState

    init?(
        _ result: GitLabResourceEditResult
    ) {
        switch result {
        case let .issue(issue):
            labels = issue.labels
            assigneeIDs =
                issue.assignees.map(\.id)
            reviewerIDs = []
            state =
                switch issue.stateKind {
                case .opened:
                    .opened
                case .closed:
                    .closed
                case .unknown:
                    .unsupported
                }
        case let .mergeRequest(
            mergeRequest
        ):
            labels = mergeRequest.labels
            assigneeIDs =
                mergeRequest.assignees.map(\.id)
            reviewerIDs =
                mergeRequest.reviewers.map(\.id)
            state =
                switch
                    mergeRequest.stateKind
                {
                case .opened:
                    .opened
                case .closed:
                    .closed
                case .merged,
                     .locked,
                     .unknown:
                    .unsupported
                }
        }
    }
}

private nonisolated struct GitLabResourceMetadataIntent:
    Equatable,
    Sendable
{
    let addedLabels: [String]
    let removedLabels: [String]
    let addedAssignees: [Int]
    let removedAssignees: [Int]
    let addedReviewers: [Int]
    let removedReviewers: [Int]
    let changesAssignees: Bool
    let changesReviewers: Bool
    let stateEvent:
        GitLabResourceStateEvent?

    init(
        baseline:
            GitLabResourceMetadataValues?,
        selectedLabels: [String],
        selectedAssignees: [Int],
        selectedReviewers: [Int],
        stateEvent:
            GitLabResourceStateEvent?
    ) {
        let baselineLabels =
            baseline?.labels ?? []
        let baselineAssignees =
            baseline?.assigneeIDs ?? []
        let baselineReviewers =
            baseline?.reviewerIDs ?? []
        addedLabels = Self.added(
            selectedLabels,
            from: baselineLabels
        )
        removedLabels = Self.removed(
            baselineLabels,
            from: selectedLabels
        )
        addedAssignees = Self.added(
            selectedAssignees,
            from: baselineAssignees
        )
        removedAssignees = Self.removed(
            baselineAssignees,
            from: selectedAssignees
        )
        addedReviewers = Self.added(
            selectedReviewers,
            from: baselineReviewers
        )
        removedReviewers = Self.removed(
            baselineReviewers,
            from: selectedReviewers
        )
        changesAssignees =
            selectedAssignees
                != baselineAssignees
        changesReviewers =
            selectedReviewers
                != baselineReviewers
        self.stateEvent = stateEvent
    }

    var hasChanges: Bool {
        !addedLabels.isEmpty
            || !removedLabels.isEmpty
            || changesAssignees
            || changesReviewers
            || stateEvent != nil
    }

    func changes(
        rebasedOnto latest:
            GitLabResourceMetadataValues
    ) -> GitLabResourceMetadataChanges {
        GitLabResourceMetadataChanges(
            labels:
                addedLabels.isEmpty
                    && removedLabels.isEmpty
                ? nil
                : .delta(
                    add: addedLabels,
                    remove: removedLabels
                ),
            assigneeIDs:
                changesAssignees
                ? rebasedAssignees(
                    onto:
                        latest.assigneeIDs
                )
                : nil,
            reviewerIDs:
                changesReviewers
                ? rebasedReviewers(
                    onto:
                        latest.reviewerIDs
                )
                : nil,
            stateEvent: stateEvent
        )
    }

    func matches(
        _ values:
            GitLabResourceMetadataValues
    ) -> Bool {
        let labelSet = Set(values.labels)
        guard
            addedLabels.allSatisfy(
                labelSet.contains
            ),
            removedLabels.allSatisfy({
                !labelSet.contains($0)
            })
        else {
            return false
        }
        if changesAssignees {
            let assigneeSet =
                Set(values.assigneeIDs)
            guard
                addedAssignees.allSatisfy(
                    assigneeSet.contains
                ),
                removedAssignees
                    .allSatisfy({
                        !assigneeSet.contains($0)
                    })
            else {
                return false
            }
        }
        if changesReviewers {
            let reviewerSet =
                Set(values.reviewerIDs)
            guard
                addedReviewers.allSatisfy(
                    reviewerSet.contains
                ),
                removedReviewers
                    .allSatisfy({
                        !reviewerSet.contains($0)
                    })
            else {
                return false
            }
        }
        switch stateEvent {
        case .close:
            return values.state == .closed
        case .reopen:
            return values.state == .opened
        case nil:
            return true
        }
    }

    func rebasedLabels(
        onto values: [String]
    ) -> [String] {
        Self.rebased(
            values,
            adding: addedLabels,
            removing: removedLabels
        )
    }

    func rebasedAssignees(
        onto values: [Int]
    ) -> [Int] {
        guard changesAssignees else {
            return values
        }
        return Self.rebased(
            values,
            adding: addedAssignees,
            removing: removedAssignees
        )
    }

    func rebasedReviewers(
        onto values: [Int]
    ) -> [Int] {
        guard changesReviewers else {
            return values
        }
        return Self.rebased(
            values,
            adding: addedReviewers,
            removing: removedReviewers
        )
    }

    private static func added<Value: Hashable>(
        _ selected: [Value],
        from baseline: [Value]
    ) -> [Value] {
        let baselineSet = Set(baseline)
        return selected.filter {
            !baselineSet.contains($0)
        }
    }

    private static func removed<Value: Hashable>(
        _ baseline: [Value],
        from selected: [Value]
    ) -> [Value] {
        let selectedSet = Set(selected)
        return baseline.filter {
            !selectedSet.contains($0)
        }
    }

    private static func rebased<
        Value: Hashable
    >(
        _ values: [Value],
        adding: [Value],
        removing: [Value]
    ) -> [Value] {
        let removed = Set(removing)
        var result = values.filter {
            !removed.contains($0)
        }
        var present = Set(result)
        for value in adding
        where present.insert(value).inserted {
            result.append(value)
        }
        return result
    }
}
