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
}
