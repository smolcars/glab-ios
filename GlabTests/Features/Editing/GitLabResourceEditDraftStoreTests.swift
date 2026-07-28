import Foundation
import Testing
@testable import Glab

@Suite("GitLab resource edit draft store")
struct GitLabResourceEditDraftStoreTests {
    @Test("Separates every account and resource identity component")
    func separatesDraftKeys() throws {
        let firstAccount = try account(
            host: "https://gitlab.example.com",
            userID: 7
        )
        let issue = issueTarget(
            projectID: 42,
            issueIID: 3
        )
        let keys = [
            GitLabResourceEditDraftKey(
                accountID: firstAccount,
                target: issue
            ),
            GitLabResourceEditDraftKey(
                accountID: try account(
                    host:
                        "https://other.example.com",
                    userID: 7
                ),
                target: issue
            ),
            GitLabResourceEditDraftKey(
                accountID: try account(
                    host:
                        "https://gitlab.example.com",
                    userID: 8
                ),
                target: issue
            ),
            GitLabResourceEditDraftKey(
                accountID: firstAccount,
                target: issueTarget(
                    projectID: 43,
                    issueIID: 3
                )
            ),
            GitLabResourceEditDraftKey(
                accountID: firstAccount,
                target: issueTarget(
                    projectID: 42,
                    issueIID: 4
                )
            ),
            GitLabResourceEditDraftKey(
                accountID: firstAccount,
                target: mergeRequestTarget(
                    projectID: 42,
                    mergeRequestIID: 3
                )
            ),
        ]

        #expect(Set(keys).count == keys.count)
    }

    @Test("Persists both target kinds without changing identity")
    func targetCodingRoundTrips() throws {
        let encoder =
            PropertyListEncoder()
        let decoder =
            PropertyListDecoder()

        for target in [
            issueTarget(
                projectID: 42,
                issueIID: 7
            ),
            mergeRequestTarget(
                projectID: 43,
                mergeRequestIID: 8
            ),
        ] {
            let data = try encoder.encode(
                target
            )
            let decoded = try decoder.decode(
                GitLabResourceEditTarget.self,
                from: data
            )

            #expect(decoded == target)
        }
    }

    @Test("Edit identity and draft descriptions redact private content")
    func redactsDescriptions() throws {
        let privateTitle =
            "Private acquisition title"
        let privateMarkdown =
            "# Confidential\n\nsecret-token"
        let target = issueTarget()
        let snapshot =
            GitLabResourceEditSnapshot(
                target: target,
                title: privateTitle,
                description: privateMarkdown,
                updatedAt:
                    Date(
                        timeIntervalSince1970:
                            1_700_000_000
                    )
            )
        let draft = GitLabResourceEditDraft(
            baseline: snapshot,
            title: privateTitle,
            description: "",
            revision: 1
        )
        let key = GitLabResourceEditDraftKey(
            accountID: try account(),
            target: target
        )

        for value in [
            String(describing: target),
            String(reflecting: target),
            String(describing: snapshot),
            String(reflecting: snapshot),
            String(describing: draft),
            String(reflecting: draft),
            String(describing: key),
            String(reflecting: key),
        ] {
            #expect(
                !value.contains(privateTitle)
            )
            #expect(
                !value.contains(privateMarkdown)
            )
            #expect(
                !value.contains(
                    "gitlab.example.com"
                )
            )
        }

        let error =
            GitLabResourceEditDraftStoreError
                .storage
        #expect(
            error.debugDescription
                == error.description
        )
        #expect(
            !error.description
                .contains(privateMarkdown)
        )
    }

    @Test("In-memory storage keeps only the newest revision")
    func keepsNewestRevision() async throws {
        let store =
            InMemoryGitLabResourceEditDraftStore()
        let key = try draftKey()
        let newest = draft(
            title: "Newest",
            description: "Newest body",
            revision: 2
        )

        try await store.store(
            newest,
            for: key
        )
        try await store.store(
            draft(
                title: "Older",
                description: "Older body",
                revision: 1
            ),
            for: key
        )

        #expect(
            await store.draft(for: key)
                == newest
        )
    }

    @Test("Returning exactly to the baseline removes a draft")
    func cleanDraftRemovesStoredDraft() async throws {
        let store =
            InMemoryGitLabResourceEditDraftStore()
        let key = try draftKey()
        let dirty = draft(
            description: "",
            revision: 1
        )

        try await store.store(
            dirty,
            for: key
        )
        try await store.store(
            GitLabResourceEditDraft(
                baseline: dirty.baseline,
                title: dirty.baseline.title,
                description:
                    dirty.baseline
                    .rawDescription,
                revision: 2
            ),
            for: key
        )

        #expect(
            await store.draft(for: key)
                == nil
        )
    }

    @Test("An intentionally empty description round trips exactly")
    func emptyDescriptionRoundTrips() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            let exact = draft(
                title: "  Preserve spacing  ",
                description: "",
                revision: 4
            )

            try await store.store(
                exact,
                for: key
            )
            let restored =
                FileGitLabResourceEditDraftStore(
                    rootDirectory:
                        rootDirectory
                )

            #expect(
                await restored.draft(for: key)
                    == exact
            )
        }
    }

    @Test("File storage preserves raw Unicode Markdown and newest revision")
    func fileRoundTrip() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            let newest = draft(
                title: "  Exact 👩🏽‍💻 title  ",
                description:
                    "\r\n# Draft 👩🏽‍💻\r\n"
                    + "\r\n- [ ] keep  \r\n",
                revision: 9
            )

            try await store.store(
                newest,
                for: key
            )
            try await store.store(
                draft(
                    title: "Stale",
                    description: "Stale",
                    revision: 8
                ),
                for: key
            )
            let restored =
                FileGitLabResourceEditDraftStore(
                    rootDirectory:
                        rootDirectory
                )

            #expect(
                await restored.draft(for: key)
                    == newest
            )
        }
    }

    @Test("Removes one account without affecting another")
    func removesAccountDrafts() async throws {
        try await withFileStore {
            store,
            _ in
            let target = issueTarget()
            let firstKey =
                GitLabResourceEditDraftKey(
                    accountID: try account(
                        userID: 7
                    ),
                    target: target
                )
            let secondKey =
                GitLabResourceEditDraftKey(
                    accountID: try account(
                        userID: 8
                    ),
                    target: target
                )
            let firstDraft = draft(
                title: "First account",
                revision: 1
            )
            let secondDraft = draft(
                title: "Second account",
                revision: 1
            )
            try await store.store(
                firstDraft,
                for: firstKey
            )
            try await store.store(
                secondDraft,
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
                ) == secondDraft
            )
        }
    }

    @Test("File paths hash every private identity component")
    func hashesFilePaths() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            let privateTitle =
                "Confidential roadmap"
            let privateMarkdown =
                "# Hidden launch plan"

            try await store.store(
                draft(
                    title: privateTitle,
                    description: privateMarkdown,
                    revision: 1
                ),
                for: key
            )

            let paths = recursivePaths(
                below: rootDirectory
            )
            #expect(!paths.isEmpty)
            for path in paths {
                #expect(
                    !path.contains(
                        "gitlab.example.com"
                    )
                )
                #expect(
                    !path.contains(privateTitle)
                )
                #expect(
                    !path.contains(
                        privateMarkdown
                    )
                )
            }
            let files = recursiveFiles(
                below: rootDirectory
            )
            #expect(files.count == 1)
            #expect(
                files[0]
                    .lastPathComponent
                    .wholeMatch(
                        of:
                            /[0-9a-f]{64}\.draft/
                    ) != nil
            )
        }
    }

    @Test("Atomic replacement leaves one complete newest record")
    func replacesAtomically() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                draft(
                    title: "First",
                    revision: 1
                ),
                for: key
            )
            let newest = draft(
                title: "Second",
                description:
                    "# Complete replacement",
                revision: 2
            )

            try await store.store(
                newest,
                for: key
            )

            #expect(
                recursiveFiles(
                    below: rootDirectory
                ).count == 1
            )
            #expect(
                await store.draft(for: key)
                    == newest
            )
        }
    }

    @Test("Discards corrupt and unsupported records")
    func discardsInvalidRecords() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                draft(revision: 1),
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
                draft(revision: 2),
                for: key
            )
            fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )
            var propertyList = try #require(
                try PropertyListSerialization
                    .propertyList(
                        from: Data(
                            contentsOf: fileURL
                        ),
                        format: nil
                    ) as? [String: Any]
            )
            propertyList["formatVersion"] = 999
            let unsupported =
                try PropertyListSerialization
                    .data(
                        fromPropertyList:
                            propertyList,
                        format: .binary,
                        options: 0
                    )
            try unsupported.write(
                to: fileURL
            )

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

    @Test("Discards a record copied under a different account key")
    func discardsWrongKeyRecord() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let sourceKey = try draftKey()
            try await store.store(
                draft(revision: 1),
                for: sourceKey
            )
            let sourceURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )
            let sourceData = try Data(
                contentsOf: sourceURL
            )
            let destinationKey =
                GitLabResourceEditDraftKey(
                    accountID: try account(
                        userID: 8
                    ),
                    target: sourceKey.target
                )
            try await store.store(
                draft(
                    baselineTarget:
                        destinationKey.target,
                    revision: 1
                ),
                for: destinationKey
            )
            let destinationURL =
                try #require(
                    recursiveFiles(
                        below: rootDirectory
                    )
                    .first {
                        $0 != sourceURL
                    }
                )
            try sourceData.write(
                to: destinationURL
            )

            #expect(
                await store.draft(
                    for: destinationKey
                ) == nil
            )
            #expect(
                !FileManager.default
                    .fileExists(
                        atPath:
                            destinationURL.path
                    )
            )
            #expect(
                await store.draft(
                    for: sourceKey
                ) != nil
            )
        }
    }

    @Test("Rejects oversized records before loading their data")
    func discardsOversizedRecord() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                draft(revision: 1),
                for: key
            )
            let fileURL = try #require(
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
                        FileGitLabResourceEditDraftStore
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

    @Test("Treats an unreadable record as a miss and removes it")
    func discardsUnreadableRecord() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                draft(revision: 1),
                for: key
            )
            let fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )
            try FileManager.default
                .removeItem(at: fileURL)
            try FileManager.default
                .createDirectory(
                    at: fileURL,
                    withIntermediateDirectories:
                        false
                )

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

    @Test("Maps file-system failures to one redacted storage error")
    func mapsStorageFailures() async throws {
        let temporaryDirectory =
            FileManager.default
            .temporaryDirectory
            .appending(
                path: UUID().uuidString,
                directoryHint: .isDirectory
            )
        try FileManager.default
            .createDirectory(
                at: temporaryDirectory,
                withIntermediateDirectories:
                    true
            )
        defer {
            try? FileManager.default
                .removeItem(
                    at: temporaryDirectory
                )
        }
        let blockingFile =
            temporaryDirectory.appending(
                path: "not-a-directory",
                directoryHint: .notDirectory
            )
        try Data().write(to: blockingFile)
        let store =
            FileGitLabResourceEditDraftStore(
                rootDirectory: blockingFile
            )

        await #expect(
            throws:
                GitLabResourceEditDraftStoreError
                    .storage
        ) {
            try await store.store(
                draft(revision: 1),
                for: draftKey()
            )
        }
    }

    @Test("Uses complete protection when the filesystem exposes it")
    func usesCompleteProtection() async throws {
        try await withFileStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                draft(revision: 1),
                for: key
            )
            let fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
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
            let fileProtection =
                fileAttributes[.protectionKey]
                    as? FileProtectionType
            let directoryProtection =
                directoryAttributes[
                    .protectionKey
                ] as? FileProtectionType

            #if targetEnvironment(simulator)
                #expect(fileProtection == nil)
                #expect(directoryProtection == nil)
            #else
                #expect(
                    fileProtection == .complete
                )
                #expect(
                    directoryProtection == .complete
                )
            #endif
        }
    }
}

private extension GitLabResourceEditDraftStoreTests {
    func account(
        host: String =
            "https://gitlab.example.com",
        userID: Int = 7
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(host),
            userID: userID
        )
    }

    func issueTarget(
        projectID: Int = 42,
        issueIID: Int = 3
    ) -> GitLabResourceEditTarget {
        .issue(
            GitLabIssueRoute(
                projectID: projectID,
                issueIID: issueIID
            )
        )
    }

    func mergeRequestTarget(
        projectID: Int = 42,
        mergeRequestIID: Int = 3
    ) -> GitLabResourceEditTarget {
        .mergeRequest(
            GitLabMergeRequestRoute(
                projectID: projectID,
                mergeRequestIID:
                    mergeRequestIID
            )
        )
    }

    func draftKey() throws
        -> GitLabResourceEditDraftKey
    {
        GitLabResourceEditDraftKey(
            accountID: try account(),
            target: issueTarget()
        )
    }

    func draft(
        baselineTarget:
            GitLabResourceEditTarget? = nil,
        title: String = "Changed title",
        description: String =
            "# Baseline\n\nChanged",
        revision: Int
    ) -> GitLabResourceEditDraft {
        let target =
            baselineTarget ?? issueTarget()
        return GitLabResourceEditDraft(
            baseline:
                GitLabResourceEditSnapshot(
                    target: target,
                    title: "Baseline title",
                    description:
                        "# Baseline\n\nOriginal",
                    updatedAt:
                        Date(
                            timeIntervalSince1970:
                                1_700_000_000
                        )
                ),
            title: title,
            description: description,
            revision: revision
        )
    }

    func withFileStore(
        _ operation: (
            FileGitLabResourceEditDraftStore,
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
            FileGitLabResourceEditDraftStore(
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
