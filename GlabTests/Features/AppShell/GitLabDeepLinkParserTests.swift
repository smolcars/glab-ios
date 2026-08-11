import Foundation
import Testing
@testable import Glab

@Suite("GitLab deep-link parser")
struct GitLabDeepLinkParserTests {
    @Test("Parses supported project, work-item, and repository-file routes")
    func parsesSupportedRoutes() throws {
        let gitLabCom = try GitLabHost(
            "https://gitlab.com"
        )
        let selfManaged = try GitLabHost(
            "https://gitlab.example.com/gitlab"
        )

        let cases: [
            (
                host: GitLabHost,
                url: String,
                target: GitLabDeepLinkTarget
            )
        ] = [
            (
                gitLabCom,
                "https://gitlab.com/group/project",
                .project(
                    pathWithNamespace:
                        "group/project"
                )
            ),
            (
                gitLabCom,
                "https://GITLAB.COM:443/group/subgroup/project/"
                    + "?ref=main#readme",
                .project(
                    pathWithNamespace:
                        "group/subgroup/project"
                )
            ),
            (
                selfManaged,
                "https://gitlab.example.com/gitlab/"
                    + "group/subgroup/project/-/issues/17",
                .issue(
                    pathWithNamespace:
                        "group/subgroup/project",
                    iid: 17
                )
            ),
            (
                selfManaged,
                "https://gitlab.example.com/gitlab/"
                    + "group%2Fsubgroup/project/"
                    + "-/merge_requests/23/",
                .mergeRequest(
                    pathWithNamespace:
                        "group/subgroup/project",
                    iid: 23
                )
            ),
            (
                gitLabCom,
                "https://gitlab.com/ark-bitcoin/bark/"
                    + "-/blob/master/docs/CONTRIBUTING.md#setup",
                .repositoryFile(
                    pathWithNamespace:
                        "ark-bitcoin/bark",
                    ref: "master",
                    path: "docs/CONTRIBUTING.md"
                )
            ),
        ]

        for testCase in cases {
            let url = try #require(
                URL(string: testCase.url)
            )
            #expect(
                GitLabDeepLinkParser.parse(
                    url,
                    for: testCase.host
                ) == .supported(
                    testCase.target
                )
            )
        }
    }

    @Test("Requires a positive canonical IID")
    func requiresPositiveIID() throws {
        let host = try GitLabHost(
            "gitlab.example.com"
        )

        for iid in [
            "0",
            "-1",
            "+1",
            "1.0",
            "abc",
            "999999999999999999999999999",
        ] {
            let url = try #require(
                URL(
                    string:
                        "https://gitlab.example.com/"
                        + "group/project/-/issues/"
                        + iid
                )
            )
            #expect(
                GitLabDeepLinkParser.parse(
                    url,
                    for: host
                ) == .unsupported(url)
            )
        }
    }

    @Test("Keeps safe exact-site unsupported paths as browser fallbacks")
    func preservesSafeUnsupportedURLs() throws {
        let host = try GitLabHost(
            "gitlab.example.com/gitlab"
        )
        let urls = try [
            "https://gitlab.example.com/gitlab/group/project/-/wiki/home",
            "https://gitlab.example.com/gitlab/group/project/-/issues/1/extra",
            "https://gitlab.example.com/gitlab/group/project/-/issues",
            "https://gitlab.example.com/gitlab/group/project/-/blob/main",
            "https://gitlab.example.com/gitlab/one-component",
            "https://gitlab.example.com/gitlab/group/project/-/issues/01",
        ].map {
            try #require(URL(string: $0))
        }

        for url in urls {
            #expect(
                GitLabDeepLinkParser.parse(
                    url,
                    for: host
                ) == .unsupported(url)
            )
        }
    }

    @Test("Rejects unsafe origins and paths")
    func rejectsUnsafeURLs() throws {
        let host = try GitLabHost(
            "https://gitlab.example.com/gitlab"
        )
        let urls = try [
            "http://gitlab.example.com/gitlab/group/project",
            "https://user:password@gitlab.example.com/gitlab/group/project",
            "https://gitlab.example.com.evil.test/gitlab/group/project",
            "https://evil-gitlab.example.com/gitlab/group/project",
            "https://gitlab.example.com:8443/gitlab/group/project",
            "https://gitlab.example.com/gitlab-evil/group/project",
            "https://gitlab.example.com/gitlab/group/%2E%2E/project",
            "https://gitlab.example.com/gitlab/group%252Fsubgroup/project",
            "https://gitlab.example.com/gitlab/group%255Csubgroup/project",
            "https://gitlab.example.com/gitlab/group%250A/project",
        ].map {
            try #require(URL(string: $0))
        }

        for url in urls {
            #expect(
                GitLabDeepLinkParser.parse(
                    url,
                    for: host
                ) == .untrusted
            )
        }
    }

    @Test("Matches non-default ports exactly")
    func matchesNonDefaultPort() throws {
        let host = try GitLabHost(
            "https://gitlab.example.com:8443/root"
        )
        let matchingURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com:8443/"
                    + "root/group/project"
            )
        )
        let missingPortURL = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "root/group/project"
            )
        )

        #expect(
            GitLabDeepLinkParser.parse(
                matchingURL,
                for: host
            ) == .supported(
                .project(
                    pathWithNamespace:
                        "group/project"
                )
            )
        )
        #expect(
            GitLabDeepLinkParser.parse(
                missingPortURL,
                for: host
            ) == .untrusted
        )
    }
}
