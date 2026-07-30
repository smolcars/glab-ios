import Foundation
import Testing
@testable import Glab

@Suite("GitLab issue creation draft store")
struct GitLabIssueCreationDraftStoreTests {
    @Test("Draft keys isolate accounts and redact their identity")
    func keysIsolateAccountsAndRedactIdentity() throws {
        let first = GitLabIssueCreationDraftKey(
            accountID: try account()
        )
        let second = GitLabIssueCreationDraftKey(
            accountID: try account(userID: 8)
        )

        #expect(first != second)
        #expect(
            !first.description.contains(
                "gitlab.example.com"
            )
        )
        #expect(
            first.debugDescription
                == first.description
        )
    }

    @Test("Draft keys isolate account and project composers")
    func keysIsolateComposerScopes() throws {
        let accountID = try account()
        let accountKey =
            GitLabIssueCreationDraftKey(
                accountID: accountID
            )
        let firstProjectKey =
            GitLabIssueCreationDraftKey(
                accountID: accountID,
                scope: .project(42)
            )
        let secondProjectKey =
            GitLabIssueCreationDraftKey(
                accountID: accountID,
                scope: .project(43)
            )

        #expect(accountKey != firstProjectKey)
        #expect(
            firstProjectKey
                != secondProjectKey
        )
        #expect(
            !firstProjectKey.description
                .contains("42")
        )
    }

    @Test("Draft descriptions redact private form content")
    func draftDescriptionsRedactContent() {
        let privateTitle =
            "Private customer outage"
        let privateDescription =
            "# Secret\n\ninternal-token"
        let draft = creationDraft(
            title: privateTitle,
            description: privateDescription,
            revision: 1
        )

        for value in [
            String(describing: draft),
            String(reflecting: draft),
            String(
                describing:
                    draft.selectedProject
            ),
            String(
                reflecting:
                    draft.selectedProject
            ),
        ] {
            #expect(
                !value.contains(privateTitle)
            )
            #expect(
                !value.contains(
                    privateDescription
                )
            )
            #expect(
                !value.contains(
                    "private-group"
                )
            )
        }
    }

    @Test("In-memory storage keeps only the newest valid revision")
    func inMemoryKeepsNewestRevision()
        async throws
    {
        let store =
            InMemoryGitLabIssueCreationDraftStore()
        let key = try draftKey()
        let newest = creationDraft(
            title: "Newest",
            revision: 3
        )

        try await store.store(
            newest,
            for: key
        )
        try await store.store(
            creationDraft(
                title: "Stale",
                revision: 2
            ),
            for: key
        )

        #expect(
            await store.draft(for: key)
                == newest
        )
    }

    @Test("A pristine draft removes stored creation state")
    func pristineDraftRemovesState()
        async throws
    {
        let store =
            InMemoryGitLabIssueCreationDraftStore()
        let key = try draftKey()
        try await store.store(
            creationDraft(revision: 1),
            for: key
        )

        try await store.store(
            GitLabIssueCreationDraft(
                revision: 2
            ),
            for: key
        )

        #expect(
            await store.draft(for: key)
                == nil
        )
    }

    @Test("Removing an account clears every project-scoped draft")
    func removesAllComposerScopes()
        async throws
    {
        let store =
            InMemoryGitLabIssueCreationDraftStore()
        let accountID = try account()
        let otherAccountID =
            try account(userID: 8)
        let keys = [
            GitLabIssueCreationDraftKey(
                accountID: accountID
            ),
            GitLabIssueCreationDraftKey(
                accountID: accountID,
                scope: .project(42)
            ),
        ]
        let preservedKey =
            GitLabIssueCreationDraftKey(
                accountID: otherAccountID,
                scope: .project(42)
            )
        for (revision, key) in
            keys.enumerated()
        {
            try await store.store(
                creationDraft(
                    revision: revision + 1
                ),
                for: key
            )
        }
        try await store.store(
            creationDraft(revision: 1),
            for: preservedKey
        )

        await store.removeAll(
            for: accountID
        )

        for key in keys {
            #expect(
                await store.draft(for: key)
                    == nil
            )
        }
        #expect(
            await store.draft(
                for: preservedKey
            ) != nil
        )
    }

    @Test("Storage rejects malformed restored state")
    func rejectsMalformedState() async throws {
        let store =
            InMemoryGitLabIssueCreationDraftStore()
        let key = try draftKey()
        let malformed = GitLabIssueCreationDraft(
            selectedProject:
                GitLabIssueCreationProjectSelection(
                    id: 0,
                    name: "Invalid",
                    nameWithNamespace:
                        "Private Group / Invalid",
                    pathWithNamespace:
                        "private-group/invalid"
                ),
            title: "Invalid draft",
            assigneeIDs: [-1],
            revision: 1,
            pendingSubmissionFingerprint:
                "not-a-digest"
        )

        await #expect(
            throws:
                GitLabIssueCreationDraftStoreError
                    .storage
        ) {
            try await store.store(
                malformed,
                for: key
            )
        }
    }

    @Test("Protected file storage round trips exact creation state")
    func fileRoundTrip() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            let exact = creationDraft(
                title: "  Exact 👩🏽‍💻 title  ",
                description:
                    "\r\n# Draft 👩🏽‍💻\r\n"
                    + "\r\n- [ ] keep  \r\n",
                revision: 9,
                pendingSubmissionFingerprint:
                    String(
                        repeating: "a",
                        count: 64
                    )
            )

            try await store.store(
                exact,
                for: key
            )
            let restored =
                FileGitLabIssueCreationDraftStore(
                    rootDirectory:
                        rootDirectory
                )

            #expect(
                await restored.draft(for: key)
                    == exact
            )
        }
    }

    @Test("Removing one account preserves another account draft")
    func removesOnlyOneAccount() async throws {
        try await withFileStore {
            store,
            _ in
            let firstKey = try draftKey()
            let secondKey =
                GitLabIssueCreationDraftKey(
                    accountID:
                        try account(userID: 8)
                )
            let first = creationDraft(
                title: "First",
                revision: 1
            )
            let second = creationDraft(
                title: "Second",
                revision: 1
            )
            try await store.store(
                first,
                for: firstKey
            )
            try await store.store(
                second,
                for: secondKey
            )

            await store.removeAll(
                for: firstKey.accountID
            )

            #expect(
                await store.draft(
                    for: firstKey
                ) == nil
            )
            #expect(
                await store.draft(
                    for: secondKey
                ) == second
            )
        }
    }

    @Test("Invalid and oversized records are discarded")
    func discardsInvalidRecords() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                creationDraft(revision: 1),
                for: key
            )
            var fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )

            try Data("private-corrupt-data".utf8)
                .write(to: fileURL)
            #expect(
                await store.draft(for: key)
                    == nil
            )
            #expect(
                !FileManager.default
                    .fileExists(
                        atPath: fileURL.path
                    )
            )

            try await store.store(
                creationDraft(revision: 2),
                for: key
            )
            fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )
            let file = try FileHandle(
                forWritingTo: fileURL
            )
            try file.truncate(
                atOffset:
                    UInt64(
                        FileGitLabIssueCreationDraftStore
                            .maximumStoredRecordBytes
                            + 1
                    )
            )
            try file.close()

            #expect(
                await store.draft(for: key)
                    == nil
            )
            #expect(
                !FileManager.default
                    .fileExists(
                        atPath: fileURL.path
                    )
            )
        }
    }

    @Test("Protected paths hash private account and project data")
    func protectsFileAndPathMetadata()
        async throws
    {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                creationDraft(
                    title:
                        "Confidential roadmap",
                    description:
                        "# Hidden launch plan",
                    revision: 1
                ),
                for: key
            )
            let fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )

            for path in recursivePaths(
                below: rootDirectory
            ) {
                #expect(
                    !path.contains(
                        "gitlab.example.com"
                    )
                )
                #expect(
                    !path.contains(
                        "private-group"
                    )
                )
                #expect(
                    !path.contains(
                        "Confidential roadmap"
                    )
                )
            }
            #expect(
                fileURL.lastPathComponent
                    .wholeMatch(
                        of:
                            /[0-9a-f]{64}\.draft/
                    ) != nil
            )

            let fileAttributes =
                try FileManager.default
                    .attributesOfItem(
                        atPath: fileURL.path
                    )
            let directoryAttributes =
                try FileManager.default
                    .attributesOfItem(
                        atPath:
                            fileURL
                            .deletingLastPathComponent()
                            .path
                    )
            #if targetEnvironment(simulator)
                #expect(
                    fileAttributes[
                        .protectionKey
                    ] == nil
                )
                #expect(
                    directoryAttributes[
                        .protectionKey
                    ] == nil
                )
            #else
                #expect(
                    fileAttributes[
                        .protectionKey
                    ] as? FileProtectionType
                        == .complete
                )
                #expect(
                    directoryAttributes[
                        .protectionKey
                    ] as? FileProtectionType
                        == .complete
                )
            #endif
        }
    }
}

private extension GitLabIssueCreationDraftStoreTests {
    func account(
        userID: Int = 7
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host:
                try GitLabHost(
                    "https://gitlab.example.com"
                ),
            userID: userID
        )
    }

    func draftKey() throws
        -> GitLabIssueCreationDraftKey
    {
        GitLabIssueCreationDraftKey(
            accountID: try account()
        )
    }

    func creationDraft(
        title: String = "Draft issue",
        description: String = "# Details",
        revision: Int,
        pendingSubmissionFingerprint:
            String? = nil
    ) -> GitLabIssueCreationDraft {
        GitLabIssueCreationDraft(
            selectedProject:
                GitLabIssueCreationProjectSelection(
                    id: 42,
                    name: "Private Project",
                    nameWithNamespace:
                        "Private Group / Private Project",
                    pathWithNamespace:
                        "private-group/private-project"
                ),
            title: title,
            description: description,
            labelNames: [
                "type::feature",
                "team::mobile",
            ],
            assigneeIDs: [7, 8],
            confidential: true,
            dueDate:
                GitLabIssueDueDate(
                    year: 2026,
                    month: 8,
                    day: 12
                ),
            status:
                GitLabIssueWorkItemStatus(
                    id:
                        "gid://gitlab/WorkItems::Statuses::SystemDefined::Status/7",
                    name: "In progress",
                    description: nil,
                    iconName: nil,
                    color: nil,
                    position: 2,
                    category: .inProgress
                ),
            milestone:
                GitLabIssueMilestone(
                    id: 19,
                    iid: 3,
                    title: "1.0",
                    state: "active",
                    startDate:
                        "2026-07-01",
                    dueDate:
                        "2026-08-01"
                ),
            iteration:
                GitLabIssueIteration(
                    id: 23,
                    iid: 5,
                    title: "Sprint 5",
                    state: 1,
                    startDate:
                        "2026-07-27",
                    dueDate:
                        "2026-08-07"
                ),
            revision: revision,
            pendingSubmissionFingerprint:
                pendingSubmissionFingerprint
        )
    }

    func withFileStore(
        _ operation: (
            FileGitLabIssueCreationDraftStore,
            URL
        ) async throws -> Void
    ) async throws {
        let rootDirectory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path: UUID().uuidString,
                directoryHint: .isDirectory
            )
        let store =
            FileGitLabIssueCreationDraftStore(
                rootDirectory: rootDirectory
            )
        defer {
            try? FileManager.default
                .removeItem(at: rootDirectory)
        }

        try await operation(
            store,
            rootDirectory
        )
    }

    func recursivePaths(
        below rootDirectory: URL
    ) -> [String] {
        guard
            let enumerator =
                FileManager.default
                .enumerator(
                    at: rootDirectory,
                    includingPropertiesForKeys:
                        nil
                )
        else {
            return []
        }

        return enumerator.compactMap {
            ($0 as? URL)?.path
        }
    }

    func recursiveFiles(
        below rootDirectory: URL
    ) -> [URL] {
        guard
            let enumerator =
                FileManager.default
                .enumerator(
                    at: rootDirectory,
                    includingPropertiesForKeys: [
                        .isRegularFileKey,
                    ]
                )
        else {
            return []
        }

        return enumerator.compactMap {
            guard
                let url = $0 as? URL,
                let values =
                    try? url.resourceValues(
                        forKeys: [
                            .isRegularFileKey,
                        ]
                    ),
                values.isRegularFile == true
            else {
                return nil
            }
            return url
        }
    }
}
