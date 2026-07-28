import Foundation
import Testing
@testable import Glab

@Suite("GitLab resource editor model")
struct GitLabResourceEditorModelTests {
    @Test("Restores an exact resource draft and its original baseline")
    @MainActor
    func restoresDraft() async throws {
        let context = try ResourceEditorTestContext()
        let storedBaseline = context.snapshot(
            title: "Original",
            description: "Original body",
            updatedAt: Date(
                timeIntervalSince1970: 1_700_000_000
            )
        )
        let draft = GitLabResourceEditDraft(
            baseline: storedBaseline,
            title: "Draft title",
            description: "Draft **body**",
            revision: 7
        )
        let store = RecordingResourceEditDraftStore(
            draft: draft
        )
        let model = context.makeModel(
            draftStore: store
        )

        await model.restoreDraft()

        #expect(model.hasRestoredDraft)
        #expect(model.baseline == storedBaseline)
        #expect(model.title == "Draft title")
        #expect(
            model.rawDescription
                == "Draft **body**"
        )
        #expect(model.draftRevision == 7)
        #expect(model.isDirty)
    }

    @Test("Local typing during a delayed restore wins with a newer revision")
    @MainActor
    func typingDuringRestoreWins() async throws {
        let context = try ResourceEditorTestContext()
        let storedDraft =
            GitLabResourceEditDraft(
                baseline: context.baseline,
                title: "Older draft",
                description: "Older body",
                revision: 7
            )
        let store = GatedResourceEditDraftStore(
            draft: storedDraft
        )
        let model = context.makeModel(
            draftStore: store
        )

        let restoration = Task {
            await model.restoreDraft()
        }
        await store.waitUntilReadStarts()
        model.title = "Typed while restoring"
        await store.releaseRead()
        await restoration.value
        _ = await model.persistForDismissal()

        #expect(
            model.title
                == "Typed while restoring"
        )
        #expect(
            model.rawDescription
                == context.baseline.rawDescription
        )
        #expect(model.baseline == context.baseline)
        #expect(model.draftRevision == 8)
        #expect(
            await store.storedDraft
                == GitLabResourceEditDraft(
                    baseline:
                        context.baseline,
                    title:
                        "Typed while restoring",
                    description:
                        context.baseline
                            .rawDescription,
                    revision: 8
                )
        )
    }

    @Test("A stale draft already reflected by GitLab is discarded")
    @MainActor
    func discardsAppliedDraft() async throws {
        let context = try ResourceEditorTestContext(
            title: "Already saved",
            description: "Server body"
        )
        let draft = GitLabResourceEditDraft(
            baseline: context.snapshot(
                title: "Older title",
                description: "Older body",
                updatedAt: Date(
                    timeIntervalSince1970:
                        1_700_000_000
                )
            ),
            title: "Already saved",
            description: "Server body",
            revision: 5
        )
        let store = RecordingResourceEditDraftStore(
            draft: draft
        )
        let model = context.makeModel(
            draftStore: store
        )

        await model.restoreDraft()

        #expect(model.baseline == context.baseline)
        #expect(!model.isDirty)
        #expect(await store.storedDraft == nil)
    }

    @Test("A clean dismissal removes a redundant baseline draft")
    @MainActor
    func cleanDismissalRemovesDraft() async throws {
        let context = try ResourceEditorTestContext()
        let store = RecordingResourceEditDraftStore(
            draft: GitLabResourceEditDraft(
                baseline: context.baseline,
                title: context.baseline.title,
                description:
                    context.baseline.rawDescription,
                revision: 1
            )
        )
        let model = context.makeModel(
            draftStore: store
        )
        await model.restoreDraft()

        let didPersist =
            await model.persistForDismissal()

        #expect(didPersist)
        #expect(await store.storedDraft == nil)
    }

    @Test("Discard restores the baseline and removes the local draft")
    @MainActor
    func discardsLocalChanges() async throws {
        let context = try ResourceEditorTestContext()
        let store =
            RecordingResourceEditDraftStore()
        let model = context.makeModel(
            draftStore: store
        )
        await model.restoreDraft()
        model.title = "Draft title"
        model.rawDescription = "Draft body"
        _ = await model.persistForDismissal()

        let didDiscard =
            await model.discardDraft()

        #expect(didDiscard)
        #expect(model.title == context.baseline.title)
        #expect(
            model.rawDescription
                == context.baseline.rawDescription
        )
        #expect(!model.isDirty)
        #expect(await store.storedDraft == nil)
    }

    @Test("A draft storage failure blocks every network request")
    @MainActor
    func storageFailureBlocksSave() async throws {
        let context = try ResourceEditorTestContext()
        let service =
            RecordingResourceEditingService()
        let store = RecordingResourceEditDraftStore(
            failsStores: true
        )
        let model = context.makeModel(
            service: service,
            draftStore: store
        )
        await model.restoreDraft()
        model.title = "Edited"

        await model.save()

        #expect(
            model.failure == .draftStorage
        )
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("Read-only accounts can edit locally but never request a mutation")
    @MainActor
    func readOnlyNeverMutates() async throws {
        let context = try ResourceEditorTestContext()
        let service =
            RecordingResourceEditingService()
        let model = context.makeModel(
            apiAccess: .readOnly,
            service: service
        )
        await model.restoreDraft()
        model.title = "Local draft"

        await model.save()

        #expect(model.failure == .readOnly)
        #expect(model.isDirty)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("An unchanged submission sends no request")
    @MainActor
    func unchangedSubmission() async throws {
        let context = try ResourceEditorTestContext()
        let service =
            RecordingResourceEditingService()
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()

        await model.save()

        #expect(
            model.failure
                == .validation(.noChanges)
        )
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)
    }

    @Test("An empty title fails validation before any request")
    @MainActor
    func rejectsEmptyTitle() async throws {
        let context = try ResourceEditorTestContext()
        let service =
            RecordingResourceEditingService()
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = " \n\t "

        await model.save()

        #expect(
            model.failure
                == .validation(.emptyTitle)
        )
        #expect(!model.canSave)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)

        model.title = "Fixed title"

        #expect(model.canSave)
    }

    @Test("A description over GitLab's limit fails before any request")
    @MainActor
    func rejectsOversizedDescription() async throws {
        let context = try ResourceEditorTestContext()
        let service =
            RecordingResourceEditingService()
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.rawDescription = String(
            repeating: "a",
            count:
                GitLabResourceEditChanges
                    .maximumDescriptionLength
                    + 1
        )

        await model.save()

        #expect(
            model.failure
                == .validation(
                    .descriptionTooLong(
                        maximum:
                            GitLabResourceEditChanges
                                .maximumDescriptionLength
                    )
                )
        )
        #expect(!model.canSave)
        #expect(await service.loadCount == 0)
        #expect(await service.updateCount == 0)

        model.rawDescription = "Valid body"

        #expect(model.canSave)
    }

    @Test("The maximum description length is accepted without normalization")
    @MainActor
    func acceptsMaximumDescription() async throws {
        let context = try ResourceEditorTestContext()
        let description = String(
            repeating: "a",
            count:
                GitLabResourceEditChanges
                    .maximumDescriptionLength
        )
        let authoritative = context.result(
            description: description
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(authoritative),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.rawDescription = description

        await model.save()

        let changes = try #require(
            await service.updates.first?.changes
        )
        #expect(changes.description == description)
        #expect(model.didSucceed)
    }

    @Test("Unicode and raw Markdown are sent exactly as edited")
    @MainActor
    func preservesUnicodeMarkdown() async throws {
        let context = try ResourceEditorTestContext()
        let description =
            "## Café 👩🏽‍💻\n- [ ] **Ship it**\n\n"
        let authoritative = context.result(
            description: description
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(authoritative),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.rawDescription = description

        await model.save()

        let changes = try #require(
            await service.updates.first?.changes
        )
        #expect(changes.description == description)
        #expect(model.rawDescription == description)
    }

    @Test("A failed freshness read preserves the draft and sends no PUT")
    @MainActor
    func preservesDraftAfterFreshnessFailure()
        async throws
    {
        let context = try ResourceEditorTestContext()
        let failure =
            GitLabSessionClientError.api(
                .connectivity(.timedOut)
            )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .failure(failure),
                ]
            )
        let store =
            RecordingResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )
        await model.restoreDraft()
        model.title = "Edited"

        await model.save()

        #expect(
            model.failure == .freshness(failure)
        )
        #expect(await service.updateCount == 0)
        #expect(await store.storedDraft != nil)
    }

    @Test("The shared editor updates a merge request through its exact target")
    @MainActor
    func updatesMergeRequest() async throws {
        let baseline:
            GitLabResourceEditResult =
                .mergeRequest(
                    makeTestMergeRequest(
                        title: "Original MR",
                        description: "Original body"
                    )
                )
        let context =
            try ResourceEditorTestContext(
                baselineResult: baseline
            )
        let authoritative:
            GitLabResourceEditResult =
                .mergeRequest(
                    makeTestMergeRequest(
                        title: "Edited MR",
                        description: "Original body",
                        updatedAt: Date(
                            timeIntervalSince1970:
                                1_700_004_000
                        )
                    )
                )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(baseline),
                ],
                updateResults: [
                    .success(authoritative),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited MR"

        await model.save()

        let update = try #require(
            await service.updates.first
        )
        #expect(
            update.target
                == baseline.snapshot.target
        )
        #expect(update.changes.title == "Edited MR")
        #expect(model.didSucceed)
    }

    @Test("Editor failure descriptions redact resource content")
    func redactsFailureDescriptions() {
        let conflict =
            GitLabResourceEditConflict(
                fields: [.title],
                latest:
                    GitLabResourceEditSnapshot(
                        target:
                            .issue(
                                GitLabIssueRoute(
                                    projectID: 42,
                                    issueIID: 7
                                )
                            ),
                        resourceID: 101,
                        title: "private-content",
                        description:
                            "private-content",
                        updatedAt: Date()
                    )
            )
        let failure =
            GitLabResourceEditorFailure
                .conflict(conflict)

        #expect(
            failure.description
                == "GitLabResourceEditorFailure(<redacted>)"
        )
        #expect(
            failure.debugDescription
                == failure.description
        )
    }

    @Test("A fresh baseline updates once and reconciles before draft removal")
    @MainActor
    func savesFreshBaseline() async throws {
        let context = try ResourceEditorTestContext()
        let events = ResourceEditorEventRecorder()
        let authoritative = context.result(
            title: "Edited title",
            description:
                context.baseline
                    .rawDescription,
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_004_000
            )
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(authoritative),
                ],
                events: events
            )
        let store =
            RecordingResourceEditDraftStore(
                events: events
            )
        var received:
            GitLabResourceEditResult?
        let model = context.makeModel(
            service: service,
            draftStore: store,
            onSuccess: {
                received = $0
                events.record("reconcile")
            }
        )
        await model.restoreDraft()
        model.title = "Edited title"

        await model.save()

        #expect(received == authoritative)
        #expect(model.didSucceed)
        #expect(model.failure == nil)
        #expect(model.baseline == authoritative.snapshot)
        #expect(!model.isDirty)
        #expect(await store.storedDraft == nil)
        #expect(await service.updateCount == 1)
        let changes = try #require(
            await service.updates.first?.changes
        )
        #expect(changes.title == "Edited title")
        #expect(changes.description == nil)
        #expect(
            events.values
                == [
                    "store",
                    "load-latest",
                    "update",
                    "reconcile",
                    "remove",
                ]
        )
    }

    @Test("An updated timestamp alone rebases without a false conflict")
    @MainActor
    func rebasesTimestampOnly() async throws {
        let context = try ResourceEditorTestContext()
        let latest = context.result(
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_700
            )
        )
        let authoritative = context.result(
            title: "Edited",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_800
            )
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [.success(latest)],
                updateResults: [
                    .success(authoritative),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited"

        await model.save()

        #expect(model.didSucceed)
        #expect(await service.updateCount == 1)
    }

    @Test("An untouched server title is rebased and omitted from the PUT")
    @MainActor
    func rebasesUntouchedTitle() async throws {
        let context = try ResourceEditorTestContext()
        let latest = context.result(
            title: "Server title",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_700
            )
        )
        let authoritative = context.result(
            title: "Server title",
            description: "Local body",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_800
            )
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [.success(latest)],
                updateResults: [
                    .success(authoritative),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.rawDescription = "Local body"

        await model.save()

        #expect(model.title == "Server title")
        let changes = try #require(
            await service.updates.first?.changes
        )
        #expect(changes.title == nil)
        #expect(changes.description == "Local body")
    }

    @Test("An untouched server description is rebased and omitted from the PUT")
    @MainActor
    func rebasesUntouchedDescription() async throws {
        let context = try ResourceEditorTestContext()
        let latest = context.result(
            description: "Server body",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_700
            )
        )
        let authoritative = context.result(
            title: "Local title",
            description: "Server body",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_800
            )
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [.success(latest)],
                updateResults: [
                    .success(authoritative),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Local title"

        await model.save()

        #expect(
            model.rawDescription == "Server body"
        )
        let changes = try #require(
            await service.updates.first?.changes
        )
        #expect(changes.title == "Local title")
        #expect(changes.description == nil)
    }

    @Test(
        "A locally edited field changed on GitLab becomes a conflict",
        arguments: [
            (
                localTitle: "Local title",
                localDescription: "Original body",
                serverTitle: "Server title",
                serverDescription: "Original body",
                expected:
                    Set([
                        GitLabResourceEditField.title,
                    ])
            ),
            (
                localTitle: "Original",
                localDescription: "Local body",
                serverTitle: "Original",
                serverDescription: "Server body",
                expected:
                    Set([
                        GitLabResourceEditField
                            .description,
                    ])
            ),
            (
                localTitle: "Local title",
                localDescription: "Local body",
                serverTitle: "Server title",
                serverDescription: "Server body",
                expected:
                    Set([
                        GitLabResourceEditField.title,
                        GitLabResourceEditField
                            .description,
                    ])
            ),
        ]
    )
    @MainActor
    func detectsFieldConflicts(
        localTitle: String,
        localDescription: String,
        serverTitle: String,
        serverDescription: String,
        expected: Set<GitLabResourceEditField>
    ) async throws {
        let context = try ResourceEditorTestContext(
            title: "Original",
            description: "Original body"
        )
        let latest = context.result(
            title: serverTitle,
            description: serverDescription,
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_003_700
            )
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [.success(latest)]
            )
        let store =
            RecordingResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )
        await model.restoreDraft()
        model.title = localTitle
        model.rawDescription = localDescription

        await model.save()

        #expect(
            model.failure
                == .conflict(
                    GitLabResourceEditConflict(
                        fields: expected,
                        latest: latest.snapshot
                    )
                )
        )
        #expect(await service.updateCount == 0)
        #expect(await store.storedDraft != nil)
    }

    @Test("A different stable resource ID becomes an identity conflict")
    @MainActor
    func detectsIdentityConflict() async throws {
        let context = try ResourceEditorTestContext()
        let latest = context.result(
            resourceID: 999,
            title: "Original",
            description: "Original body"
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [.success(latest)]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Local title"

        await model.save()

        #expect(
            model.failure
                == .conflict(
                    GitLabResourceEditConflict(
                        fields: [.resourceIdentity],
                        latest: latest.snapshot
                    )
                )
        )
        #expect(await service.updateCount == 0)
    }

    @Test("A definitely rejected PUT preserves an immediately retryable draft")
    @MainActor
    func preservesRejectedMutation() async throws {
        let context = try ResourceEditorTestContext()
        let failure =
            GitLabSessionClientError.api(.forbidden)
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [.failure(failure)]
            )
        let store =
            RecordingResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )
        await model.restoreDraft()
        model.title = "Edited"

        await model.save()

        #expect(
            model.failure
                == .mutation(
                    failure,
                    certainty: .rejected
                )
        )
        #expect(model.canSave)
        #expect(await store.storedDraft != nil)
    }

    @Test("An ambiguous PUT is reconciled as success when GitLab has the intent")
    @MainActor
    func reconcilesUnknownDeliverySuccess() async throws {
        let context = try ResourceEditorTestContext()
        let intended = context.result(
            title: "Edited",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_004_000
            )
        )
        let failure =
            GitLabSessionClientError.api(
                .server(statusCode: 500)
            )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                    .success(intended),
                ],
                updateResults: [.failure(failure)]
            )
        let store =
            RecordingResourceEditDraftStore()
        var received:
            GitLabResourceEditResult?
        let model = context.makeModel(
            service: service,
            draftStore: store,
            onSuccess: {
                received = $0
            }
        )
        await model.restoreDraft()
        model.title = "Edited"
        await model.save()

        #expect(
            model.failure
                == .mutation(
                    failure,
                    certainty:
                        .deliveryUnknown
                )
        )
        #expect(!model.canSave)

        await model.checkGitLab()

        #expect(received == intended)
        #expect(model.didSucceed)
        #expect(model.failure == nil)
        #expect(await store.storedDraft == nil)
        #expect(await service.updateCount == 1)
    }

    @Test("An ambiguous PUT can be retried only after GitLab proves no change")
    @MainActor
    func reconcilesUnknownDeliveryNoChange() async throws {
        let context = try ResourceEditorTestContext()
        let unchanged = context.result(
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_004_000
            )
        )
        let failure =
            GitLabSessionClientError.api(
                .connectivity(
                    .networkConnectionLost
                )
            )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                    .success(unchanged),
                ],
                updateResults: [.failure(failure)]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited"
        await model.save()

        await model.checkGitLab()

        #expect(!model.didSucceed)
        #expect(model.failure == nil)
        #expect(model.canSave)
        #expect(model.baseline == unchanged.snapshot)
        #expect(model.title == "Edited")
        #expect(await service.updateCount == 1)
    }

    @Test("An ambiguous PUT becomes a conflict when GitLab has another value")
    @MainActor
    func reconcilesUnknownDeliveryConflict() async throws {
        let context = try ResourceEditorTestContext()
        let changed = context.result(
            title: "Someone else",
            updatedAt: Date(
                timeIntervalSince1970:
                    1_700_004_000
            )
        )
        let failure =
            GitLabSessionClientError.api(
                .transport
            )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                    .success(changed),
                ],
                updateResults: [.failure(failure)]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited"
        await model.save()

        await model.checkGitLab()

        #expect(
            model.failure
                == .conflict(
                    GitLabResourceEditConflict(
                        fields: [.title],
                        latest: changed.snapshot
                    )
                )
        )
        #expect(!model.canSave)
    }

    @Test("A failed ambiguous-delivery check remains blocked")
    @MainActor
    func preservesUnknownDeliveryAfterCheckFailure()
        async throws
    {
        let context = try ResourceEditorTestContext()
        let mutationFailure =
            GitLabSessionClientError.api(
                .server(statusCode: 503)
            )
        let checkFailure =
            GitLabSessionClientError.api(
                .connectivity(.timedOut)
            )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                    .failure(checkFailure),
                ],
                updateResults: [
                    .failure(mutationFailure),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited"
        await model.save()

        await model.checkGitLab()

        #expect(
            model.failure
                == .reconciliation(checkFailure)
        )
        #expect(!model.canSave)
    }

    @Test("Unknown delivery cannot send a second PUT before reconciliation")
    @MainActor
    func blocksResubmissionAfterUnknownDelivery()
        async throws
    {
        let context = try ResourceEditorTestContext()
        let failure =
            GitLabSessionClientError.api(
                .server(statusCode: 500)
            )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .failure(failure),
                    .success(
                        context.result(
                            title: "Edited"
                        )
                    ),
                ]
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited"

        await model.save()
        await model.save()

        #expect(await service.loadCount == 1)
        #expect(await service.updateCount == 1)
        #expect(
            model.failure
                == .mutation(
                    failure,
                    certainty:
                        .deliveryUnknown
                )
        )
    }

    @Test("A response with the wrong identity is treated as unknown delivery")
    @MainActor
    func rejectsMutationIdentityMismatch() async throws {
        let context = try ResourceEditorTestContext()
        let wrong = context.result(
            resourceID: 999,
            title: "Edited"
        )
        let service =
            RecordingResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [.success(wrong)]
            )
        var received:
            GitLabResourceEditResult?
        let model = context.makeModel(
            service: service,
            onSuccess: {
                received = $0
            }
        )
        await model.restoreDraft()
        model.title = "Edited"

        await model.save()

        #expect(received == nil)
        #expect(
            model.failure
                == .mutation(
                    .api(.invalidResponse),
                    certainty:
                        .deliveryUnknown
                )
        )
        #expect(!model.canSave)
    }

    @Test("Rapid duplicate saves perform one preflight and one PUT")
    @MainActor
    func suppressesDuplicateSave() async throws {
        let context = try ResourceEditorTestContext()
        let authoritative = context.result(
            title: "Edited"
        )
        let service =
            GatedResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(authoritative),
                ],
                gate: .latest
            )
        let model = context.makeModel(
            service: service
        )
        await model.restoreDraft()
        model.title = "Edited"

        let first = Task {
            await model.save()
        }
        await service.waitUntilLatestStarts()
        let second = Task {
            await model.save()
        }
        await Task.yield()
        await service.releaseLatest()
        await first.value
        await second.value

        #expect(await service.loadCount == 1)
        #expect(await service.updateCount == 1)
    }

    @Test("Canceling a late preflight cannot send a PUT")
    @MainActor
    func cancelsLatePreflight() async throws {
        let context = try ResourceEditorTestContext()
        let service =
            GatedResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(
                        context.result(
                            title: "Edited"
                        )
                    ),
                ],
                gate: .latest
            )
        let store =
            RecordingResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )
        await model.restoreDraft()
        model.title = "Edited"

        let save = Task {
            await model.save()
        }
        await service.waitUntilLatestStarts()
        model.cancelActiveOperation()
        await service.releaseLatest()
        await save.value

        #expect(await service.updateCount == 0)
        #expect(!model.didSucceed)
        #expect(await store.storedDraft != nil)
    }

    @Test("Canceling after PUT starts preserves an unknown-delivery recovery")
    @MainActor
    func cancelsLateMutationConservatively()
        async throws
    {
        let context = try ResourceEditorTestContext()
        let service =
            GatedResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(
                        context.result(
                            title: "Edited"
                        )
                    ),
                ],
                gate: .update
            )
        let store =
            RecordingResourceEditDraftStore()
        let model = context.makeModel(
            service: service,
            draftStore: store
        )
        await model.restoreDraft()
        model.title = "Edited"

        let save = Task {
            await model.save()
        }
        await service.waitUntilUpdateStarts()
        model.cancelActiveOperation()
        await service.releaseUpdate()
        await save.value

        #expect(
            model.failure
                == .mutation(
                    .api(.cancelled),
                    certainty:
                        .deliveryUnknown
                )
        )
        #expect(!model.canSave)
        #expect(await store.storedDraft != nil)
    }

    @Test("An account switch rejects a late mutation response")
    @MainActor
    func rejectsLateResponseAfterAccountSwitch()
        async throws
    {
        let context = try ResourceEditorTestContext()
        let authoritative = context.result(
            title: "Edited"
        )
        let service =
            GatedResourceEditingService(
                latestResults: [
                    .success(context.baselineResult),
                ],
                updateResults: [
                    .success(authoritative),
                ],
                gate: .update
            )
        let accountState =
            ResourceEditorAccountState()
        let store =
            RecordingResourceEditDraftStore()
        var received:
            GitLabResourceEditResult?
        let model = context.makeModel(
            service: service,
            draftStore: store,
            isAccountCurrent: {
                accountState.isCurrent
            },
            onSuccess: {
                received = $0
            }
        )
        await model.restoreDraft()
        model.title = "Edited"

        let save = Task {
            await model.save()
        }
        await service.waitUntilUpdateStarts()
        accountState.isCurrent = false
        await service.releaseUpdate()
        await save.value

        #expect(received == nil)
        #expect(!model.didSucceed)
        #expect(await store.storedDraft != nil)
    }
}

private struct ResourceEditorTestContext {
    let accountID: GitLabAccountID
    let baselineResult: GitLabResourceEditResult

    init(
        title: String = "Original",
        description: String = "Original body"
    ) throws {
        try self.init(
            baselineResult:
                .issue(
                    makeTestIssue(
                        id: 101,
                        iid: 7,
                        projectID: 42,
                        title: title,
                        description: description,
                        updatedAt: Date(
                            timeIntervalSince1970:
                                1_700_003_600
                        )
                    )
                )
        )
    }

    init(
        baselineResult:
            GitLabResourceEditResult
    ) throws {
        accountID = GitLabAccountID(
            host: try GitLabHost(
                "https://gitlab.example.com"
            ),
            userID: 7
        )
        self.baselineResult =
            baselineResult
    }

    var baseline: GitLabResourceEditSnapshot {
        baselineResult.snapshot
    }

    func snapshot(
        resourceID: Int = 101,
        title: String = "Original",
        description: String = "Original body",
        updatedAt: Date = Date(
            timeIntervalSince1970:
                1_700_003_600
        )
    ) -> GitLabResourceEditSnapshot {
        GitLabResourceEditSnapshot(
            target: baseline.target,
            resourceID: resourceID,
            title: title,
            description: description,
            updatedAt: updatedAt
        )
    }

    func result(
        resourceID: Int = 101,
        title: String? = nil,
        description: String? = nil,
        updatedAt: Date? = nil
    ) -> GitLabResourceEditResult {
        .issue(
            makeTestIssue(
                id: resourceID,
                iid: baseline.target
                    .resourceIID,
                projectID:
                    baseline.target.projectID,
                title: title ?? baseline.title,
                description:
                    description
                    ?? baseline.rawDescription,
                updatedAt:
                    updatedAt
                    ?? baseline.updatedAt
            )
        )
    }

    @MainActor
    func makeModel(
        apiAccess:
            GitLabAPIAccess = .readWrite,
        service:
            any GitLabResourceEditing =
                RecordingResourceEditingService(),
        draftStore:
            any GitLabResourceEditDraftStoring =
                InMemoryGitLabResourceEditDraftStore(),
        isAccountCurrent:
            @escaping @MainActor () -> Bool = {
                true
            },
        onSuccess:
            @escaping @MainActor (
                GitLabResourceEditResult
            ) -> Void = { _ in }
    ) -> GitLabResourceEditorModel {
        GitLabResourceEditorModel(
            accountID: accountID,
            baseline: baseline,
            apiAccess: apiAccess,
            service: service,
            draftStore: draftStore,
            isAccountCurrent:
                isAccountCurrent,
            onSuccess: onSuccess
        )
    }
}

private struct RecordedResourceEditUpdate:
    Equatable,
    Sendable
{
    let target: GitLabResourceEditTarget
    let changes: GitLabResourceEditChanges
}

private actor RecordingResourceEditingService:
    GitLabResourceEditing
{
    private var latestResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]
    private var updateResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]
    private let events:
        ResourceEditorEventRecorder?

    private(set) var loadedTargets:
        [GitLabResourceEditTarget] = []
    private(set) var updates:
        [RecordedResourceEditUpdate] = []

    init(
        latestResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ] = [],
        updateResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ] = [],
        events:
            ResourceEditorEventRecorder? = nil
    ) {
        self.latestResults = latestResults
        self.updateResults = updateResults
        self.events = events
    }

    var loadCount: Int {
        loadedTargets.count
    }

    var updateCount: Int {
        updates.count
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        loadedTargets.append(target)
        await events?.record("load-latest")
        guard !latestResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try result(
            latestResults.removeFirst()
        )
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        updates.append(
            RecordedResourceEditUpdate(
                target: target,
                changes: changes
            )
        )
        await events?.record("update")
        guard !updateResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try result(
            updateResults.removeFirst()
        )
    }

    private func result<Value>(
        _ result:
            Result<
                Value,
                GitLabSessionClientError
            >
    ) throws(GitLabSessionClientError) -> Value {
        switch result {
        case let .success(value):
            value
        case let .failure(error):
            throw error
        }
    }
}

private actor GatedResourceEditingService:
    GitLabResourceEditing
{
    enum Gate: Equatable {
        case latest
        case update
    }

    private var latestResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]
    private var updateResults:
        [
            Result<
                GitLabResourceEditResult,
                GitLabSessionClientError
            >
        ]
    private let gate: Gate
    private var latestStarted = false
    private var updateStarted = false
    private var latestStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var updateStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var latestContinuation:
        CheckedContinuation<Void, Never>?
    private var updateContinuation:
        CheckedContinuation<Void, Never>?

    private(set) var loadCount = 0
    private(set) var updateCount = 0

    init(
        latestResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ],
        updateResults:
            [
                Result<
                    GitLabResourceEditResult,
                    GitLabSessionClientError
                >
            ],
        gate: Gate
    ) {
        self.latestResults = latestResults
        self.updateResults = updateResults
        self.gate = gate
    }

    func loadLatest(
        _ target: GitLabResourceEditTarget
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        loadCount += 1
        if gate == .latest {
            latestStarted = true
            let waiters = latestStartWaiters
            latestStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation {
                latestContinuation = $0
            }
        }
        guard !latestResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try result(
            latestResults.removeFirst()
        )
    }

    func update(
        _ target: GitLabResourceEditTarget,
        changes: GitLabResourceEditChanges
    ) async throws(GitLabSessionClientError)
        -> GitLabResourceEditResult
    {
        updateCount += 1
        if gate == .update {
            updateStarted = true
            let waiters = updateStartWaiters
            updateStartWaiters.removeAll()
            waiters.forEach { $0.resume() }
            await withCheckedContinuation {
                updateContinuation = $0
            }
        }
        guard !updateResults.isEmpty else {
            throw .api(.invalidResponse)
        }
        return try result(
            updateResults.removeFirst()
        )
    }

    func waitUntilLatestStarts() async {
        guard !latestStarted else {
            return
        }
        await withCheckedContinuation {
            latestStartWaiters.append($0)
        }
    }

    func waitUntilUpdateStarts() async {
        guard !updateStarted else {
            return
        }
        await withCheckedContinuation {
            updateStartWaiters.append($0)
        }
    }

    func releaseLatest() {
        latestContinuation?.resume()
        latestContinuation = nil
    }

    func releaseUpdate() {
        updateContinuation?.resume()
        updateContinuation = nil
    }

    private func result<Value>(
        _ result:
            Result<
                Value,
                GitLabSessionClientError
            >
    ) throws(GitLabSessionClientError) -> Value {
        switch result {
        case let .success(value):
            value
        case let .failure(error):
            throw error
        }
    }
}

private actor RecordingResourceEditDraftStore:
    GitLabResourceEditDraftStoring
{
    private(set) var storedDraft:
        GitLabResourceEditDraft?
    private let failsStores: Bool
    private let events:
        ResourceEditorEventRecorder?

    init(
        draft: GitLabResourceEditDraft? = nil,
        failsStores: Bool = false,
        events:
            ResourceEditorEventRecorder? = nil
    ) {
        storedDraft = draft
        self.failsStores = failsStores
        self.events = events
    }

    func draft(
        for key: GitLabResourceEditDraftKey
    ) -> GitLabResourceEditDraft? {
        storedDraft
    }

    func store(
        _ draft: GitLabResourceEditDraft,
        for key: GitLabResourceEditDraftKey
    ) async throws(
        GitLabResourceEditDraftStoreError
    ) {
        guard !failsStores else {
            throw .storage
        }
        guard
            storedDraft.map({
                $0.revision < draft.revision
            }) ?? true
        else {
            return
        }
        storedDraft =
            draft.isDirty ? draft : nil
        await events?.record("store")
    }

    func remove(
        for key: GitLabResourceEditDraftKey
    ) async {
        storedDraft = nil
        await events?.record("remove")
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        storedDraft = nil
    }
}

private actor GatedResourceEditDraftStore:
    GitLabResourceEditDraftStoring
{
    private(set) var storedDraft:
        GitLabResourceEditDraft?
    private var readStarted = false
    private var startWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var readContinuation:
        CheckedContinuation<Void, Never>?

    init(draft: GitLabResourceEditDraft) {
        storedDraft = draft
    }

    func draft(
        for key: GitLabResourceEditDraftKey
    ) async -> GitLabResourceEditDraft? {
        readStarted = true
        let waiters = startWaiters
        startWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation {
            readContinuation = $0
        }
        return storedDraft
    }

    func store(
        _ draft: GitLabResourceEditDraft,
        for key: GitLabResourceEditDraftKey
    ) {
        guard
            storedDraft.map({
                $0.revision < draft.revision
            }) ?? true
        else {
            return
        }
        storedDraft =
            draft.isDirty ? draft : nil
    }

    func remove(
        for key: GitLabResourceEditDraftKey
    ) {
        storedDraft = nil
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        storedDraft = nil
    }

    func waitUntilReadStarts() async {
        guard !readStarted else {
            return
        }
        await withCheckedContinuation {
            startWaiters.append($0)
        }
    }

    func releaseRead() {
        readContinuation?.resume()
        readContinuation = nil
    }
}

@MainActor
private final class ResourceEditorEventRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        values.append(value)
    }
}

@MainActor
private final class ResourceEditorAccountState {
    var isCurrent = true
}
