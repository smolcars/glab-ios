import Foundation

@MainActor
protocol GitLabAccountIndexStoring: Sendable {
    func load() throws(GitLabCredentialStoreError) -> GitLabAccountIndex
    func save(
        _ index: GitLabAccountIndex
    ) throws(GitLabCredentialStoreError)
}

@MainActor
final class UserDefaultsGitLabAccountIndexStore:
    GitLabAccountIndexStoring
{
    private let defaults: UserDefaults
    private let storageKey: String

    init(
        defaults: UserDefaults = .standard,
        storageKey: String = "gitLabAccountIndex"
    ) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    func load() throws(GitLabCredentialStoreError) -> GitLabAccountIndex {
        guard defaults.object(forKey: storageKey) != nil else {
            return .empty
        }
        guard let data = defaults.data(forKey: storageKey) else {
            throw .corruptData
        }

        do {
            return try decoder.decode(
                GitLabAccountIndex.self,
                from: data
            )
        } catch {
            throw .corruptData
        }
    }

    func save(
        _ index: GitLabAccountIndex
    ) throws(GitLabCredentialStoreError) {
        do {
            defaults.set(
                try encoder.encode(index),
                forKey: storageKey
            )
        } catch {
            throw .encoding
        }
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }
}

@MainActor
final class InMemoryGitLabAccountIndexStore:
    GitLabAccountIndexStoring
{
    private var index: GitLabAccountIndex

    init(index: GitLabAccountIndex = .empty) {
        self.index = index
    }

    func load() throws(GitLabCredentialStoreError) -> GitLabAccountIndex {
        index
    }

    func save(
        _ index: GitLabAccountIndex
    ) throws(GitLabCredentialStoreError) {
        self.index = index
    }
}
