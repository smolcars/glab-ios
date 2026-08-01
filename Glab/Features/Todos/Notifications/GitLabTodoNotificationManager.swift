import BackgroundTasks
import Foundation
import Observation
import UIKit
import UserNotifications

nonisolated enum GitLabTodoNotificationAuthorization:
    Equatable,
    Sendable
{
    case notDetermined
    case denied
    case authorized
}

nonisolated enum GitLabTodoNotificationEnableResult:
    Equatable,
    Sendable
{
    case enabled
    case denied
    case failed(String)
}

@MainActor
@Observable
final class GitLabTodoNotificationManager {
    nonisolated static let backgroundTaskIdentifier =
        "com.dunder.glab.todo-notifications"
    nonisolated static let accountKeyUserInfoKey =
        "glabTodoAccountKey"

    private(set) var authorization:
        GitLabTodoNotificationAuthorization =
            .notDetermined
    private(set) var revision = 0

    @ObservationIgnored
    private let store:
        UserDefaultsGitLabTodoNotificationStore
    @ObservationIgnored
    private let notificationCenter:
        UNUserNotificationCenter

    init(
        store:
            UserDefaultsGitLabTodoNotificationStore =
                UserDefaultsGitLabTodoNotificationStore(),
        notificationCenter:
            UNUserNotificationCenter = .current()
    ) {
        self.store = store
        self.notificationCenter =
            notificationCenter
    }

    var backgroundRefreshIsAvailable: Bool {
        UIApplication.shared
            .backgroundRefreshStatus
            == .available
    }

    func isEnabled(
        for accountID: GitLabAccountID
    ) -> Bool {
        _ = revision
        return store.isEnabled(
            for: Self.accountKey(
                for: accountID
            )
        )
    }

    func refreshAuthorization() async {
        let settings =
            await notificationCenter
                .notificationSettings()
        authorization = Self.authorization(
            for: settings.authorizationStatus
        )
    }

    func setEnabled(
        _ isEnabled: Bool,
        for accountID: GitLabAccountID,
        appSession: AppSession
    ) async -> GitLabTodoNotificationEnableResult {
        if !isEnabled {
            await disable(for: accountID)
            return .enabled
        }

        do {
            let canNotify =
                try await requestAuthorizationIfNeeded()
            guard canNotify else {
                return .denied
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        let accountKey = Self.accountKey(
            for: accountID
        )
        store.setEnabled(
            true,
            for: accountKey
        )
        revision &+= 1
        scheduleRefresh()
        await refresh(
            accountIDs: [accountID],
            appSession: appSession
        )
        return .enabled
    }

    func observe(
        todos: [GitLabTodo],
        for accountID: GitLabAccountID
    ) {
        let accountKey = Self.accountKey(
            for: accountID
        )
        guard
            store.isEnabled(
                for: accountKey
            ),
            let checkpoint =
                store.checkpoint(
                    for: accountKey
                )
        else {
            return
        }

        let observedCheckpoint =
            checkpoint.observing(
                todoIDs: todos.map(\.id)
            )
        guard
            observedCheckpoint != checkpoint
        else {
            return
        }
        store.save(
            observedCheckpoint,
            for: accountKey
        )
    }

    func reconcileAccounts(
        _ accountIDs: [GitLabAccountID]
    ) async {
        let validKeys = Set(
            accountIDs.map(Self.accountKey)
        )
        let removedKeys = store.reconcile(
            validAccountKeys: validKeys
        )
        for accountKey in removedKeys {
            await removeNotifications(
                for: accountKey
            )
        }
        revision &+= 1

        if store.hasEnabledAccounts {
            scheduleRefresh()
        } else {
            cancelRefresh()
        }
    }

    func scheduleRefresh() {
        guard store.hasEnabledAccounts else {
            cancelRefresh()
            return
        }

        BGTaskScheduler.shared
            .cancel(
                taskRequestWithIdentifier:
                    Self.backgroundTaskIdentifier
            )
        let request = BGAppRefreshTaskRequest(
            identifier:
                Self.backgroundTaskIdentifier
        )
        request.earliestBeginDate = Date(
            timeIntervalSinceNow: 15 * 60
        )
        try? BGTaskScheduler.shared
            .submit(request)
    }

    func performBackgroundRefresh(
        appSession: AppSession
    ) async {
        scheduleRefresh()
        guard
            UIApplication.shared
                .isProtectedDataAvailable
        else {
            return
        }

        if case .restoring = appSession.state {
            await appSession.restore()
        }
        await reconcileAccounts(
            appSession.committedAccountIDs
        )
        await refresh(
            accountIDs:
                appSession.committedAccountIDs,
            appSession: appSession
        )
    }

    func refresh(
        accountIDs: [GitLabAccountID],
        appSession: AppSession
    ) async {
        guard
            UIApplication.shared
                .isProtectedDataAvailable
        else {
            return
        }

        await refreshAuthorization()
        guard authorization == .authorized else {
            return
        }

        for accountID in accountIDs {
            guard !Task.isCancelled else {
                return
            }
            await refresh(
                accountID: accountID,
                appSession: appSession
            )
        }
    }

    static func accountKey(
        for accountID: GitLabAccountID
    ) -> String {
        GitLabTodoNotificationAccountKey
            .make(for: accountID)
    }

    private func requestAuthorizationIfNeeded()
        async throws -> Bool
    {
        await refreshAuthorization()
        switch authorization {
        case .authorized:
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted =
                try await notificationCenter
                    .requestAuthorization(
                        options: [
                            .alert,
                            .sound,
                        ]
                    )
            await refreshAuthorization()
            return granted
                && authorization == .authorized
        }
    }

    private func disable(
        for accountID: GitLabAccountID
    ) async {
        let accountKey = Self.accountKey(
            for: accountID
        )
        store.setEnabled(
            false,
            for: accountKey
        )
        revision &+= 1
        await removeNotifications(
            for: accountKey
        )

        if store.hasEnabledAccounts {
            scheduleRefresh()
        } else {
            cancelRefresh()
        }
    }

    private func cancelRefresh() {
        BGTaskScheduler.shared.cancel(
            taskRequestWithIdentifier:
                Self.backgroundTaskIdentifier
        )
    }

    private func refresh(
        accountID: GitLabAccountID,
        appSession: AppSession
    ) async {
        let accountKey = Self.accountKey(
            for: accountID
        )
        guard
            store.isEnabled(for: accountKey)
        else {
            return
        }

        do {
            guard
                let session =
                    try await appSession
                        .credentialStore
                        .load(for: accountID)
            else {
                return
            }

            let transport =
                URLSessionGitLabHTTPTransport()
            let client = GitLabSessionClient(
                session: session,
                transport: transport,
                tokenExchanger:
                    GitLabOAuthTokenClient(
                        transport: transport
                    ),
                credentialStore:
                    appSession.credentialStore,
                responseCache:
                    appSession.responseCache,
                sessionDidRefresh: {
                    refreshedSession in
                    await appSession
                        .synchronizeRefreshedSession(
                            refreshedSession,
                            for: accountID
                        )
                }
            )
            let loader = LiveGitLabTodoLoader(
                client: client,
                pageSize: 100
            )
            let todos = try await loadAllPendingTodos(
                using: loader
            )
            guard
                store.isEnabled(
                    for: accountKey
                )
            else {
                return
            }
            let result =
                GitLabTodoNotificationDetection
                    .evaluate(
                        todos: todos,
                        checkpoint:
                            store.checkpoint(
                                for: accountKey
                            )
                    )

            if !result.newTodos.isEmpty {
                try await deliverNotification(
                    count: result.newTodos.count,
                    accountKey: accountKey
                )
            }
            store.save(
                result.checkpoint,
                for: accountKey
            )
        } catch is CancellationError {
            return
        } catch {
            return
        }
    }

    private func loadAllPendingTodos(
        using loader: LiveGitLabTodoLoader
    ) async throws -> [GitLabTodo] {
        var todosByID: [Int: GitLabTodo] = [:]
        var nextPageURL: URL?
        var visitedPageURLs: Set<URL> = []

        repeat {
            try Task.checkCancellation()
            let page = try await loader.loadTodosPage(
                state: .pending,
                targetFilter: .all,
                after: nextPageURL
            )
            for todo in page.todos {
                todosByID[todo.id] = todo
            }
            if
                let nextURL = page.nextPageURL,
                !visitedPageURLs
                    .insert(nextURL)
                    .inserted
            {
                throw GitLabSessionClientError
                    .api(.invalidResponse)
            }
            nextPageURL = page.nextPageURL
        } while nextPageURL != nil

        return Array(todosByID.values)
    }

    private func deliverNotification(
        count: Int,
        accountKey: String
    ) async throws {
        let content =
            UNMutableNotificationContent()
        content.title =
            count == 1
                ? "New GitLab Todo"
                : "\(count) New GitLab Todos"
        content.body =
            "Open Glab to review."
        content.sound = .default
        content.threadIdentifier =
            "gitlab-todos-\(accountKey)"
        content.userInfo = [
            Self.accountKeyUserInfoKey:
                accountKey,
        ]

        try await notificationCenter.add(
            UNNotificationRequest(
                identifier:
                    "gitlab-todos-"
                    + UUID().uuidString,
                content: content,
                trigger: nil
            )
        )
    }

    private func removeNotifications(
        for accountKey: String
    ) async {
        let pending =
            await notificationCenter
                .pendingNotificationRequests()
        let pendingIDs = pending.compactMap {
            request in
            request.content.userInfo[
                Self.accountKeyUserInfoKey
            ] as? String == accountKey
                ? request.identifier
                : nil
        }
        notificationCenter
            .removePendingNotificationRequests(
                withIdentifiers: pendingIDs
            )

        let delivered =
            await notificationCenter
                .deliveredNotifications()
        let deliveredIDs = delivered.compactMap {
            notification in
            notification.request.content
                .userInfo[
                    Self.accountKeyUserInfoKey
                ] as? String == accountKey
                ? notification.request.identifier
                : nil
        }
        notificationCenter
            .removeDeliveredNotifications(
                withIdentifiers: deliveredIDs
            )
    }

    private static func authorization(
        for status: UNAuthorizationStatus
    ) -> GitLabTodoNotificationAuthorization {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .authorized, .provisional, .ephemeral:
            .authorized
        @unknown default:
            .denied
        }
    }
}
