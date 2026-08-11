import Foundation
import Testing
@testable import Glab

@Suite("GitLab Markdown badge loader")
struct GitLabMarkdownBadgeLoaderTests {
    @Test("Recognizes supported GitLab badge URLs on the exact instance")
    func routes() throws {
        let siteURL = try GitLabHost(
            "https://gitlab.example.com"
        ).siteURL

        let pipeline = try #require(
            GitLabMarkdownBadgeRoute(
                url: URL(
                    string:
                        "https://gitlab.example.com/group/old-project/badges/main/pipeline.svg?ignore_skipped=true"
                )!,
                siteURL: siteURL
            )
        )
        #expect(
            pipeline.projectPath
                == "group/old-project"
        )
        #expect(
            pipeline.kind == .pipeline(ref: "main")
        )

        let coverage = try #require(
            GitLabMarkdownBadgeRoute(
                url: URL(
                    string:
                        "https://gitlab.example.com/group/project/badges/main/coverage.svg?min_good=90&min_acceptable=75&min_medium=70&key_text=tests"
                )!,
                siteURL: siteURL
            )
        )
        #expect(
            coverage.kind == .coverage(ref: "main")
        )
        #expect(coverage.keyText == "tests")
        #expect(coverage.coverageLimits.good == 90)
        #expect(
            coverage.coverageLimits.acceptable
                == 75
        )
        #expect(coverage.coverageLimits.medium == 70)

        let release = try #require(
            GitLabMarkdownBadgeRoute(
                url: URL(
                    string:
                        "https://gitlab.example.com/group/project/-/badges/release.svg"
                )!,
                siteURL: siteURL
            )
        )
        #expect(release.kind == .release)
        #expect(
            release.projectPath == "group/project"
        )

        #expect(
            GitLabMarkdownBadgeRoute(
                url: URL(
                    string:
                        "https://images.example.com/group/project/badges/main/pipeline.svg"
                )!,
                siteURL: siteURL
            ) == nil
        )
    }

    @Test("Loads a private pipeline badge through authenticated APIs")
    func pipelineFallback() async throws {
        let host = try GitLabHost(
            "https://gitlab.example.com"
        )
        let client = RecordingMarkdownBadgeClient()
        let loader = LiveGitLabMarkdownBadgeLoader(
            host: host,
            client: client
        )

        let image = try #require(
            await loader.image(
                for: URL(
                    string:
                        "https://gitlab.example.com/group/moved-project/badges/main/pipeline.svg"
                )!,
                targetPixelWidth: 300
            )
        )

        #expect(image.pixelWidth > 0)
        #expect(image.pixelHeight == 60)
        #expect(
            await client.paths == [
                ["projects", "group/moved-project"],
                [
                    "projects",
                    "263",
                    "pipelines",
                    "latest",
                ],
            ]
        )
        #expect(
            await client.queryItems.last == [
                URLQueryItem(
                    name: "ref",
                    value: "main"
                ),
            ]
        )
    }

    @Test("Renders compact badge images for missing values")
    func missingValues() throws {
        let coverage = try GitLabMarkdownBadgeRenderer
            .render(
                .coverage(
                    value: nil,
                    limits:
                        GitLabMarkdownCoverageLimits(),
                    keyText: nil
                ),
                targetPixelWidth: 300
            )
        let release = try GitLabMarkdownBadgeRenderer
            .render(
                .release(
                    tag: nil,
                    keyText: nil
                ),
                targetPixelWidth: 300
            )

        #expect(coverage.pixelHeight == 60)
        #expect(release.pixelHeight == 60)
        #expect(coverage.pixelWidth > 0)
        #expect(release.pixelWidth > 0)
    }
}

private actor RecordingMarkdownBadgeClient:
    GitLabSessionRequestSending
{
    private(set) var paths: [[String]] = []
    private(set) var queryItems:
        [[URLQueryItem]] = []

    func send<Response>(
        _ endpoint: GitLabAPIRequest<Response>
    ) async throws(GitLabSessionClientError)
        -> Response
    {
        paths.append(endpoint.pathComponents)
        queryItems.append(endpoint.queryItems)

        if Response.self
            == GitLabMarkdownBadgeProject.self
        {
            return GitLabMarkdownBadgeProject(
                id: 263
            ) as! Response
        }
        if Response.self
            == GitLabMarkdownBadgePipeline.self
        {
            return GitLabMarkdownBadgePipeline(
                status: GitLabCIStatus(
                    rawValue: "failed"
                ),
                coverage: nil
            ) as! Response
        }
        throw .api(.invalidResponse)
    }
}
