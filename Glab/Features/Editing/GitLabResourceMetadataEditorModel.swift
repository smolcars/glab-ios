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
    private(set) var labelOptionsError:
        GitLabSessionClientError?
    private(set) var memberOptionsError:
        GitLabSessionClientError?
    var labelSearchText = "" {
        didSet {
            scheduleLabelSearch()
        }
    }
    var memberSearchText = "" {
        didSet {
            scheduleMemberSearch()
        }
    }

    let apiAccess: GitLabAPIAccess
    let supportsReviewers: Bool

    @ObservationIgnored
    private let accountID: GitLabAccountID
    @ObservationIgnored
    private let service:
        any GitLabResourceEditing
    @ObservationIgnored
    private let searchDebounce: Duration
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
    @ObservationIgnored
    private var seedMembers:
        [GitLabProjectMember]
    @ObservationIgnored
    private var activeMemberIDs:
        Set<Int> = []
    @ObservationIgnored
    private var confirmedNewLabels:
        Set<String> = []
    @ObservationIgnored
    private var labelSearchTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var memberSearchTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var labelSearchGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var memberSearchGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var isLoadingNextLabelsPage =
        false
    @ObservationIgnored
    private var isLoadingNextMembersPage =
        false

    init(
        accountID: GitLabAccountID,
        baseline: GitLabResourceEditResult,
        apiAccess: GitLabAPIAccess,
        service: any GitLabResourceEditing,
        searchDebounce: Duration =
            .milliseconds(250),
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
        self.searchDebounce =
            searchDebounce
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
        seedMembers =
            Self.members(
                from: baseline
            )
        members = seedMembers
        supportsReviewers =
            if case .mergeRequest = baseline {
                true
            } else {
                false
            }
    }

    deinit {
        labelSearchTask?.cancel()
        memberSearchTask?.cancel()
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

    var optionsError:
        GitLabSessionClientError?
    {
        labelOptionsError
            ?? memberOptionsError
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
        if
            !selectedLabelNames.contains(
                label.name
            )
        {
            confirmedNewLabels.remove(
                label.name
            )
        }
        clearEditableFailure()
    }

    func addLabel(named name: String) {
        let normalized =
            name.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        guard
            !normalized.isEmpty,
            !containsLabel(
                normalized,
                in: selectedLabelNames
            ),
            !isBusy
        else {
            return
        }
        selectedLabelNames.append(normalized)
        confirmedNewLabels.insert(
            normalized
        )
        clearEditableFailure()
    }

    func removeLabel(named name: String) {
        guard !isBusy else {
            return
        }
        selectedLabelNames.removeAll {
            $0 == name
        }
        confirmedNewLabels.remove(name)
        clearEditableFailure()
    }

    func removeAssignee(id: Int) {
        guard !isBusy else {
            return
        }
        selectedAssigneeIDs.removeAll {
            $0 == id
        }
        clearEditableFailure()
    }

    func removeReviewer(id: Int) {
        guard !isBusy else {
            return
        }
        selectedReviewerIDs.removeAll {
            $0 == id
        }
        clearEditableFailure()
    }

    func toggleAssignee(
        _ member: GitLabProjectMember
    ) {
        guard
            member.id > 0,
            !isBusy
        else {
            return
        }
        if selectedAssigneeIDs.contains(
            member.id
        ) {
            removeAssignee(id: member.id)
        } else {
            guard
                member.isActive,
                activeMemberIDs.contains(
                    member.id
                )
            else {
                return
            }
            selectedAssigneeIDs.append(
                member.id
            )
        }
        clearEditableFailure()
    }

    func toggleReviewer(
        _ member: GitLabProjectMember
    ) {
        guard
            supportsReviewers,
            member.id > 0,
            !isBusy
        else {
            return
        }
        if selectedReviewerIDs.contains(
            member.id
        ) {
            removeReviewer(id: member.id)
        } else {
            guard
                member.isActive,
                activeMemberIDs.contains(
                    member.id
                )
            else {
                return
            }
            selectedReviewerIDs.append(
                member.id
            )
        }
        clearEditableFailure()
    }

    func loadOptions() async {
        guard
            !isLoadingOptions,
            isAccountCurrent()
        else {
            return
        }
        let labelGeneration =
            labelSearchGeneration
        let memberGeneration =
            memberSearchGeneration
        isLoadingOptions = true
        labelOptionsError = nil
        memberOptionsError = nil
        defer {
            isLoadingOptions = false
        }

        async let labelResult =
            initialLabelPageResult()
        async let memberResult =
            initialMemberPageResult()
        let (
            loadedLabels,
            loadedMembers
        ) = await (
            labelResult,
            memberResult
        )
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        if
            labelGeneration
                == labelSearchGeneration,
            labelSearchText.isEmpty
        {
            switch loadedLabels {
            case let .success(page):
                applyLabels(page)
            case let .failure(error):
                labelOptionsError = error
            }
        }
        if
            memberGeneration
                == memberSearchGeneration,
            memberSearchText.isEmpty
        {
            switch loadedMembers {
            case let .success(page):
                applyMembers(page)
            case let .failure(error):
                memberOptionsError = error
            }
        }
    }

    func loadNextLabelsPage() async {
        guard
            let labelNextPageURL,
            !isLoadingNextLabelsPage
        else {
            return
        }
        let generation =
            labelSearchGeneration
        let search = labelSearch
        isLoadingNextLabelsPage = true
        defer {
            isLoadingNextLabelsPage = false
        }
        do {
            let page =
                try await service
                    .loadLabelsPage(
                        projectID: projectID,
                        search: search,
                        after: labelNextPageURL
                    )
            guard
                !Task.isCancelled,
                isAccountCurrent(),
                generation
                    == labelSearchGeneration,
                search == labelSearch
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
            labelOptionsError = nil
        } catch {
            recordLabelOptionsError(
                error,
                generation: generation
            )
        }
    }

    func loadNextMembersPage() async {
        guard
            let memberNextPageURL,
            !isLoadingNextMembersPage
        else {
            return
        }
        let generation =
            memberSearchGeneration
        let search = memberSearch
        isLoadingNextMembersPage = true
        defer {
            isLoadingNextMembersPage =
                false
        }
        do {
            let page =
                try await service
                    .loadMembersPage(
                        projectID: projectID,
                        search: search,
                        after:
                            memberNextPageURL
                    )
            guard
                !Task.isCancelled,
                isAccountCurrent(),
                generation
                    == memberSearchGeneration,
                search == memberSearch
            else {
                return
            }
            mergeMembers(page)
            self.memberNextPageURL =
                page.nextPageURL
            memberOptionsError = nil
        } catch {
            recordMemberOptionsError(
                error,
                generation: generation
            )
        }
    }

    private func scheduleLabelSearch() {
        labelSearchGeneration &+= 1
        let generation =
            labelSearchGeneration
        labelSearchTask?.cancel()
        labelNextPageURL = nil
        let search =
            Self.normalizedSearch(
                labelSearchText
            )
        labelSearch = search
        let debounce = searchDebounce
        labelSearchTask = Task {
            do {
                try await Task.sleep(
                    for: debounce
                )
                try Task.checkCancellation()
            } catch {
                return
            }
            guard
                generation
                    == labelSearchGeneration,
                isAccountCurrent()
            else {
                return
            }
            do {
                let page =
                    try await service
                        .loadLabelsPage(
                            projectID:
                                projectID,
                            search: search,
                            after: nil
                        )
                guard
                    !Task.isCancelled,
                    isAccountCurrent(),
                    generation
                        == labelSearchGeneration,
                    search == labelSearch
                else {
                    return
                }
                applyLabels(page)
                labelOptionsError = nil
            } catch {
                recordLabelOptionsError(
                    error as?
                        GitLabSessionClientError
                        ?? .api(
                            .invalidResponse
                        ),
                    generation:
                        generation
                )
            }
        }
    }

    private func scheduleMemberSearch() {
        memberSearchGeneration &+= 1
        let generation =
            memberSearchGeneration
        memberSearchTask?.cancel()
        memberNextPageURL = nil
        let search =
            Self.normalizedSearch(
                memberSearchText
            )
        memberSearch = search
        let debounce = searchDebounce
        memberSearchTask = Task {
            do {
                try await Task.sleep(
                    for: debounce
                )
                try Task.checkCancellation()
            } catch {
                return
            }
            guard
                generation
                    == memberSearchGeneration,
                isAccountCurrent()
            else {
                return
            }
            do {
                let page =
                    try await service
                        .loadMembersPage(
                            projectID:
                                projectID,
                            search: search,
                            after: nil
                        )
                guard
                    !Task.isCancelled,
                    isAccountCurrent(),
                    generation
                        == memberSearchGeneration,
                    search == memberSearch
                else {
                    return
                }
                applyMembers(page)
                memberOptionsError = nil
            } catch {
                recordMemberOptionsError(
                    error as?
                        GitLabSessionClientError
                        ?? .api(
                            .invalidResponse
                        ),
                    generation:
                        generation
                )
            }
        }
    }

    private func initialLabelPageResult()
        async -> Result<
        GitLabResourcePage<
            GitLabProjectLabel
        >,
        GitLabSessionClientError
    > {
        do {
            return .success(
                try await service
                    .loadLabelsPage(
                        projectID: projectID,
                        search: nil,
                        after: nil
                    )
            )
        } catch {
            return .failure(error)
        }
    }

    private func initialMemberPageResult()
        async -> Result<
        GitLabResourcePage<
            GitLabProjectMember
        >,
        GitLabSessionClientError
    > {
        do {
            return .success(
                try await service
                    .loadMembersPage(
                        projectID: projectID,
                        search: nil,
                        after: nil
                    )
            )
        } catch {
            return .failure(error)
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
                await completeMutationSuccess(
                    latest,
                    invalidatesProjectLabels:
                        invalidatesProjectLabels(
                            for:
                                pendingIntent
                        )
                )
            } else {
                self.pendingIntent = nil
                apply(
                    latest,
                    preserving:
                        pendingIntent
                )
                onSuccess(latest)
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
            await completeReconciliationSuccess(
                latest,
                invalidatesProjectLabels:
                    invalidatesProjectLabels(
                        for: intent
                    )
            )
            return
        }
        guard intent.canApply(to: latestValues) else {
            apply(
                latest,
                preserving: intent
            )
            onSuccess(latest)
            failure = .notApplied
            return
        }
        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
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
                !Task.isCancelled,
                isAccountCurrent()
            else {
                pendingIntent = intent
                failure =
                    .mutation(
                        .api(.cancelled),
                        certainty:
                            .deliveryUnknown
                    )
                return
            }
            guard
                let resultValues =
                    validValues(result),
                intent.matches(resultValues)
            else {
                failure =
                    .invalidAuthoritativeResponse
                return
            }
            await completeMutationSuccess(
                result,
                invalidatesProjectLabels:
                    invalidatesProjectLabels(
                        for: intent
                    )
            )
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

    private func completeMutationSuccess(
        _ result: GitLabResourceEditResult,
        invalidatesProjectLabels: Bool
    ) async {
        await service.invalidateAffectedReads(
            for: target
        )
        if invalidatesProjectLabels {
            await service
                .invalidateProjectLabels(
                    projectID: projectID
                )
        }
        guard isAccountCurrent() else {
            return
        }
        acceptSuccess(result)
    }

    private func completeReconciliationSuccess(
        _ result: GitLabResourceEditResult,
        invalidatesProjectLabels: Bool
    ) async {
        if invalidatesProjectLabels {
            await service
                .invalidateProjectLabels(
                    projectID: projectID
                )
        }
        guard isAccountCurrent() else {
            return
        }
        acceptSuccess(result)
    }

    private func acceptSuccess(
        _ result: GitLabResourceEditResult
    ) {
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
        seedMembers =
            Self.members(
                from: result
            )
        members = Self.merged(
            seedMembers,
            members,
            identity: \.id
        )
        confirmedNewLabels.removeAll()
        pendingIntent = nil
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
        seedMembers =
            Self.members(
                from: result
            )
        members = Self.merged(
            seedMembers,
            members,
            identity: \.id
        )
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
    }

    private func applyMembers(
        _ page:
            GitLabResourcePage<
                GitLabProjectMember
            >
    ) {
        activeMemberIDs.formUnion(
            page.items
                .filter(\.isActive)
                .map(\.id)
        )
        members = Self.merged(
            seedMembers,
            page.items.filter(\.isActive),
            identity: \.id
        )
        memberNextPageURL =
            page.nextPageURL
    }

    private func mergeMembers(
        _ page:
            GitLabResourcePage<
                GitLabProjectMember
            >
    ) {
        let active =
            page.items.filter(\.isActive)
        activeMemberIDs.formUnion(
            active.map(\.id)
        )
        members = Self.merged(
            members,
            active,
            identity: \.id
        )
    }

    private func recordLabelOptionsError(
        _ error: GitLabSessionClientError,
        generation: UInt64
    ) {
        guard
            generation
                == labelSearchGeneration,
            isAccountCurrent()
        else {
            return
        }
        recordOptionsError(
            error,
            in: &labelOptionsError
        )
    }

    private func recordMemberOptionsError(
        _ error: GitLabSessionClientError,
        generation: UInt64
    ) {
        guard
            generation
                == memberSearchGeneration,
            isAccountCurrent()
        else {
            return
        }
        recordOptionsError(
            error,
            in: &memberOptionsError
        )
    }

    private func recordOptionsError(
        _ error: GitLabSessionClientError,
        in destination:
            inout GitLabSessionClientError?
    ) {
        guard
            !Task.isCancelled,
            error != .api(.cancelled)
        else {
            return
        }
        destination = error
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

    private func containsLabel(
        _ label: String,
        in values: [String]
    ) -> Bool {
        values.contains {
            $0.localizedCaseInsensitiveCompare(
                label
            ) == .orderedSame
        }
    }

    private func invalidatesProjectLabels(
        for intent:
            GitLabResourceMetadataIntent
    ) -> Bool {
        intent.addedLabels.contains {
            confirmedNewLabels.contains($0)
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

    private static func members(
        from result:
            GitLabResourceEditResult
    ) -> [GitLabProjectMember] {
        let users:
            [GitLabAPIUser] =
                switch result {
                case let .issue(issue):
                    issue.assignees
                case let .mergeRequest(
                    mergeRequest
                ):
                    mergeRequest.assignees
                        + mergeRequest.reviewers
                }
        return merged(
            [],
            users.map {
                GitLabProjectMember(
                    id: $0.id,
                    username: $0.username,
                    name: $0.name,
                    state: "active",
                    avatarURL: $0.avatarURL,
                    webURL: $0.webURL,
                    accessLevel: 0
                )
            },
            identity: \.id
        )
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

    func canApply(
        to values:
            GitLabResourceMetadataValues
    ) -> Bool {
        switch stateEvent {
        case .close:
            values.state == .opened
        case .reopen:
            values.state == .closed
        case nil:
            true
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
