import CryptoKit
import Foundation

nonisolated enum GitLabTodoNotificationAccountKey {
    static func make(
        for accountID: GitLabAccountID
    ) -> String {
        let digest = SHA256.hash(
            data: Data(
                accountID.storageIdentifier.utf8
            )
        )
        return digest.map {
            String(format: "%02x", $0)
        }
        .joined()
    }
}

@MainActor
final class UserDefaultsGitLabTodoNotificationStore {
    private struct PersistedState: Codable {
        let formatVersion: Int
        var enabledAccountKeys: Set<String>
        var checkpoints: [
            String:
                GitLabTodoNotificationCheckpoint
        ]

        static var empty: Self {
            Self(
                formatVersion: 1,
                enabledAccountKeys: [],
                checkpoints: [:]
            )
        }
    }

    private static let stateKey =
        "gitLabTodoNotificationState"

    private let defaults: UserDefaults
    private var state: PersistedState

    init(
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        state = Self.load(from: defaults)
    }

    var hasEnabledAccounts: Bool {
        !state.enabledAccountKeys.isEmpty
    }

    func isEnabled(
        for accountKey: String
    ) -> Bool {
        state.enabledAccountKeys
            .contains(accountKey)
    }

    func setEnabled(
        _ isEnabled: Bool,
        for accountKey: String
    ) {
        if isEnabled {
            state.enabledAccountKeys
                .insert(accountKey)
        } else {
            state.enabledAccountKeys
                .remove(accountKey)
            state.checkpoints
                .removeValue(forKey: accountKey)
        }
        save()
    }

    func checkpoint(
        for accountKey: String
    ) -> GitLabTodoNotificationCheckpoint? {
        state.checkpoints[accountKey]
    }

    func save(
        _ checkpoint:
            GitLabTodoNotificationCheckpoint,
        for accountKey: String
    ) {
        state.checkpoints[accountKey] =
            checkpoint
        save()
    }

    func reconcile(
        validAccountKeys: Set<String>
    ) -> Set<String> {
        let removedKeys =
            state.enabledAccountKeys
                .union(state.checkpoints.keys)
                .subtracting(validAccountKeys)
        guard !removedKeys.isEmpty else {
            return []
        }

        state.enabledAccountKeys
            .formIntersection(validAccountKeys)
        state.checkpoints =
            state.checkpoints.filter {
                validAccountKeys.contains($0.key)
            }
        save()
        return removedKeys
    }

    private func save() {
        guard
            let data = try? JSONEncoder()
                .encode(state)
        else {
            return
        }
        defaults.set(
            data,
            forKey: Self.stateKey
        )
    }

    private static func load(
        from defaults: UserDefaults
    ) -> PersistedState {
        guard
            let data = defaults.data(
                forKey: stateKey
            ),
            let state = try? JSONDecoder()
                .decode(
                    PersistedState.self,
                    from: data
                ),
            state.formatVersion == 1
        else {
            return .empty
        }

        return state
    }
}
