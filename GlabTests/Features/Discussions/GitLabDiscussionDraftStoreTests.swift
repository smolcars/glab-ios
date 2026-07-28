import Foundation
import Testing
@testable import Glab

@Suite("GitLab discussion draft store")
struct GitLabDiscussionDraftStoreTests {
    @Test("Separates accounts, resources, and reply targets")
    func separatesDraftKeys() throws {
        let firstAccount = try account(
            host: "https://gitlab.example.com",
            userID: 7
        )
        let secondAccount = try account(
            host: "https://gitlab.example.com",
            userID: 8
        )
        let issue: GitLabDiscussionResource =
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 3
                )
            )
        let mergeRequest:
            GitLabDiscussionResource =
                .mergeRequest(
                    GitLabMergeRequestRoute(
                        projectID: 42,
                        mergeRequestIID: 3
                    )
                )
        let issueComment =
            GitLabDiscussionDraftKey(
                accountID: firstAccount,
                resource: issue
            )
        let issueReply =
            GitLabDiscussionDraftKey(
                accountID: firstAccount,
                resource: issue,
                target: .reply(
                    discussionID: "thread-a"
                )
            )
        let otherReply =
            GitLabDiscussionDraftKey(
                accountID: firstAccount,
                resource: issue,
                target: .reply(
                    discussionID: "thread-b"
                )
            )

        #expect(
            issueComment
                != GitLabDiscussionDraftKey(
                    accountID: secondAccount,
                    resource: issue
                )
        )
        #expect(
            issueComment
                != GitLabDiscussionDraftKey(
                    accountID: firstAccount,
                    resource: mergeRequest
                )
        )
        #expect(issueComment != issueReply)
        #expect(issueReply != otherReply)
        #expect(
            !String(describing: issueReply)
                .contains("gitlab.example.com")
        )
        #expect(
            !String(reflecting: issueReply)
                .contains("thread-a")
        )
        let privateBody =
            "Private draft contents"
        let draft = GitLabDiscussionDraft(
            body: privateBody,
            revision: 1
        )
        #expect(
            !String(describing: draft)
                .contains(privateBody)
        )
        #expect(
            !String(reflecting: draft)
                .contains(privateBody)
        )
    }

    @Test("In-memory storage keeps only the newest revision")
    func keepsNewestRevision() async throws {
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let key = try draftKey()
        let newest = GitLabDiscussionDraft(
            body: "Newest",
            revision: 2
        )

        try await store.store(
            newest,
            for: key
        )
        try await store.store(
            GitLabDiscussionDraft(
                body: "Older",
                revision: 1
            ),
            for: key
        )

        #expect(
            await store.draft(for: key)
                == newest
        )
    }

    @Test("File storage round trips and keeps only the newest revision")
    func fileRoundTrip() async throws {
        try await withStore {
            store,
            rootDirectory in
            let key = try draftKey()
            let newest =
                GitLabDiscussionDraft(
                    body: "A **new** draft",
                    revision: 4
                )

            try await store.store(
                newest,
                for: key
            )
            try await store.store(
                GitLabDiscussionDraft(
                    body: "Stale",
                    revision: 3
                ),
                for: key
            )
            let restored =
                FileGitLabDiscussionDraftStore(
                    rootDirectory: rootDirectory
                )

            #expect(
                await restored.draft(for: key)
                    == newest
            )
        }
    }

    @Test("Empty bodies remove an existing draft")
    func emptyBodyRemovesDraft() async throws {
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let key = try draftKey()
        try await store.store(
            GitLabDiscussionDraft(
                body: "Temporary",
                revision: 1
            ),
            for: key
        )

        try await store.store(
            GitLabDiscussionDraft(
                body: "",
                revision: 2
            ),
            for: key
        )

        #expect(
            await store.draft(for: key)
                == nil
        )
    }

    @Test("Removes one draft without removing sibling drafts")
    func removesExactDraft() async throws {
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let comment = try draftKey()
        let reply = GitLabDiscussionDraftKey(
            accountID: comment.accountID,
            resource: comment.resource,
            target: .reply(
                discussionID: "thread-a"
            )
        )
        try await store.store(
            GitLabDiscussionDraft(
                body: "Comment",
                revision: 1
            ),
            for: comment
        )
        try await store.store(
            GitLabDiscussionDraft(
                body: "Reply",
                revision: 1
            ),
            for: reply
        )

        await store.remove(for: comment)

        #expect(
            await store.draft(for: comment)
                == nil
        )
        #expect(
            await store.draft(for: reply)?
                .body == "Reply"
        )
    }

    @Test("Removes every draft for only the selected account")
    func removesAccountDrafts() async throws {
        let store =
            InMemoryGitLabDiscussionDraftStore()
        let firstAccount = try account(
            host: "https://gitlab.example.com",
            userID: 7
        )
        let secondAccount = try account(
            host: "https://gitlab.example.com",
            userID: 8
        )
        let resource: GitLabDiscussionResource =
            .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 3
                )
            )
        let first = GitLabDiscussionDraftKey(
            accountID: firstAccount,
            resource: resource
        )
        let second = GitLabDiscussionDraftKey(
            accountID: secondAccount,
            resource: resource
        )
        let draft = GitLabDiscussionDraft(
            body: "Preserve me",
            revision: 1
        )
        try await store.store(draft, for: first)
        try await store.store(draft, for: second)

        await store.removeAll(
            for: firstAccount
        )

        #expect(
            await store.draft(for: first)
                == nil
        )
        #expect(
            await store.draft(for: second)
                == draft
        )
    }

    @Test("File paths hash private draft identity")
    func hashesFilePaths() async throws {
        try await withStore {
            store,
            rootDirectory in
            let key = try draftKey(
                target: .reply(
                    discussionID:
                        "private-thread-name"
                )
            )
            let privateBody =
                "Confidential release detail"
            try await store.store(
                GitLabDiscussionDraft(
                    body: privateBody,
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
                    !path.contains(
                        "private-thread-name"
                    )
                )
                #expect(
                    !path.contains(privateBody)
                )
            }
        }
    }

    @Test("Discards corrupt and unsupported records")
    func discardsInvalidRecords() async throws {
        try await withStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                GitLabDiscussionDraft(
                    body: "Valid",
                    revision: 1
                ),
                for: key
            )
            let fileURL = try #require(
                recursiveFiles(
                    below: rootDirectory
                ).first
            )

            try Data("not a plist".utf8)
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
                GitLabDiscussionDraft(
                    body: "Valid again",
                    revision: 2
                ),
                for: key
            )
            let replacementURL =
                try #require(
                    recursiveFiles(
                        below: rootDirectory
                    ).first
                )
            let unsupported =
                try PropertyListSerialization
                    .data(
                        fromPropertyList: [
                            "formatVersion": 999,
                            "draft": [
                                "body": "Unsupported",
                                "revision": 3,
                            ],
                        ],
                        format: .binary,
                        options: 0
                    )
            try unsupported.write(
                to: replacementURL
            )

            #expect(
                await store.draft(for: key)
                    == nil
            )
            #expect(
                !FileManager.default
                    .fileExists(
                        atPath:
                            replacementURL.path
                    )
            )
        }
    }

    @Test("Uses complete file protection when the filesystem exposes it")
    func usesCompleteProtection() async throws {
        try await withStore {
            store,
            rootDirectory in
            let key = try draftKey()
            try await store.store(
                GitLabDiscussionDraft(
                    body: "Protected",
                    revision: 1
                ),
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
            let directoryURL =
                fileURL.deletingLastPathComponent()
            let directoryAttributes =
                try FileManager.default
                    .attributesOfItem(
                        atPath:
                            directoryURL.path
                    )

            let fileProtection =
                fileAttributes[.protectionKey]
                    as? FileProtectionType
            let directoryProtection =
                directoryAttributes[
                    .protectionKey
                ] as? FileProtectionType

            #if targetEnvironment(simulator)
                // CoreSimulator accepts file-protection
                // options but does not expose their
                // attributes through FileManager.
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

    private func withStore(
        _ operation: (
            FileGitLabDiscussionDraftStore,
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
            FileGitLabDiscussionDraftStore(
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

    private func account(
        host: String,
        userID: Int
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(host),
            userID: userID
        )
    }

    private func draftKey(
        target:
            GitLabDiscussionComposerTarget =
                .newDiscussion
    ) throws -> GitLabDiscussionDraftKey {
        GitLabDiscussionDraftKey(
            accountID: try account(
                host:
                    "https://gitlab.example.com",
                userID: 7
            ),
            resource: .issue(
                GitLabIssueRoute(
                    projectID: 42,
                    issueIID: 3
                )
            ),
            target: target
        )
    }

    private func recursivePaths(
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

    private func recursiveFiles(
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
