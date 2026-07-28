import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab incoming-link model")
struct GitLabIncomingLinkModelTests {
    @Test("Stores and evaluates only an extracted HTTPS target")
    func retainsValidatedTarget() throws {
        let model = GitLabIncomingLinkModel()
        let account = try makeAccount(
            host: "gitlab.example.com",
            userID: 7
        )
        let target = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project"
            )
        )
        let wrapper = try #require(
            URL(
                string:
                    "glab://open?url=https%3A%2F%2F"
                    + "gitlab.example.com%2Fgroup%2Fproject"
            )
        )
        let invalid = try #require(
            URL(
                string:
                    "glab://open?url=http%3A%2F%2F"
                    + "gitlab.example.com%2Fgroup%2Fproject"
            )
        )

        #expect(
            model.receive(
                wrapper,
                accounts: [account],
                activeAccountID: account
            )
        )
        #expect(model.pendingURL == target)
        #expect(
            model.decision == .open(
                accountID: account,
                target: .project(
                    pathWithNamespace:
                        "group/project"
                ),
                sourceURL: target
            )
        )
        #expect(
            !model.receive(
                invalid,
                accounts: [account],
                activeAccountID: account
            )
        )
        #expect(model.pendingURL == target)

        model.clear()
        #expect(model.pendingURL == nil)
        #expect(model.decision == nil)
    }

    @Test("Reparses a pending link after an explicit account transition")
    func preservesPendingLinkAcrossAccountSwitch() throws {
        let model = GitLabIncomingLinkModel()
        let active = try makeAccount(
            host: "other.example.com",
            userID: 1
        )
        let matching = try makeAccount(
            host: "gitlab.example.com",
            userID: 2
        )
        let target = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/issues/17"
            )
        )

        #expect(
            model.receive(
                target,
                accounts: [active, matching],
                activeAccountID: active
            )
        )
        #expect(
            model.decision == .confirmSwitch(
                accountID: matching,
                target: .issue(
                    pathWithNamespace:
                        "group/project",
                    iid: 17
                ),
                sourceURL: target
            )
        )

        model.preserveForAccountTransition()

        #expect(model.pendingURL == target)
        #expect(model.decision == nil)

        model.reevaluate(
            accounts: [active, matching],
            activeAccountID: matching
        )

        #expect(
            model.decision == .open(
                accountID: matching,
                target: .issue(
                    pathWithNamespace:
                        "group/project",
                    iid: 17
                ),
                sourceURL: target
            )
        )
    }

    @Test("Reevaluates a signed-out link after authentication")
    func continuesPendingLinkAfterSignIn() throws {
        let model = GitLabIncomingLinkModel()
        let account = try makeAccount(
            host: "gitlab.example.com",
            userID: 9
        )
        let target = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project"
            )
        )

        #expect(
            model.receive(
                target,
                accounts: [],
                activeAccountID: nil
            )
        )
        #expect(
            model.decision == .signedOut(
                sourceURL: target
            )
        )

        model.preserveForAccountTransition()
        model.reevaluate(
            accounts: [account],
            activeAccountID: account
        )

        #expect(
            model.decision == .open(
                accountID: account,
                target: .project(
                    pathWithNamespace:
                        "group/project"
                ),
                sourceURL: target
            )
        )
    }

    @Test("Offers browser fallback only for the current pending URL")
    func offersFallbackForCurrentURL() throws {
        let model = GitLabIncomingLinkModel()
        let account = try makeAccount(
            host: "gitlab.example.com",
            userID: 1
        )
        let target = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/issues/17"
            )
        )
        let staleURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "other/project"
            )
        )

        #expect(
            model.receive(
                target,
                accounts: [account],
                activeAccountID: account
            )
        )

        model.offerBrowserFallback(
            for: staleURL
        )
        #expect(
            model.decision == .open(
                accountID: account,
                target: .issue(
                    pathWithNamespace:
                        "group/project",
                    iid: 17
                ),
                sourceURL: target
            )
        )

        model.offerBrowserFallback(
            for: target
        )
        #expect(
            model.decision == .browserFallback(
                sourceURL: target
            )
        )
    }

    @Test("Does not retain a configured-host lookalike")
    func rejectsConfiguredHostLookalike() throws {
        let model = GitLabIncomingLinkModel()
        let account = try makeAccount(
            host: "gitlab.example.com",
            userID: 1
        )
        let lookalike = try #require(
            URL(
                string:
                    "glab://open?url=https%3A%2F%2F"
                    + "gitlab.example.com.evil.test"
                    + "%2Fgroup%2Fproject"
            )
        )

        #expect(
            !model.receive(
                lookalike,
                accounts: [account],
                activeAccountID: account
            )
        )
        #expect(model.pendingURL == nil)
        #expect(model.decision == nil)
    }

    private func makeAccount(
        host: String,
        userID: Int
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(host),
            userID: userID
        )
    }
}
