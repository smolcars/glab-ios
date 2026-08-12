#if DEBUG
    import SwiftUI

    struct GitLabRepositoryFixtureView: View {
        private let loader =
            GitLabRepositoryFixtureLoader()
        private let imageLoader =
            GitLabRepositoryFixtureImageLoader()
        private let accountID = GitLabAccountID(
            host:
                try! GitLabHost(
                    "gitlab.example.com"
                ),
            userID: 7
        )
        @State private var appSession = AppSession(
            credentialStore:
                KeychainGitLabCredentialStore(),
            accountIndexStore:
                UserDefaultsGitLabAccountIndexStore(),
            responseCache:
                FileGitLabResponseCache(),
            discussionDraftStore:
                FileGitLabDiscussionDraftStore(),
            resourceEditDraftStore:
                FileGitLabResourceEditDraftStore(),
            issueCreationDraftStore:
                FileGitLabIssueCreationDraftStore()
        )

        var body: some View {
            NavigationStack {
                GitLabRepositoryView(
                    project:
                        GitLabRepositoryFixtureLoader
                        .project,
                    loader: loader,
                    accountID: accountID,
                    appSession: appSession
                )
            }
            .environment(
                \.gitLabMarkdownImageLoader,
                imageLoader
            )
        }
    }

    private nonisolated struct
        GitLabRepositoryFixtureLoader:
        GitLabRepositoryLoading,
        Sendable
    {
        static let project = GitLabProject(
            id: 42,
            name: "glab-ios",
            nameWithNamespace:
                "Example / glab-ios",
            pathWithNamespace:
                "example/glab-ios",
            webURL: URL(
                string:
                    "https://gitlab.example.com/example/glab-ios"
            ),
            readmeURL: URL(
                string:
                    "https://gitlab.example.com/example/glab-ios/-/blob/main/README.md"
            ),
            avatarURL: nil,
            starCount: 12,
            lastActivityAt: Date(
                timeIntervalSince1970: 0
            ),
            defaultBranch: "main",
            visibility: .privateAccess,
            namespace: nil,
            issuesAccessLevel: .enabled,
            mergeRequestsAccessLevel: .enabled
        )

        func loadTreePage(
            projectID: Int,
            ref: String,
            path: String,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabRepositoryEntryPage
        {
            guard
                projectID == Self.project.id,
                ["main", "release/1.0", "develop"]
                    .contains(ref)
            else {
                throw .api(.notFound)
            }
            return GitLabRepositoryEntryPage(
                entries: Self.entries[path] ?? [],
                nextPageURL: nil
            )
        }

        func loadBranchesPage(
            projectID: Int,
            search: String?,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabRepositoryBranchPage
        {
            guard projectID == Self.project.id else {
                throw .api(.notFound)
            }
            let branches = Self.branches.filter {
                guard
                    let search,
                    !search.isEmpty
                else {
                    return true
                }
                return $0.name.localizedCaseInsensitiveContains(
                    search
                )
            }
            return GitLabRepositoryBranchPage(
                branches: branches,
                nextPageURL: nil
            )
        }

        func loadBranch(
            projectID: Int,
            name: String
        ) async throws(GitLabSessionClientError)
            -> GitLabRepositoryBranch
        {
            guard
                projectID == Self.project.id,
                let branch = Self.branches.first(
                    where: { $0.name == name }
                )
            else {
                throw .api(.notFound)
            }
            return branch
        }

        func loadSearchPage(
            projectID: Int,
            ref: String,
            query: String,
            after nextPageURL: URL?
        ) async throws(GitLabSessionClientError)
            -> GitLabRepositorySearchPage
        {
            guard projectID == Self.project.id else {
                throw .api(.notFound)
            }
            let matches = Self.sources.keys
                .filter {
                    $0.localizedCaseInsensitiveContains(
                        query
                    )
                }
                .sorted()
                .map {
                    GitLabRepositorySearchResult(
                        blobID: "fixture-\($0)",
                        path: $0,
                        filename:
                            URL(filePath: $0)
                            .lastPathComponent,
                        ref: ref,
                        startLine: 1,
                        projectID: projectID
                    )
                }
            return GitLabRepositorySearchPage(
                results: matches,
                nextPageURL: nil
            )
        }

        func loadSource(
            at route: GitLabRepositoryFileRoute
        ) async throws(
            GitLabRepositorySourceLoadError
        ) -> GitLabSourceDocument {
            guard
                let source = Self.sources[
                    route.path
                ]
            else {
                throw .session(.api(.notFound))
            }
            return GitLabSourceDocument(
                source: source,
                fileName: route.fileName
            )
        }

        private static let branches = [
            GitLabRepositoryBranch(
                name: "main",
                isDefault: true,
                isProtected: true,
                webURL: nil
            ),
            GitLabRepositoryBranch(
                name: "develop",
                isDefault: false,
                isProtected: true,
                webURL: nil
            ),
            GitLabRepositoryBranch(
                name: "release/1.0",
                isDefault: false,
                isProtected: false,
                webURL: nil
            ),
        ]

        private static let entries: [
            String: [GitLabRepositoryEntry]
        ] = [
            "": [
                entry(
                    "Sources",
                    type: .tree
                ),
                entry(
                    "Tests",
                    type: .tree
                ),
                entry(
                    "README.md",
                    type: .blob
                ),
                entry(
                    "build.sh",
                    type: .blob
                ),
                entry(
                    "Package.swift",
                    type: .blob
                ),
            ],
            "Sources": [
                entry(
                    "Repository",
                    parent: "Sources",
                    type: .tree
                ),
                entry(
                    "App.swift",
                    parent: "Sources",
                    type: .blob
                ),
            ],
            "Sources/Repository": [
                entry(
                    "GitLabRepositoryView.swift",
                    parent:
                        "Sources/Repository",
                    type: .blob
                ),
            ],
            "Tests": [],
        ]

        private static let sources: [
            String: String
        ] = [
            "README.md":
                """
                ![glab-ios logo](https://gitlab.example.com/fixtures/logo.svg)

                <div align="center">
                <h1>glab-ios</h1>
                <p><strong>A compact GitLab client for iPhone.</strong></p>
                <p><a href="https://gitlab.example.com/example/glab-ios">Project</a> · <a href="https://gitlab.example.com/example/glab-ios/-/issues">Issues</a></p>
                <p><a href="https://gitlab.example.com/example/glab-ios/-/pipelines"><img alt="pipeline failed" src="https://gitlab.example.com/fixtures/pipeline.svg"></a> <a href="https://gitlab.example.com/example/glab-ios/-/blob/main/LICENSE"><img alt="license MIT" src="https://gitlab.example.com/fixtures/license.svg"></a> <a href="https://gitlab.example.com/example/glab-ios/-/merge_requests"><img alt="PRs welcome" src="https://gitlab.example.com/fixtures/community.svg"></a></p>
                </div>

                ## Repository browser

                - Browse branches and folders
                - Search repository files
                - Read syntax-highlighted source

                ```swift
                struct RepositoryRoute {
                    let projectID: Int
                    let branch = "main"
                }
                ```
                """,
            "build.sh":
                """
                #!/usr/bin/env bash
                set -euo pipefail

                ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
                swift build --package-path "$ROOT_DIR" --configuration release
                """,
            "Package.swift":
                """
                import PackageDescription

                let package = Package(
                    name: "glab-ios",
                    platforms: [.iOS(.v26)],
                    products: [.library(name: "GlabKit", targets: ["GlabKit"])],
                    targets: [.target(name: "GlabKit")]
                )
                """,
            "Sources/App.swift":
                """
                import SwiftUI

                @main
                struct GlabFixtureApp: App {
                    var body: some Scene {
                        WindowGroup {
                            Text("Hello, GitLab")
                        }
                    }
                }
                """,
            "Sources/Repository/GitLabRepositoryView.swift":
                """
                import SwiftUI

                struct GitLabRepositoryView: View {
                    let projectName: String
                    let selectedBranch = "main"

                    var body: some View {
                        List {
                            Label(projectName, systemImage: "folder.fill")
                            Text("A deliberately long source line verifies that horizontal scrolling keeps the line-number gutter fixed while the code moves underneath it.")
                        }
                        .navigationTitle("Code")
                    }
                }
                """,
        ]

        private static func entry(
            _ name: String,
            parent: String = "",
            type: GitLabRepositoryEntryType
        ) -> GitLabRepositoryEntry {
            let path = parent.isEmpty
                ? name
                : "\(parent)/\(name)"
            return GitLabRepositoryEntry(
                id: "fixture-\(path)",
                name: name,
                type: type,
                path: path,
                mode: type == .tree
                    ? "040000"
                    : "100644"
            )
        }
    }

    private actor GitLabRepositoryFixtureImageLoader:
        GitLabMarkdownImageLoading
    {
        func image(
            _ request:
                GitLabMarkdownImageLoadRequest
        ) async throws -> GitLabMarkdownDecodedImage {
            let source = switch request.url.lastPathComponent {
            case "logo.svg":
                Self.logo
            case "pipeline.svg":
                Self.pipelineBadge
            case "license.svg":
                Self.licenseBadge
            case "community.svg":
                Self.communityBadge
            default:
                throw GitLabMarkdownImageError.invalidURL
            }
            return try await GitLabMarkdownImageDecoder.decode(
                Data(source.utf8),
                targetPixelWidth:
                    request.targetPixelWidth,
                maximumPixelCount: 2_000_000
            )
        }

        private static let logo =
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="640" height="240" viewBox="0 0 640 240">
              <rect width="640" height="240" rx="22" fill="#f6f7f9"/>
              <circle cx="210" cy="120" r="54" fill="#e24329"/>
              <path d="M180 120 L210 70 L240 120 L210 170 Z" fill="#fc6d26"/>
              <text x="286" y="140" font-family="Helvetica,Arial,sans-serif" font-size="72" font-weight="700" fill="#171321">glab</text>
            </svg>
            """

        private static let pipelineBadge =
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="132" height="28" viewBox="0 0 132 28">
              <rect width="66" height="28" rx="6" fill="#555"/>
              <rect x="66" width="66" height="28" rx="6" fill="#e05d44"/>
              <text x="8" y="19" font-family="Helvetica,Arial,sans-serif" font-size="13" fill="white">pipeline</text>
              <text x="78" y="19" font-family="Helvetica,Arial,sans-serif" font-size="13" fill="white">failed</text>
            </svg>
            """

        private static let licenseBadge =
            """
            <svg xmlns="http://www.w3.org/2000/svg" width="118" height="28" viewBox="0 0 118 28">
              <rect width="66" height="28" rx="6" fill="#555"/>
              <rect x="66" width="52" height="28" rx="6" fill="#1685c8"/>
              <text x="10" y="19" font-family="Helvetica,Arial,sans-serif" font-size="13" fill="white">license</text>
              <text x="78" y="19" font-family="Helvetica,Arial,sans-serif" font-size="13" fill="white">MIT</text>
            </svg>
            """

        private static let communityBadge: String = {
            let logo = Data(
                """
                <svg fill="#F03C2E" viewBox="0 0 24 24" xmlns="http://www.w3.org/2000/svg">
                  <title>Git</title>
                  <path d="M12 0 0 12l12 12 12-12L12 0Zm0 5 7 7-7 7-7-7 7-7Z"/>
                </svg>
                """.utf8
            )
            .base64EncodedString()
            return
                """
                <svg xmlns="http://www.w3.org/2000/svg" width="118" height="28" viewBox="0 0 118 28">
                  <rect width="118" height="28" rx="6" fill="#2da44e"/>
                  <image x="7" y="7" width="14" height="14" href="data:image/svg+xml;base64,\(logo)"/>
                  <text x="28" y="19" font-family="Helvetica,Arial,sans-serif" font-size="13" fill="white">PRs welcome</text>
                </svg>
                """
        }()
    }
#endif
