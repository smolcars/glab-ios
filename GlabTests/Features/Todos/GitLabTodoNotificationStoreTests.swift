import Foundation
import Testing
@testable import Glab

@Suite("GitLab Todo notification store")
@MainActor
struct GitLabTodoNotificationStoreTests {
    @Test("Uses a stable opaque account key")
    func usesOpaqueAccountKey() throws {
        let accountID = GitLabAccountID(
            host: try GitLabHost(
                "gitlab.example.com"
            ),
            userID: 42
        )

        let key =
            GitLabTodoNotificationAccountKey
                .make(for: accountID)

        #expect(key.count == 64)
        #expect(
            key
                == GitLabTodoNotificationAccountKey
                    .make(for: accountID)
        )
        #expect(
            !key.contains("gitlab.example.com")
        )
        #expect(
            key != accountID.storageIdentifier
        )
    }

    @Test("Persists opt-in and checkpoint")
    func persistsState() throws {
        let suiteName =
            "GitLabTodoNotificationStoreTests."
            + UUID().uuidString
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        let checkpoint =
            GitLabTodoNotificationCheckpoint(
                observedTodoIDs: [3, 5],
                newestObservedCreationDate:
                    Date(
                        timeIntervalSince1970:
                            100
                    )
            )

        let first =
            UserDefaultsGitLabTodoNotificationStore(
                defaults: defaults
            )
        first.setEnabled(
            true,
            for: "account"
        )
        first.save(
            checkpoint,
            for: "account"
        )

        let restored =
            UserDefaultsGitLabTodoNotificationStore(
                defaults: defaults
            )
        #expect(
            restored.isEnabled(
                for: "account"
            )
        )
        #expect(
            restored.checkpoint(
                for: "account"
            ) == checkpoint
        )
    }

    @Test("Disabling resets the baseline")
    func disablingResetsCheckpoint() throws {
        let suiteName =
            "GitLabTodoNotificationStoreTests."
            + UUID().uuidString
        let defaults = try #require(
            UserDefaults(suiteName: suiteName)
        )
        defer {
            defaults.removePersistentDomain(
                forName: suiteName
            )
        }
        let store =
            UserDefaultsGitLabTodoNotificationStore(
                defaults: defaults
            )
        store.setEnabled(true, for: "account")
        store.save(
            GitLabTodoNotificationCheckpoint(
                observedTodoIDs: [1],
                newestObservedCreationDate:
                    Date(
                        timeIntervalSince1970:
                            100
                    )
            ),
            for: "account"
        )

        store.setEnabled(false, for: "account")

        #expect(
            !store.isEnabled(for: "account")
        )
        #expect(
            store.checkpoint(for: "account")
                == nil
        )
    }
}
