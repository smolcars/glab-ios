import Foundation
import Observation

nonisolated enum GitLabDiscussionComposerTarget:
    Equatable,
    Hashable,
    Identifiable,
    Sendable
{
    case newDiscussion
    case newDiffDiscussion(
        position: GitLabDiffLinePosition
    )
    case reply(discussionID: String)

    var id: Self {
        self
    }

    var discussionID: String? {
        switch self {
        case .newDiscussion,
             .newDiffDiscussion:
            nil
        case let .reply(discussionID):
            discussionID
        }
    }
}

nonisolated enum GitLabDiscussionComposerResult:
    Equatable,
    Sendable
{
    case discussion(GitLabDiscussion)
    case reply(
        GitLabDiscussionNote,
        discussionID: String
    )
}

nonisolated enum GitLabDiscussionComposerFailure:
    Equatable,
    Sendable
{
    case emptyBody
    case readOnly
    case draftStorage
    case mutation(
        GitLabDiscussionMutationError,
        certainty:
            GitLabMutationDeliveryCertainty
    )

    var certainty:
        GitLabMutationDeliveryCertainty?
    {
        guard
            case let .mutation(
                _,
                certainty
            ) = self
        else {
            return nil
        }
        return certainty
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        guard
            case let .mutation(
                .request(error),
                _
            ) = self,
            error.requiresReauthentication
        else {
            return nil
        }
        return error
    }
}

extension GitLabDiscussionMutationError {
    var deliveryCertainty:
        GitLabMutationDeliveryCertainty
    {
        switch self {
        case .encoding,
             .invalidDiffResource,
             .latestDiffVersionUnavailable,
             .staleDiffVersion:
            .rejected
        case let .request(error):
            error.mutationDeliveryCertainty
        }
    }
}

@MainActor
@Observable
final class GitLabDiscussionComposerModel {
    var body = "" {
        didSet {
            bodyDidChange(from: oldValue)
        }
    }

    private(set) var hasRestoredDraft = false
    private(set) var draftRevision = 0
    private(set) var isSending = false
    private(set) var failure:
        GitLabDiscussionComposerFailure?
    private(set) var didSucceed = false

    let target: GitLabDiscussionComposerTarget
    let apiAccess: GitLabAPIAccess

    @ObservationIgnored
    private let draftKey:
        GitLabDiscussionDraftKey
    @ObservationIgnored
    private let mutator:
        any GitLabDiscussionMutating
    @ObservationIgnored
    private let draftStore:
        any GitLabDiscussionDraftStoring
    @ObservationIgnored
    private let onSuccess:
        @MainActor (
            GitLabDiscussionComposerResult
        ) -> Void
    @ObservationIgnored
    private var persistenceTask:
        Task<Void, Never>?
    @ObservationIgnored
    private var isApplyingRestoredDraft = false
    @ObservationIgnored
    private var isRestoringDraft = false

    init(
        accountID: GitLabAccountID,
        resource: GitLabDiscussionResource,
        target: GitLabDiscussionComposerTarget,
        apiAccess: GitLabAPIAccess,
        mutator: any GitLabDiscussionMutating,
        draftStore:
            any GitLabDiscussionDraftStoring,
        onSuccess:
            @escaping @MainActor (
                GitLabDiscussionComposerResult
            ) -> Void
    ) {
        draftKey = GitLabDiscussionDraftKey(
            accountID: accountID,
            resource: resource,
            target: target
        )
        self.target = target
        self.apiAccess = apiAccess
        self.mutator = mutator
        self.draftStore = draftStore
        self.onSuccess = onSuccess
    }

    deinit {
        persistenceTask?.cancel()
    }

    var canSend: Bool {
        hasRestoredDraft
            && apiAccess.canWrite
            && !isSending
            && !body.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
    }

    var canSubmitFromToolbar: Bool {
        canSend
            && failure?.certainty
                != .deliveryUnknown
    }

    var authenticationFailure:
        GitLabSessionClientError?
    {
        failure?.authenticationFailure
    }

    func restoreDraft() async {
        guard
            !hasRestoredDraft,
            !isRestoringDraft
        else {
            return
        }
        isRestoringDraft = true
        let draft = await draftStore.draft(
            for: draftKey
        )
        isRestoringDraft = false

        let hadLocalEdits =
            draftRevision > 0
        if
            !hadLocalEdits,
            body.isEmpty,
            let draft
        {
            isApplyingRestoredDraft = true
            draftRevision = draft.revision
            body = draft.body
            isApplyingRestoredDraft = false
        }

        hasRestoredDraft = true
        if hadLocalEdits {
            draftRevision = max(
                draftRevision,
                (draft?.revision ?? -1) + 1
            )
            schedulePersistence()
        }
    }

    func send() async {
        guard
            hasRestoredDraft,
            !isSending
        else {
            return
        }
        guard apiAccess.canWrite else {
            failure = .readOnly
            return
        }

        let commentBody:
            GitLabDiscussionCommentBody
        do {
            commentBody =
                try GitLabDiscussionCommentBody(
                    body
                )
        } catch {
            failure = .emptyBody
            return
        }

        isSending = true
        didSucceed = false
        failure = nil
        defer {
            isSending = false
        }

        guard await persistCurrentDraft() else {
            return
        }
        guard !Task.isCancelled else {
            failure = .mutation(
                .request(.api(.cancelled)),
                certainty: .rejected
            )
            return
        }

        do {
            let result = try await post(
                commentBody
            )

            onSuccess(result)
            await draftStore.remove(
                for: draftKey
            )
            persistenceTask?.cancel()
            persistenceTask = nil
            failure = nil
            didSucceed = true
        } catch {
            failure = .mutation(
                error,
                certainty:
                    error.deliveryCertainty
            )
        }
    }

    private func post(
        _ body: GitLabDiscussionCommentBody
    ) async throws(GitLabDiscussionMutationError)
        -> GitLabDiscussionComposerResult
    {
        switch target {
        case .newDiscussion:
            .discussion(
                try await mutator
                    .createDiscussion(
                        for: draftKey.resource,
                        body: body
                    )
            )
        case let .newDiffDiscussion(position):
            if
                case let .mergeRequest(route) =
                    draftKey.resource
            {
                .discussion(
                    try await mutator
                        .createDiffDiscussion(
                            for: route,
                            body: body,
                            position: position
                        )
                )
            } else {
                throw .invalidDiffResource
            }
        case let .reply(discussionID):
            .reply(
                try await mutator.reply(
                    to: discussionID,
                    in: draftKey.resource,
                    body: body
                ),
                discussionID: discussionID
            )
        }
    }

    @discardableResult
    func persistForDismissal() async -> Bool {
        guard !isSending else {
            return false
        }
        return await persistCurrentDraft()
    }

    private func bodyDidChange(
        from oldValue: String
    ) {
        guard
            body != oldValue,
            !isApplyingRestoredDraft
        else {
            return
        }

        draftRevision += 1
        if failure?.certainty == .rejected
            || failure == .emptyBody
        {
            failure = nil
        }
        if hasRestoredDraft {
            schedulePersistence()
        }
    }

    private func schedulePersistence() {
        persistenceTask?.cancel()
        let draft = currentDraft
        let draftStore = draftStore
        let draftKey = draftKey

        persistenceTask = Task { [weak self] in
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
                if self?.failure
                    == .draftStorage
                {
                    self?.failure = nil
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self?.failure = .draftStorage
            }
        }
    }

    private func persistCurrentDraft() async -> Bool {
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

    private var currentDraft:
        GitLabDiscussionDraft
    {
        GitLabDiscussionDraft(
            body: body,
            revision: draftRevision
        )
    }
}
