import CryptoKit
import Foundation

actor FileGitLabResponseCache:
    GitLabResponseCaching
{
    private struct StoredRecord:
        Codable,
        Sendable
    {
        let formatVersion: Int
        let response: GitLabCachedResponse
    }

    private struct FileRecord {
        let url: URL
        let size: Int
        let lastAccessedAt: Date
    }

    private static let formatVersion = 1
    private static let directoryName =
        "GlabGitLabResponseCache"
    private static let defaultCapacityBytes =
        25 * 1_024 * 1_024

    private let rootDirectory: URL
    private let capacityBytes: Int
    private let currentDate: @Sendable () -> Date
    private let fileManager: FileManager

    init(
        rootDirectory: URL = URL.cachesDirectory
            .appending(
                path:
                    FileGitLabResponseCache
                        .directoryName,
                directoryHint: .isDirectory
            ),
        capacityBytes: Int =
            FileGitLabResponseCache
                .defaultCapacityBytes,
        currentDate:
            @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
        self.capacityBytes = max(0, capacityBytes)
        self.currentDate = currentDate
        self.fileManager = fileManager
    }

    func response(
        for key: GitLabResponseCacheKey
    ) -> GitLabCachedResponse? {
        let fileURL = cacheFileURL(for: key)

        guard
            let data = try? Data(contentsOf: fileURL),
            let record = try? decoder.decode(
                StoredRecord.self,
                from: data
            ),
            record.formatVersion == Self.formatVersion
        else {
            try? fileManager.removeItem(at: fileURL)
            return nil
        }

        let accessed = record.response.accessed(
            at: currentDate()
        )
        try? persist(
            accessed,
            at: fileURL
        )
        return accessed
    }

    func store(
        _ response: GitLabCachedResponse,
        for key: GitLabResponseCacheKey
    ) throws(GitLabResponseCacheError) {
        do {
            let accountDirectory =
                cacheAccountDirectory(for: key.account)
            try createDirectoryIfNeeded(accountDirectory)
            try persist(
                response,
                at: cacheFileURL(for: key)
            )
            try pruneIfNeeded()
        } catch {
            throw .storage
        }
    }

    func remove(
        for key: GitLabResponseCacheKey
    ) {
        try? fileManager.removeItem(
            at: cacheFileURL(for: key)
        )
    }

    func removeAll(
        for account: GitLabCacheAccount
    ) {
        try? fileManager.removeItem(
            at: cacheAccountDirectory(for: account)
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
        _ response: GitLabCachedResponse,
        at fileURL: URL
    ) throws {
        let record = StoredRecord(
            formatVersion: Self.formatVersion,
            response: response
        )
        let data = try encoder.encode(record)
        try data.write(
            to: fileURL,
            options: [
                .atomic,
                .completeFileProtectionUntilFirstUserAuthentication,
            ]
        )
        try fileManager.setAttributes(
            [
                .modificationDate: response.lastAccessedAt,
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication,
            ],
            ofItemAtPath: fileURL.path
        )
    }

    private func createDirectoryIfNeeded(
        _ directory: URL
    ) throws {
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try fileManager.setAttributes(
            [
                .protectionKey:
                    FileProtectionType
                        .completeUntilFirstUserAuthentication,
            ],
            ofItemAtPath: directory.path
        )
    }

    private func pruneIfNeeded() throws {
        var files = cacheFiles()
        var totalBytes = files.reduce(0) {
            $0 + $1.size
        }

        guard totalBytes > capacityBytes else {
            return
        }

        files.sort {
            $0.lastAccessedAt < $1.lastAccessedAt
        }

        for file in files
        where totalBytes > capacityBytes
        {
            try fileManager.removeItem(at: file.url)
            totalBytes -= file.size
        }
    }

    private func cacheFiles() -> [FileRecord] {
        guard
            let enumerator = fileManager.enumerator(
                at: rootDirectory,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ],
                options: [.skipsHiddenFiles]
            )
        else {
            return []
        }

        return enumerator.compactMap { element in
            guard
                let url = element as? URL,
                url.pathExtension == "cache",
                let values = try? url.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .fileSizeKey,
                        .contentModificationDateKey,
                    ]
                ),
                values.isRegularFile == true
            else {
                return nil
            }

            return FileRecord(
                url: url,
                size: values.fileSize ?? 0,
                lastAccessedAt:
                    values.contentModificationDate
                    ?? .distantPast
            )
        }
    }

    private func cacheAccountDirectory(
        for account: GitLabCacheAccount
    ) -> URL {
        rootDirectory
            .appending(
                path: "v\(Self.formatVersion)",
                directoryHint: .isDirectory
            )
            .appending(
                path: digest(account.storageIdentifier),
                directoryHint: .isDirectory
            )
    }

    private func cacheFileURL(
        for key: GitLabResponseCacheKey
    ) -> URL {
        cacheAccountDirectory(for: key.account)
            .appending(
                path: "\(digest(key.requestIdentifier)).cache",
                directoryHint: .notDirectory
            )
    }

    private func digest(
        _ value: String
    ) -> String {
        SHA256.hash(
            data: Data(value.utf8)
        )
        .map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}
