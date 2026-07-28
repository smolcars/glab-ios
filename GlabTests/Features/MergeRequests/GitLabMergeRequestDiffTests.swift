import Foundation
import Testing
@testable import Glab

@Suite("GitLab merge request diff contract")
struct GitLabMergeRequestDiffTests {
    @Test("Decodes current file metadata without losing paths or modes")
    func decodesCurrentDiffs() throws {
        let files = try decode(
            """
            [
              {
                "old_path": "Sources/Old.swift",
                "new_path": "Sources/New.swift",
                "a_mode": "100644",
                "b_mode": "100755",
                "diff": "@@ -1 +1 @@\\n-old\\n+new",
                "new_file": false,
                "renamed_file": true,
                "deleted_file": false,
                "generated_file": true,
                "collapsed": false,
                "too_large": false
              },
              {
                "old_path": "Assets/archive.bin",
                "new_path": "Assets/archive.bin",
                "a_mode": "100644",
                "b_mode": "100644",
                "diff": "",
                "new_file": false,
                "renamed_file": false,
                "deleted_file": false,
                "generated_file": false,
                "collapsed": true,
                "too_large": true
              }
            ]
            """
        )

        let renamed = try #require(files.first)
        #expect(
            renamed.id
                == GitLabMergeRequestDiffFileID(
                    oldPath: "Sources/Old.swift",
                    newPath: "Sources/New.swift"
                )
        )
        #expect(renamed.oldMode == "100644")
        #expect(renamed.newMode == "100755")
        #expect(renamed.isRenamedFile)
        #expect(renamed.isGeneratedFile)
        #expect(renamed.kind == .renamed)
        #expect(renamed.availability == .available)

        let unavailable = try #require(files.last)
        #expect(
            unavailable.availability
                == .tooLarge
        )
    }

    @Test("Defaults newer self-managed flags when absent")
    func decodesLegacyDiff() throws {
        let file = try #require(
            decode(
                """
                [
                  {
                    "old_path": "README.md",
                    "new_path": "README.md",
                    "a_mode": "100644",
                    "b_mode": "100644",
                    "diff": "@@ -1 +1 @@\\n-old\\n+new",
                    "new_file": false,
                    "renamed_file": false,
                    "deleted_file": false
                  }
                ]
                """
            ).first
        )

        #expect(!file.isGeneratedFile)
        #expect(!file.isCollapsed)
        #expect(!file.isTooLarge)
        #expect(file.availability == .available)
        #expect(file.kind == .modified)
    }

    @Test("Classifies a collapsed patch before its empty text")
    func identifiesCollapsedPatch() throws {
        let file = try #require(
            decode(
                """
                [
                  {
                    "old_path": "Sources/Large.swift",
                    "new_path": "Sources/Large.swift",
                    "diff": "",
                    "collapsed": true,
                    "too_large": false
                  }
                ]
                """
            ).first
        )

        #expect(
            file.availability
                == .collapsed
        )
    }

    @Test("Treats an unclassified empty patch honestly")
    func identifiesMissingText() throws {
        let file = try #require(
            decode(
                """
                [
                  {
                    "old_path": "image.png",
                    "new_path": "image.png",
                    "diff": ""
                  }
                ]
                """
            ).first
        )

        #expect(
            file.availability
                == .missingText
        )
    }

    @Test("Builds a stable privacy-safe row identifier")
    func privacySafeIdentifier() throws {
        let first = try #require(
            decode(
                """
                [
                  {
                    "old_path": "Secret/Old.swift",
                    "new_path": "Secret/New.swift",
                    "diff": "@@ -1 +1 @@\\n-old\\n+new"
                  }
                ]
                """
            ).first
        )
        let same = try #require(
            decode(
                """
                [
                  {
                    "old_path": "Secret/Old.swift",
                    "new_path": "Secret/New.swift",
                    "diff": "different"
                  }
                ]
                """
            ).first
        )
        let other = try #require(
            decode(
                """
                [
                  {
                    "old_path": "Public/File.swift",
                    "new_path": "Public/File.swift",
                    "diff": "different"
                  }
                ]
                """
            ).first
        )

        #expect(
            first.privacySafeIdentifier
                == same.privacySafeIdentifier
        )
        #expect(
            first.privacySafeIdentifier
                != other.privacySafeIdentifier
        )
        #expect(
            !first.privacySafeIdentifier
                .contains("Secret")
        )
        #expect(
            first.privacySafeIdentifier
                .hasPrefix("diff.file.")
        )
    }

    private func decode(
        _ json: String
    ) throws -> [GitLabMergeRequestDiffFile] {
        try JSONDecoder().decode(
            [GitLabMergeRequestDiffFile].self,
            from: Data(json.utf8)
        )
    }
}
