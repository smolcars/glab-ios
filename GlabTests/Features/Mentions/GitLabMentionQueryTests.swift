import Foundation
import Testing
@testable import Glab

@Suite("GitLab mention query")
struct GitLabMentionQueryTests {
    @Test("Recognizes an empty or partial mention")
    func recognizesActiveMentions() throws {
        let empty = "@"
        let emptyQuery = try #require(
            GitLabMentionQuery.active(
                in: empty,
                selection:
                    insertionRange(
                        in: empty,
                        offset: empty.count
                    )
            )
        )
        #expect(emptyQuery.query.isEmpty)

        let partial =
            "First line\nHello, @nitesh"
        let partialQuery = try #require(
            GitLabMentionQuery.active(
                in: partial,
                selection:
                    insertionRange(
                        in: partial,
                        offset:
                            partial.count
                    )
            )
        )
        #expect(partialQuery.query == "nitesh")
        #expect(
            partial[
                partialQuery
                    .replacementRange
            ] == "@nitesh"
        )
    }

    @Test("Rejects email, path, escape, and selected text")
    func rejectsFalsePositives() {
        for text in [
            "person@example",
            "docs/@example",
            "\\@example",
            "name.@example",
        ] {
            #expect(
                GitLabMentionQuery.active(
                    in: text,
                    selection:
                        insertionRange(
                            in: text,
                            offset: text.count
                        )
                ) == nil
            )
        }

        let selected = "Hello @example"
        let start =
            selected.index(
                selected.startIndex,
                offsetBy: 6
            )
        #expect(
            GitLabMentionQuery.active(
                in: selected,
                selection:
                    start ..< selected.endIndex
            ) == nil
        )
    }

    @Test("Completing from the middle replaces the whole username")
    func replacesWholeUsername() throws {
        let text = "Hi @ali-cat, welcome"
        let query = try #require(
            GitLabMentionQuery.active(
                in: text,
                selection:
                    insertionRange(
                        in: text,
                        offset: 7
                    )
            )
        )
        #expect(query.query == "ali")

        let insertion = try #require(
            query.inserting(
                username: "alice",
                into: text
            )
        )
        #expect(
            insertion.text
                == "Hi @alice, welcome"
        )
        #expect(
            insertion.cursor
                == insertion.text.index(
                    insertion.text.startIndex,
                    offsetBy: 9
                )
        )
    }

    @Test("Insertion is Unicode safe and adds a trailing space at the end")
    func insertsAfterUnicodePrefix() throws {
        let text = "👩🏽‍💻 Hi @ni"
        let query = try #require(
            GitLabMentionQuery.active(
                in: text,
                selection:
                    insertionRange(
                        in: text,
                        offset: text.count
                    )
            )
        )
        let insertion = try #require(
            query.inserting(
                username: "nitesh.dev",
                into: text
            )
        )

        #expect(
            insertion.text
                == "👩🏽‍💻 Hi @nitesh.dev "
        )
        #expect(
            insertion.cursor
                == insertion.text.endIndex
        )
    }

    @Test("Rejects invalid returned usernames")
    func rejectsInvalidUsername() throws {
        let text = "@bad"
        let query = try #require(
            GitLabMentionQuery.active(
                in: text,
                selection:
                    insertionRange(
                        in: text,
                        offset: text.count
                    )
            )
        )

        #expect(
            query.inserting(
                username: "-invalid",
                into: text
            ) == nil
        )
        #expect(
            query.inserting(
                username: "invalid-",
                into: text
            ) == nil
        )
    }

    private func insertionRange(
        in text: String,
        offset: Int
    ) -> Range<String.Index> {
        let index =
            text.index(
                text.startIndex,
                offsetBy: offset
            )
        return index ..< index
    }
}
