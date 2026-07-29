import CryptoKit
import Foundation
import Observation

nonisolated enum GitLabIssueCreationFailure:
    Equatable,
    Sendable,
    CustomStringConvertible,
    CustomDebugStringConvertible
{
    case validation(
        GitLabIssueCreationValidationError
    )
    case restoredProjectUnavailable
    case projectVerification(
        GitLabSessionClientError
    )
    case readOnly
    case draftStorage
    case mutation(
        GitLabSessionClientError,
        certainty:
            GitLabMutationDeliveryCertainty
    )
    case invalidAuthoritativeResponse
    case deliveryCheckRequired

    var description: String {
        "GitLabIssueCreationFailure(<redacted>)"
    }

    var debugDescription: String {
        description
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            let error =
                switch self {
                case let .projectVerification(
                    error
                ):
                    error
                case let .mutation(error, _):
                    error
                default:
                    nil
                },
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }
}

@MainActor
@Observable
final class GitLabIssueCreationModel {
    var title = "" {
        didSet {
            formValueDidChange(
                changed: title != oldValue
            )
        }
    }

    var rawDescription = "" {
        didSet {
            formValueDidChange(
                changed:
                    rawDescription != oldValue
            )
        }
    }

    var confidential = false {
        didSet {
            formValueDidChange(
                changed:
                    confidential != oldValue
            )
        }
    }

    var dueDate: GitLabIssueDueDate? {
        didSet {
            formValueDidChange(
                changed: dueDate != oldValue
            )
        }
    }

    var projectSearchText = "" {
        didSet {
            guard
                projectSearchText
                    != oldValue
            else {
                return
            }
            scheduleProjectSearch()
        }
    }

    private(set) var selectedProject:
        GitLabIssueCreationProjectSelection?
    private(set) var selectedLabelNames:
        [String] = []
    private(set) var selectedAssigneeIDs:
        [Int] = []
    private(set) var hasRestoredDraft = false
    private(set) var
        isVerifyingRestoredProject = false
    private(set) var
        isSelectedProjectVerified = true
    private(set) var draftRevision = 0
    private(set) var isSubmitting = false
    private(set) var failure:
        GitLabIssueCreationFailure?
    private(set) var didSucceed = false
    private(set) var pendingSubmissionFingerprint:
        String?

    private(set) var projectsModel:
        GitLabPaginatedResourceModel<
            GitLabProject,
            Int
        >
    private(set) var labelsModel:
        GitLabPaginatedResourceModel<
            GitLabProjectLabel,
            Int
        >?
    private(set) var membersModel:
        GitLabPaginatedResourceModel<
            GitLabProjectMember,
            Int
        >?

    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let accountID: GitLabAccountID
    @ObservationIgnored
    private let service:
        any GitLabIssueCreationServing
    @ObservationIgnored
    private let draftStore:
        any GitLabIssueCreationDraftStoring
    @ObservationIgnored
    private let searchDebounce: Duration
    @ObservationIgnored
    private let isAccountCurrent:
        @MainActor () -> Bool
    @ObservationIgnored
    private let onSuccess:
        @MainActor (GitLabIssue) -> Void
    @ObservationIgnored
    private var persistenceTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var projectSearchTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var projectSearchGeneration:
        UInt64 = 0
    @ObservationIgnored
    private var isApplyingDraft = false
    @ObservationIgnored
    private var isRestoringDraft = false

    init(
        accountID: GitLabAccountID,
        apiAccess: GitLabAPIAccess,
        service:
            any GitLabIssueCreationServing,
        draftStore:
            any GitLabIssueCreationDraftStoring,
        searchDebounce: Duration =
            .milliseconds(250),
        isAccountCurrent:
            @escaping @MainActor () -> Bool,
        onSuccess:
            @escaping @MainActor (
                GitLabIssue
            ) -> Void
    ) {
        self.accountID = accountID
        self.apiAccess = apiAccess
        self.service = service
        self.draftStore = draftStore
        self.searchDebounce = searchDebounce
        self.isAccountCurrent =
            isAccountCurrent
        self.onSuccess = onSuccess
        projectsModel = Self.makeProjectsModel(
            service: service,
            search: nil
        )
    }

    deinit {
        persistenceTask?.cancel()
        projectSearchTask?.cancel()
    }

    var canCreate: Bool {
        guard
            hasRestoredDraft,
            isSelectedProjectVerified,
            apiAccess.canWrite,
            !isSubmitting,
            !requiresDeliveryCheck,
            isAccountCurrent()
        else {
            return false
        }
        return (try? creationInput()) != nil
    }

    var requiresDeliveryCheck: Bool {
        pendingSubmissionFingerprint != nil
    }

    var displayedAssignableMembers:
        [GitLabProjectMember]
    {
        membersModel?
            .displayedItems
            .filter(\.isActive)
            ?? []
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        if
            let failure =
                failure?
                .authenticationFailure
        {
            return failure
        }
        for error in [
            projectsModel
                .authenticationFailure,
            labelsModel?
                .authenticationFailure,
            membersModel?
                .authenticationFailure,
        ] {
            if let error {
                return error
            }
        }
        return nil
    }

    func restoreDraft() async {
        guard
            !hasRestoredDraft,
            !isRestoringDraft
        else {
            return
        }
        isRestoringDraft = true
        let startingRevision =
            draftRevision
        let stored = await draftStore.draft(
            for: draftKey
        )
        isRestoringDraft = false

        guard
            !Task.isCancelled,
            isAccountCurrent()
        else {
            return
        }

        let hadLocalEdits =
            draftRevision != startingRevision
                || !currentDraft.isPristine
        if
            !hadLocalEdits,
            let stored
        {
            apply(stored)
            draftRevision = stored.revision
            if
                stored
                    .pendingSubmissionFingerprint
                    != nil
            {
                failure =
                    .deliveryCheckRequired
            }
        }

        hasRestoredDraft = true
        if hadLocalEdits {
            draftRevision = max(
                draftRevision,
                (stored?.revision ?? -1) + 1
            )
            schedulePersistence()
        } else {
            await verifyRestoredProject()
        }
    }

    func verifyRestoredProject() async {
        guard
            let expectedProjectID =
                selectedProject?.id
        else {
            isSelectedProjectVerified = true
            return
        }
        guard !isVerifyingRestoredProject else {
            return
        }

        isVerifyingRestoredProject = true
        isSelectedProjectVerified = false
        defer {
            isVerifyingRestoredProject = false
        }

        do {
            let project = try await service
                .loadProject(
                    projectID:
                        expectedProjectID
                )
            guard
                !Task.isCancelled,
                isAccountCurrent(),
                selectedProject?.id
                    == expectedProjectID
            else {
                return
            }
            guard
                project.id
                    == expectedProjectID
            else {
                failure =
                    .projectVerification(
                        .api(.invalidResponse)
                    )
                return
            }

            let refreshedSelection =
                GitLabIssueCreationProjectSelection(
                    project: project
                )
            let didRefreshSelection =
                refreshedSelection
                    != selectedProject
            selectedProject =
                refreshedSelection
            isSelectedProjectVerified = true
            if
                case .projectVerification =
                    failure
            {
                failure = nil
            }
            replaceMetadataModels(
                projectID: project.id
            )
            if didRefreshSelection {
                draftRevision += 1
                schedulePersistence()
            }
        } catch {
            guard
                !Task.isCancelled,
                isAccountCurrent(),
                selectedProject?.id
                    == expectedProjectID
            else {
                return
            }

            switch error {
            case .api(.notFound),
                 .api(.forbidden):
                selectedProject = nil
                selectedLabelNames.removeAll()
                selectedAssigneeIDs.removeAll()
                labelsModel = nil
                membersModel = nil
                isSelectedProjectVerified = true
                failure =
                    .restoredProjectUnavailable
                draftRevision += 1
                schedulePersistence()
            default:
                failure =
                    .projectVerification(error)
            }
        }
    }

    func loadProjectsIfNeeded() async {
        await projectsModel
            .loadIfNeeded()
    }

    func selectProject(
        _ project: GitLabProject
    ) {
        let selection =
            GitLabIssueCreationProjectSelection(
                project: project
            )
        guard
            selection != selectedProject
        else {
            return
        }

        let changesProject =
            selectedProject?.id
                != selection.id
        selectedProject = selection
        isSelectedProjectVerified = true
        switch failure {
        case .restoredProjectUnavailable,
             .projectVerification:
            failure = nil
        default:
            break
        }
        if changesProject {
            selectedLabelNames.removeAll()
            selectedAssigneeIDs.removeAll()
        }
        replaceMetadataModels(
            projectID: selection.id
        )
        userValueDidChange()
    }

    func loadSelectedProjectMetadata()
        async
    {
        guard
            selectedProject != nil,
            isSelectedProjectVerified,
            let labelsModel,
            let membersModel
        else {
            return
        }

        async let labels: Void =
            labelsModel.loadIfNeeded()
        async let members: Void =
            membersModel.loadIfNeeded()
        _ = await (labels, members)
    }

    func loadNextAssignableMembersPageIfNeeded(
        after member: GitLabProjectMember
    ) async {
        guard
            let membersModel,
            displayedAssignableMembers
                .last?.id == member.id,
            let rawTail = membersModel.items.last
        else {
            return
        }
        await membersModel
            .loadNextPageIfNeeded(
                after: rawTail
            )
    }

    func loadUntilAssignableMemberVisibleIfNeeded()
        async
    {
        guard
            let membersModel,
            membersModel.searchText
                .trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                .isEmpty
        else {
            return
        }

        while
            displayedAssignableMembers.isEmpty,
            let previousNextPageURL =
                membersModel.nextPageURL,
            let rawTail =
                membersModel.items.last,
            !Task.isCancelled
        {
            await membersModel
                .loadNextPageIfNeeded(
                    after: rawTail
                )
            guard
                membersModel.nextPageURL
                    != previousNextPageURL,
                membersModel.loadError == nil
            else {
                return
            }
        }
    }

    func toggleLabel(
        _ label: GitLabProjectLabel
    ) {
        guard
            label.archived != true,
            !label.name.isEmpty
        else {
            return
        }
        if
            let index =
                selectedLabelNames
                .firstIndex(
                    of: label.name
                )
        {
            selectedLabelNames.remove(
                at: index
            )
        } else {
            selectedLabelNames.append(
                label.name
            )
        }
        userValueDidChange()
    }

    func toggleAssignee(
        _ member: GitLabProjectMember
    ) {
        guard
            member.id > 0,
            member.isActive
        else {
            return
        }
        if
            let index =
                selectedAssigneeIDs
                .firstIndex(
                    of: member.id
                )
        {
            selectedAssigneeIDs.remove(
                at: index
            )
        } else {
            selectedAssigneeIDs.append(
                member.id
            )
        }
        userValueDidChange()
    }

    func submit() async {
        guard
            hasRestoredDraft,
            !isSubmitting,
            !requiresDeliveryCheck,
            isAccountCurrent()
        else {
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }

        let input: GitLabIssueCreationInput
        do {
            input = try creationInput()
        } catch {
            failure = .validation(error)
            return
        }

        isSubmitting = true
        failure = nil
        didSucceed = false
        persistenceTask?.cancel()
        persistenceTask = nil
        defer {
            isSubmitting = false
        }

        guard
            await persistCurrentDraft()
        else {
            return
        }

        pendingSubmissionFingerprint =
            Self.fingerprint(input)
        draftRevision += 1
        guard
            await persistCurrentDraft()
        else {
            return
        }
        if Task.isCancelled {
            await handleRejectedMutation(
                .api(.cancelled)
            )
            return
        }

        do {
            let issue = try await service
                .createIssue(input)
            guard
                isAccountCurrent()
            else {
                return
            }
            guard
                issue.id > 0,
                issue.iid > 0,
                issue.projectID
                    == input.projectID
            else {
                await service
                    .invalidateAffectedReads()
                failure =
                    .invalidAuthoritativeResponse
                return
            }

            await service
                .invalidateAffectedReads()
            guard isAccountCurrent() else {
                return
            }

            await draftStore.remove(
                for: draftKey
            )
            pendingSubmissionFingerprint =
                nil
            failure = nil
            didSucceed = true
            onSuccess(issue)
        } catch {
            guard isAccountCurrent() else {
                return
            }
            switch
                error
                .mutationDeliveryCertainty
            {
            case .rejected:
                await handleRejectedMutation(
                    error
                )
            case .deliveryUnknown:
                failure = .mutation(
                    error,
                    certainty:
                        .deliveryUnknown
                )
            }
        }
    }

    @discardableResult
    func acknowledgeDeliveryCheck()
        async -> Bool
    {
        guard
            hasRestoredDraft,
            !isSubmitting,
            requiresDeliveryCheck
        else {
            return false
        }

        pendingSubmissionFingerprint =
            nil
        draftRevision += 1
        guard
            await persistCurrentDraft()
        else {
            return false
        }
        failure = nil
        return true
    }

    @discardableResult
    func persistForDismissal()
        async -> Bool
    {
        guard !isSubmitting else {
            return false
        }
        guard !didSucceed else {
            return true
        }
        guard hasRestoredDraft else {
            return true
        }
        return await persistCurrentDraft()
    }

    private func handleRejectedMutation(
        _ error: GitLabSessionClientError
    ) async {
        pendingSubmissionFingerprint =
            nil
        draftRevision += 1
        guard
            await persistCurrentDraft()
        else {
            return
        }
        failure = .mutation(
            error,
            certainty: .rejected
        )
    }

    private func creationInput()
        throws(
            GitLabIssueCreationValidationError
        ) -> GitLabIssueCreationInput
    {
        try GitLabIssueCreationInput(
            projectID:
                selectedProject?.id,
            title: title,
            description: rawDescription,
            labelNames:
                selectedLabelNames,
            assigneeIDs:
                selectedAssigneeIDs,
            confidential: confidential,
            dueDate: dueDate
        )
    }

    private func formValueDidChange(
        changed: Bool
    ) {
        guard
            changed,
            !isApplyingDraft
        else {
            return
        }
        userValueDidChange()
    }

    private func userValueDidChange() {
        draftRevision += 1
        didSucceed = false
        switch failure {
        case .validation,
             .readOnly,
             .draftStorage,
             .mutation(_, .rejected):
            failure = nil
        case .restoredProjectUnavailable,
             .projectVerification,
             .mutation(_, .deliveryUnknown),
             .invalidAuthoritativeResponse,
             .deliveryCheckRequired,
             nil:
            break
        }
        if hasRestoredDraft {
            schedulePersistence()
        }
    }

    private func apply(
        _ draft: GitLabIssueCreationDraft
    ) {
        isApplyingDraft = true
        selectedProject =
            draft.selectedProject
        isSelectedProjectVerified =
            selectedProject == nil
        title = draft.title
        rawDescription =
            draft.rawDescription
        selectedLabelNames =
            draft.labelNames
        selectedAssigneeIDs =
            draft.assigneeIDs
        confidential =
            draft.confidential
        dueDate = draft.dueDate
        pendingSubmissionFingerprint =
            draft
            .pendingSubmissionFingerprint
        isApplyingDraft = false

        if let projectID =
            selectedProject?.id
        {
            replaceMetadataModels(
                projectID: projectID
            )
        }
    }

    private func scheduleProjectSearch() {
        projectSearchGeneration &+= 1
        let generation =
            projectSearchGeneration
        projectSearchTask?.cancel()
        let query = Self.normalizedSearch(
            projectSearchText
        )
        let model = Self.makeProjectsModel(
            service: service,
            search: query
        )
        projectsModel = model
        let searchDebounce =
            searchDebounce

        guard hasRestoredDraft else {
            return
        }
        projectSearchTask = Task {
            do {
                try await Task.sleep(
                    for: searchDebounce
                )
                try Task.checkCancellation()
            } catch {
                return
            }
            guard
                generation
                    == projectSearchGeneration,
                isAccountCurrent()
            else {
                return
            }
            await model.loadIfNeeded()
        }
    }

    private func replaceMetadataModels(
        projectID: Int
    ) {
        labelsModel =
            Self.makeLabelsModel(
                service: service,
                projectID: projectID
            )
        membersModel =
            Self.makeMembersModel(
                service: service,
                projectID: projectID
            )
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        let draft = currentDraft
        let draftStore = draftStore
        let draftKey = draftKey

        persistenceTask = Task {
            do {
                try await Task.sleep(
                    for: .milliseconds(350)
                )
                try Task.checkCancellation()
                try await draftStore.store(
                    draft,
                    for: draftKey
                )
                guard !Task.isCancelled else {
                    return
                }
                if failure == .draftStorage {
                    failure = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                failure = .draftStorage
            }
        }
    }

    private func persistCurrentDraft()
        async -> Bool
    {
        persistenceTask?.cancel()
        persistenceTask = nil
        do {
            try await draftStore.store(
                currentDraft,
                for: draftKey
            )
            if failure == .draftStorage {
                failure = nil
            }
            return true
        } catch {
            failure = .draftStorage
            return false
        }
    }

    private var draftKey:
        GitLabIssueCreationDraftKey
    {
        GitLabIssueCreationDraftKey(
            accountID: accountID
        )
    }

    private var currentDraft:
        GitLabIssueCreationDraft
    {
        GitLabIssueCreationDraft(
            selectedProject:
                selectedProject,
            title: title,
            description: rawDescription,
            labelNames:
                selectedLabelNames,
            assigneeIDs:
                selectedAssigneeIDs,
            confidential: confidential,
            dueDate: dueDate,
            revision: draftRevision,
            pendingSubmissionFingerprint:
                pendingSubmissionFingerprint
        )
    }

    private static func normalizedSearch(
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

    private static func makeProjectsModel(
        service:
            any GitLabIssueCreationServing,
        search: String?
    ) -> GitLabPaginatedResourceModel<
        GitLabProject,
        Int
    > {
        GitLabPaginatedResourceModel(
            loadPage: {
                (
                    nextPageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabProject
                > in
                try await service
                    .loadProjectsPage(
                        search: search,
                        after: nextPageURL
                    )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabProject
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await service
                    .loadProjectsFirstPage(
                        search: search,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: \.id,
            searchValues: {
                [
                    $0.name,
                    $0.nameWithNamespace,
                    $0.pathWithNamespace,
                ]
            }
        )
    }

    private static func makeLabelsModel(
        service:
            any GitLabIssueCreationServing,
        projectID: Int
    ) -> GitLabPaginatedResourceModel<
        GitLabProjectLabel,
        Int
    > {
        GitLabPaginatedResourceModel(
            loadPage: {
                (
                    nextPageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabProjectLabel
                > in
                try await service
                    .loadLabelsPage(
                        projectID: projectID,
                        after: nextPageURL
                    )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabProjectLabel
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await service
                    .loadLabelsFirstPage(
                        projectID: projectID,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: \.id,
            searchValues: {
                [$0.name]
            }
        )
    }

    private static func makeMembersModel(
        service:
            any GitLabIssueCreationServing,
        projectID: Int
    ) -> GitLabPaginatedResourceModel<
        GitLabProjectMember,
        Int
    > {
        GitLabPaginatedResourceModel(
            loadPage: {
                (
                    nextPageURL: URL?
                ) async throws(
                    GitLabSessionClientError
                ) -> GitLabResourcePage<
                    GitLabProjectMember
                > in
                try await service
                    .loadMembersPage(
                        projectID: projectID,
                        after: nextPageURL
                    )
            },
            loadFirstPage: {
                (
                    refreshBehavior:
                        GitLabCacheRefreshBehavior,
                    onPage:
                        @escaping @Sendable (
                            GitLabResourcePageEvent<
                                GitLabProjectMember
                            >
                        ) async -> Void
                ) async throws(
                    GitLabSessionClientError
                ) -> Void in
                try await service
                    .loadMembersFirstPage(
                        projectID: projectID,
                        refreshBehavior:
                            refreshBehavior,
                        onPage: onPage
                    )
            },
            identity: \.id,
            searchValues: {
                [
                    $0.name,
                    $0.username,
                ]
            }
        )
    }

    private static func fingerprint(
        _ input: GitLabIssueCreationInput
    ) -> String {
        var values = [
            String(input.projectID),
            input.title,
            input.rawDescription,
            input.confidential ? "1" : "0",
            input.dueDate?.apiValue ?? "",
            String(input.labelNames.count),
        ]
        values.append(
            contentsOf:
                input.labelNames
        )
        values.append(
            String(input.assigneeIDs.count)
        )
        values.append(
            contentsOf:
                input.assigneeIDs
                .map(String.init)
        )
        let serialized = values
            .map {
                "\($0.utf8.count):\($0)"
            }
            .joined()
        return SHA256.hash(
            data: Data(serialized.utf8)
        )
        .map {
            String(
                format: "%02x",
                $0
            )
        }
        .joined()
    }
}
