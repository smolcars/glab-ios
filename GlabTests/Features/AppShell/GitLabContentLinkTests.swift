import Foundation
import Testing
@testable import Glab

@Suite("GitLab content link")
struct GitLabContentLinkTests {
    @Test("Accepts direct HTTPS and a strict glab open wrapper")
    func extractsTargetURL() throws {
        let target = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project/-/issues/7"
            )
        )
        let encodedTarget = try #require(
            target.absoluteString
                .addingPercentEncoding(
                    withAllowedCharacters:
                        .urlQueryAllowed
                )
        )
        let wrapped = try #require(
            URL(
                string:
                    "glab://open?url="
                    + encodedTarget
            )
        )

        #expect(
            GitLabContentLink.targetURL(
                from: target
            ) == target
        )
        #expect(
            GitLabContentLink.targetURL(
                from: wrapped
            ) == target
        )
    }

    @Test("Rejects malformed wrappers and the OAuth callback")
    func rejectsInvalidWrappers() throws {
        let urls = try [
            "glab://oauth/callback?code=secret&state=state",
            "glab://wrong?url=https%3A%2F%2Fgitlab.com%2Fg%2Fp",
            "glab://open/path?url=https%3A%2F%2Fgitlab.com%2Fg%2Fp",
            "glab://open",
            "glab://open?other=https%3A%2F%2Fgitlab.com%2Fg%2Fp",
            "glab://open?url=https%3A%2F%2Fgitlab.com%2Fg%2Fp"
                + "&url=https%3A%2F%2Fgitlab.com%2Fother%2Fp",
            "glab://open?url=http%3A%2F%2Fgitlab.com%2Fg%2Fp",
            "glab://open?url=glab%3A%2F%2Fopen",
            "glab://open?url=https%3A%2F%2Fuser%3Apass"
                + "%40gitlab.com%2Fg%2Fp",
            "https://user:pass@gitlab.com/g/p",
        ].map {
            try #require(URL(string: $0))
        }

        for url in urls {
            #expect(
                GitLabContentLink.targetURL(
                    from: url
                ) == nil
            )
        }
    }

    @Test("Intercepts only exact configured-site Markdown links")
    func classifiesInAppMarkdownLinks() throws {
        let host = try GitLabHost(
            "https://gitlab.example.com/gitlab"
        )
        let handledURLs = try [
            "https://gitlab.example.com/gitlab/group/project",
            "https://gitlab.example.com/gitlab/group/project/-/issues/7",
            "https://gitlab.example.com/gitlab/group/project/-/wiki/home",
        ].map {
            try #require(URL(string: $0))
        }
        let systemURLs = try [
            "https://docs.gitlab.com/",
            "https://gitlab.example.com/group/project",
            "https://gitlab.example.com.evil.test/gitlab/group/project",
            "http://gitlab.example.com/gitlab/group/project",
        ].map {
            try #require(URL(string: $0))
        }

        for url in handledURLs {
            #expect(
                GitLabInAppLinkRouting
                    .shouldHandle(
                        url,
                        for: host
                    )
            )
        }

        for url in systemURLs {
            #expect(
                !GitLabInAppLinkRouting
                    .shouldHandle(
                        url,
                        for: host
                    )
            )
        }
    }
}
