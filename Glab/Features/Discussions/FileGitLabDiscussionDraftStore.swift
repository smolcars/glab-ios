import CryptoKit
import Foundation

actor FileGitLabDiscussionDraftStore:
    GitLabDiscussionDraftStoring
{
    private struct StoredRecord:
        Codable,
        Sendable
    {
        let formatVersion: Int
        let draft: GitLabDiscussionDraft
    }

    private static let formatVersion = 1
    private static let directoryName =
        "GlabGitLabDiscussionDrafts"

    private let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL =
            URL.applicationSupportDirectory
            .appending(
                path:
                    FileGitLabDiscussionDraftStore
                    .directoryName,
                directoryHint: .isDirectory
            ),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func draft(
        for key: GitLabDiscussionDraftKey
    ) -> GitLabDiscussionDraft? {
        let fileURL = draftFileURL(for: key)
        guard
            fileManager.fileExists(
                atPath: fileURL.path
            )
        else {
            return nil
        }
        guard
            let data = try? Data(
                contentsOf: fileURL
            )
        else {
            return nil
        }
        guard
            let record = try? decoder.decode(
                StoredRecord.self,
                from: data
            ),
            record.formatVersion
                == Self.formatVersion,
            !record.draft.body.isEmpty
        else {
            try? fileManager.removeItem(
                at: fileURL
            )
            return nil
        }
        return record.draft
    }

    func store(
        _ draft: GitLabDiscussionDraft,
        for key: GitLabDiscussionDraftKey
    ) throws(GitLabDiscussionDraftStoreError) {
        if
            let stored = self.draft(for: key),
            stored.revision >= draft.revision
        {
            return
        }
        guard !draft.body.isEmpty else {
            remove(for: key)
            return
        }

        do {
            let accountDirectory =
                accountDirectory(
                    for: key.accountID
                )
            try createProtectedDirectory(
                rootDirectory
            )
            try createProtectedDirectory(
                accountDirectory
            )
            try persist(
                draft,
                at: draftFileURL(for: key)
            )
        } catch {
            throw .storage
        }
    }

    func remove(
        for key: GitLabDiscussionDraftKey
    ) {
        try? fileManager.removeItem(
            at: draftFileURL(for: key)
        )
    }

    func removeAll(
        for accountID: GitLabAccountID
    ) {
        try? fileManager.removeItem(
            at: accountDirectory(
                for: accountID
            )
        )
    }

    private var encoder: PropertyListEncoder {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return encoder
    }

    private var decoder: PropertyListDecoder {
        PropertyListDecoder()
    }

    private func persist(
        _ draft: GitLabDiscussionDraft,
        at fileURL: URL
    ) throws {
        let record = StoredRecord(
            formatVersion: Self.formatVersion,
            draft: draft
        )
        let data = try encoder.encode(record)
        try data.write(
            to: fileURL,
            options: [
                .atomic,
                .completeFileProtection,
            ]
        )
        try fileManager.setAttributes(
            [
                .protectionKey:
                    FileProtectionType.complete,
            ],
            ofItemAtPath: fileURL.path
        )
    }

    private func createProtectedDirectory(
        _ directory: URL
    ) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [
                .protectionKey:
                    FileProtectionType.complete,
            ],
            ofItemAtPath: directory.path
        )
    }

    private func accountDirectory(
        for accountID: GitLabAccountID
    ) -> URL {
        rootDirectory.appending(
            path: Self.hash(
                accountID.storageIdentifier
            ),
            directoryHint: .isDirectory
        )
    }

    private func draftFileURL(
        for key: GitLabDiscussionDraftKey
    ) -> URL {
        accountDirectory(
            for: key.accountID
        )
        .appending(
            path:
                Self.hash(
                    key.storageIdentifier
                )
                + ".draft",
            directoryHint: .notDirectory
        )
    }

    private static func hash(
        _ value: String
    ) -> String {
        SHA256.hash(
            data: Data(value.utf8)
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
