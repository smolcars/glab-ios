#if DEBUG
    import SwiftUI

    struct GitLabRepositoryFixtureView: View {
        private let loader =
            GitLabRepositoryFixtureLoader()
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
                # glab-ios

                A compact GitLab client for iPhone.

                - Browse branches and folders
                - Search repository files
                - Read syntax-highlighted source
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
#endif
