import Foundation
import Testing
@testable import Glab

@Suite("GitLab repository contract")
struct GitLabRepositoryTests {
    @Test("Decodes tree entry kinds without losing unknown values")
    func decodesTreeEntries() throws {
        let data = Data(
            """
            [
              {
                "id": "tree-sha",
                "name": "Sources",
                "type": "tree",
                "path": "Sources",
                "mode": "040000"
              },
              {
                "id": "blob-sha",
                "name": "App.swift",
                "type": "blob",
                "path": "Sources/App.swift",
                "mode": "100644"
              },
              {
                "id": "future-sha",
                "name": "Future",
                "type": "future_kind",
                "path": "Future",
                "mode": "000000"
              }
            ]
            """.utf8
        )

        let entries = try JSONDecoder()
            .decode(
                [GitLabRepositoryEntry].self,
                from: data
            )

        #expect(entries[0].isDirectory)
        #expect(entries[1].isFile)
        #expect(
            entries[2].type
                == .unknown("future_kind")
        )
    }

    @Test("Decodes branch and search presentation fields")
    func decodesBranchAndSearchResult() throws {
        let branch = try JSONDecoder()
            .decode(
                GitLabRepositoryBranch.self,
                from: Data(
                    """
                    {
                      "name": "main",
                      "default": true,
                      "protected": true,
                      "web_url": "https://gitlab.example.com/group/app/-/tree/main"
                    }
                    """.utf8
                )
            )
        let result = try JSONDecoder()
            .decode(
                GitLabRepositorySearchResult.self,
                from: Data(
                    """
                    {
                      "id": null,
                      "path": "Sources/App.swift",
                      "filename": "App.swift",
                      "ref": "main",
                      "startline": 12,
                      "project_id": 42
                    }
                    """.utf8
                )
            )

        #expect(branch.isDefault)
        #expect(branch.isProtected)
        #expect(branch.safeWebURL?.scheme == "https")
        #expect(result.displayName == "App.swift")
        #expect(result.parentPath == "Sources")
        #expect(result.startLine == 12)
    }

    @Test("Sorts folders before files and submodules")
    @MainActor
    func sortsRepositoryEntries() {
        let model = GitLabRepositoryDirectoryModel(
            loadPage: { _ in
                GitLabResourcePage(
                    items: [],
                    nextPageURL: nil
                )
            },
            identity: \GitLabRepositoryEntry.id,
            searchValues: { [$0.name] }
        )
        _ = model.reconcileItem(
            entry(
                id: "b",
                name: "z.swift",
                type: .blob
            )
        )
        _ = model.reconcileItem(
            entry(
                id: "c",
                name: "Vendor",
                type: .commit
            )
        )
        _ = model.reconcileItem(
            entry(
                id: "a",
                name: "Sources",
                type: .tree
            )
        )

        #expect(
            model.sortedRepositoryEntries
                .map(\.name)
                == [
                    "Sources",
                    "z.swift",
                    "Vendor",
                ]
        )
    }

    @Test("Pins the default branch before alphabetized branches")
    @MainActor
    func sortsRepositoryBranches() {
        let model = GitLabRepositoryBranchesModel(
            loadPage: { _ in
                GitLabResourcePage(
                    items: [],
                    nextPageURL: nil
                )
            },
            identity: \GitLabRepositoryBranch.name,
            searchValues: { [$0.name] }
        )
        _ = model.reconcileItem(
            branch(name: "release/2.0")
        )
        _ = model.reconcileItem(
            branch(name: "main", isDefault: true)
        )
        _ = model.reconcileItem(
            branch(name: "develop")
        )

        #expect(
            model.sortedRepositoryBranches
                .map(\.name)
                == [
                    "main",
                    "develop",
                    "release/2.0",
                ]
        )
    }

    @Test("Loads a paginated default branch into the first page")
    @MainActor
    func loadsPaginatedDefaultBranchFirst() async {
        let firstPage = (0..<100).map {
            branch(
                name: String(
                    format: "branch-%03d",
                    $0
                )
            )
        }
        let loader = RepositoryBranchLoaderStub(
            firstPage: firstPage,
            defaultBranch: branch(
                name: "z-main",
                isDefault: true
            )
        )
        let model = GitLabRepositoryBranchesModel(
            projectID: 42,
            defaultBranchName: "z-main",
            loader: loader
        )

        await model.loadIfNeeded()

        #expect(model.items.first?.name == "z-main")
        #expect(
            model.sortedRepositoryBranches.first?.name
                == "z-main"
        )
        #expect(model.items.count == 101)
    }

    private nonisolated func entry(
        id: String,
        name: String,
        type: GitLabRepositoryEntryType
    ) -> GitLabRepositoryEntry {
        GitLabRepositoryEntry(
            id: id,
            name: name,
            type: type,
            path: name,
            mode: "100644"
        )
    }

    private nonisolated func branch(
        name: String,
        isDefault: Bool = false
    ) -> GitLabRepositoryBranch {
        GitLabRepositoryBranch(
            name: name,
            isDefault: isDefault,
            isProtected: false,
            webURL: nil
        )
    }
}

private nonisolated struct RepositoryBranchLoaderStub:
    GitLabRepositoryBrowsing
{
    let firstPage: [GitLabRepositoryBranch]
    let defaultBranch: GitLabRepositoryBranch

    func loadTreePage(
        projectID: Int,
        ref: String,
        path: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryEntryPage
    {
        throw .api(.notFound)
    }

    func loadBranchesPage(
        projectID: Int,
        search: String?,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryBranchPage
    {
        GitLabRepositoryBranchPage(
            branches: firstPage,
            nextPageURL: URL(
                string:
                    "https://gitlab.example.com/api/v4/"
                    + "projects/42/repository/branches?page=2"
            )
        )
    }

    func loadBranch(
        projectID: Int,
        name: String
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositoryBranch
    {
        guard
            projectID == 42,
            name == defaultBranch.name
        else {
            throw .api(.notFound)
        }
        return defaultBranch
    }

    func loadSearchPage(
        projectID: Int,
        ref: String,
        query: String,
        after nextPageURL: URL?
    ) async throws(GitLabSessionClientError)
        -> GitLabRepositorySearchPage
    {
        throw .api(.notFound)
    }
}
