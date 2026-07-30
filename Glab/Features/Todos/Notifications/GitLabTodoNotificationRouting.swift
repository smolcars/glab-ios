import Foundation
import Observation
import UserNotifications

@MainActor
@Observable
final class GitLabTodoNotificationRouteModel {
    private(set) var pendingAccountKey:
        String?

    func receive(accountKey: String) {
        guard !accountKey.isEmpty else {
            return
        }
        pendingAccountKey = accountKey
    }

    func clear() {
        pendingAccountKey = nil
    }
}

nonisolated final class
    GitLabTodoNotificationDelegate:
    NSObject,
    UNUserNotificationCenterDelegate
{
    private let routeModel:
        GitLabTodoNotificationRouteModel

    init(
        routeModel:
            GitLabTodoNotificationRouteModel
    ) {
        self.routeModel = routeModel
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response:
            UNNotificationResponse
    ) async {
        guard
            let accountKey =
                response.notification
                    .request.content
                    .userInfo[
                        GitLabTodoNotificationManager
                            .accountKeyUserInfoKey
                    ] as? String
        else {
            return
        }

        await routeModel.receive(
            accountKey: accountKey
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification:
            UNNotification
    ) async
        -> UNNotificationPresentationOptions
    {
        []
    }
}
