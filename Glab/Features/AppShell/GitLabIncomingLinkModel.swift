import Foundation
import Observation

@MainActor
@Observable
final class GitLabIncomingLinkModel {
    private(set) var pendingURL: URL?
    private(set) var decision:
        GitLabDeepLinkDecision?

    @discardableResult
    func receive(
        _ incomingURL: URL,
        accounts: [GitLabAccountID],
        activeAccountID:
            GitLabAccountID?
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
        reevaluate(
            accounts: accounts,
            activeAccountID:
                activeAccountID
        )
        return pendingURL != nil
    }

    func reevaluate(
        accounts: [GitLabAccountID],
        activeAccountID:
            GitLabAccountID?
    ) {
        guard let pendingURL else {
            decision = nil
            return
        }

        let nextDecision =
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: pendingURL,
                    accounts: accounts,
                    activeAccountID:
                        activeAccountID
                )

        guard nextDecision != .rejected else {
            clear()
            return
        }

        decision = nextDecision
    }

    func preserveForAccountTransition() {
        decision = nil
    }

    func offerBrowserFallback(
        for sourceURL: URL
    ) {
        guard pendingURL == sourceURL else {
            return
        }

        decision = .browserFallback(
            sourceURL: sourceURL
        )
    }

    func clear() {
        pendingURL = nil
        decision = nil
    }
}
