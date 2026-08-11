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
