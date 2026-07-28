import Foundation
import Observation

@MainActor
@Observable
final class GitLabIncomingLinkModel {
    private(set) var pendingURL: URL?

    @discardableResult
    func receive(
        _ incomingURL: URL
    ) -> Bool {
        guard
            let targetURL =
                GitLabContentLink.targetURL(
                    from: incomingURL
                )
        else {
            return false
        }

        pendingURL = targetURL
        return true
    }

    func clear() {
        pendingURL = nil
    }
}
