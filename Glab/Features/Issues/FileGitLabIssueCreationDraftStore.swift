import CryptoKit
import Foundation

actor FileGitLabIssueCreationDraftStore:
    GitLabIssueCreationDraftStoring
{
    private struct StoredRecord:
        Codable,
        Sendable
    {
        let formatVersion: Int
        let keyDigest: String
        let draft: GitLabIssueCreationDraft
    }

    static let maximumStoredRecordBytes =
        4 * 1_024 * 1_024

    private static let formatVersion = 1
    private static let directoryName =
        "GlabGitLabIssueCreationDrafts"

    private let rootDirectory: URL
    private let fileManager: FileManager

    init(
        rootDirectory: URL =
            URL.applicationSupportDirectory
            .appending(
                path:
                    FileGitLabIssueCreationDraftStore
                    .directoryName,
                directoryHint: .isDirectory
            ),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.fileManager = fileManager
    }

    func draft(
        for key: GitLabIssueCreationDraftKey
    ) -> GitLabIssueCreationDraft? {
        let fileURL = draftFileURL(
            for: key
        )
        guard
            fileManager.fileExists(
                atPath: fileURL.path
            )
        else {
            return nil
        }

        guard
            let values =
                try? fileURL.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .isSymbolicLinkKey,
                        .fileSizeKey,
                    ]
                ),
            values.isRegularFile == true,
            values.isSymbolicLink != true,
            let fileSize = values.fileSize,
            fileSize
                <= Self
                .maximumStoredRecordBytes,
            let data = try? Data(
                contentsOf: fileURL,
                options: .mappedIfSafe
            ),
            data.count
                <= Self
                .maximumStoredRecordBytes,
            let record = try? decoder.decode(
                StoredRecord.self,
                from: data
            ),
            record.formatVersion
                == Self.formatVersion,
            record.keyDigest
                == Self.hash(
                    key.storageIdentifier
                ),
            record.draft.hasValidState,
            !record.draft.isPristine
        else {
            discardInvalidRecord(
                at: fileURL
            )
            return nil
        }

        return record.draft
    }

    func store(
        _ draft: GitLabIssueCreationDraft,
        for key: GitLabIssueCreationDraftKey
    ) throws(
        GitLabIssueCreationDraftStoreError
    ) {
        guard draft.hasValidState else {
            throw .storage
        }
        if
            let stored = self.draft(for: key),
            stored.revision >= draft.revision
        {
            return
        }
        guard !draft.isPristine else {
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
                key: key,
                at: draftFileURL(for: key)
            )
        } catch {
            throw .storage
        }
    }

    func remove(
        for key: GitLabIssueCreationDraftKey
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
        _ draft: GitLabIssueCreationDraft,
        key: GitLabIssueCreationDraftKey,
        at fileURL: URL
    ) throws {
        let record = StoredRecord(
            formatVersion: Self.formatVersion,
            keyDigest: Self.hash(
                key.storageIdentifier
            ),
            draft: draft
        )
        let data = try encoder.encode(record)
        guard
            data.count
                <= Self
                .maximumStoredRecordBytes
        else {
            throw GitLabIssueCreationDraftStoreError
                .storage
        }
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
            path:
                Self.hash(
                    GitLabIssueCreationDraftKey
                        .lengthPrefixed(
                            accountID
                                .storageIdentifier
                        )
                ),
            directoryHint: .isDirectory
        )
    }

    private func draftFileURL(
        for key: GitLabIssueCreationDraftKey
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

    private func discardInvalidRecord(
        at fileURL: URL
    ) {
        try? fileManager.removeItem(
            at: fileURL
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
