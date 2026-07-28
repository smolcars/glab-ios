import Foundation
import Testing
@testable import Glab

@Suite("GitLab deep-link account matcher")
struct GitLabDeepLinkAccountMatcherTests {
    @Test("Keeps the matching active account")
    func keepsActiveAccount() throws {
        let first = try account(
            host: "gitlab.example.com",
            userID: 1
        )
        let active = try account(
            host: "gitlab.example.com",
            userID: 2
        )
        let url = try projectURL()

        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: url,
                    accounts: [first, active],
                    activeAccountID: active
                ) == .open(
                    accountID: active,
                    target: .project(
                        pathWithNamespace:
                            "group/project"
                    ),
                    sourceURL: url
                )
        )
    }

    @Test("Asks before switching to one inactive matching account")
    func confirmsSingleInactiveAccount() throws {
        let active = try account(
            host: "other.example.com",
            userID: 1
        )
        let matching = try account(
            host: "gitlab.example.com",
            userID: 2
        )
        let url = try projectURL()

        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: url,
                    accounts: [active, matching],
                    activeAccountID: active
                ) == .confirmSwitch(
                    accountID: matching,
                    target: .project(
                        pathWithNamespace:
                            "group/project"
                    ),
                    sourceURL: url
                )
        )
    }

    @Test("Requires a choice between multiple inactive matching accounts")
    func choosesBetweenMatchingAccounts() throws {
        let active = try account(
            host: "other.example.com",
            userID: 1
        )
        let first = try account(
            host: "gitlab.example.com",
            userID: 2
        )
        let second = try account(
            host: "gitlab.example.com",
            userID: 3
        )
        let url = try projectURL()

        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: url,
                    accounts: [
                        active,
                        first,
                        second,
                    ],
                    activeAccountID: active
                ) == .chooseAccount(
                    accountIDs: [first, second],
                    target: .project(
                        pathWithNamespace:
                            "group/project"
                    ),
                    sourceURL: url
                )
        )
    }

    @Test("Uses the longest matching relative site root")
    func prefersLongestSiteRoot() throws {
        let rootAccount = try account(
            host: "gitlab.example.com",
            userID: 1
        )
        let relativeRootAccount = try account(
            host:
                "gitlab.example.com/company",
            userID: 2
        )
        let url = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "company/group/project"
            )
        )

        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: url,
                    accounts: [
                        rootAccount,
                        relativeRootAccount,
                    ],
                    activeAccountID:
                        rootAccount
                ) == .confirmSwitch(
                    accountID:
                        relativeRootAccount,
                    target: .project(
                        pathWithNamespace:
                            "group/project"
                    ),
                    sourceURL: url
                )
        )
    }

    @Test("Distinguishes signed out and a missing host account")
    func handlesMissingAccounts() throws {
        let url = try projectURL()
        let unrelated = try account(
            host: "other.example.com",
            userID: 1
        )

        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: url,
                    accounts: [],
                    activeAccountID: nil
                ) == .signedOut(
                    sourceURL: url
                )
        )
        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: url,
                    accounts: [unrelated],
                    activeAccountID:
                        unrelated
                ) == .addAccount(
                    sourceURL: url
                )
        )
    }

    @Test("Offers a browser fallback only for a safe configured site")
    func handlesFallbackAndUnsafeURL() throws {
        let account = try account(
            host: "gitlab.example.com",
            userID: 1
        )
        let unsupported = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/wiki/home"
            )
        )
        let unsafe = try #require(
            URL(
                string:
                    "glab://open?url=http%3A%2F%2F"
                    + "gitlab.example.com%2Fgroup%2Fproject"
            )
        )

        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: unsupported,
                    accounts: [account],
                    activeAccountID: account
                ) == .browserFallback(
                    sourceURL: unsupported
                )
        )
        #expect(
            GitLabDeepLinkAccountMatcher
                .decision(
                    for: unsafe,
                    accounts: [account],
                    activeAccountID: account
                ) == .rejected
        )
    }

    @Test("Rejects configured-host lookalikes and port mismatches")
    func rejectsConfiguredOriginConflicts() throws {
        let account = try account(
            host: "gitlab.example.com",
            userID: 1
        )
        let conflictingURLs = try [
            "https://gitlab.example.com.evil.test/group/project",
            "https://evil-gitlab.example.com/group/project",
            "https://gitlab.example.com:8443/group/project",
        ].map {
            try #require(URL(string: $0))
        }

        for url in conflictingURLs {
            #expect(
                GitLabDeepLinkAccountMatcher
                    .decision(
                        for: url,
                        accounts: [account],
                        activeAccountID: account
                    ) == .rejected
            )
        }

        let unrelatedURLs = try [
            "https://code.example.net/group/project",
            "https://example.com/group/project",
        ].map {
            try #require(URL(string: $0))
        }

        for url in unrelatedURLs {
            #expect(
                GitLabDeepLinkAccountMatcher
                    .decision(
                        for: url,
                        accounts: [account],
                        activeAccountID: account
                    ) == .addAccount(
                        sourceURL: url
                    )
            )
        }
    }
}

private extension GitLabDeepLinkAccountMatcherTests {
    func account(
        host: String,
        userID: Int
    ) throws -> GitLabAccountID {
        GitLabAccountID(
            host: try GitLabHost(host),
            userID: userID
        )
    }

    func projectURL() throws -> URL {
        try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project"
            )
        )
    }
}
