import Foundation
import Testing
@testable import Glab

@MainActor
@Suite("GitLab incoming-link model")
struct GitLabIncomingLinkModelTests {
    @Test("Stores only an extracted HTTPS target until it is cleared")
    func retainsValidatedTarget() throws {
        let model = GitLabIncomingLinkModel()
        let target = try #require(
            URL(
                string:
                    "https://gitlab.example.com/"
                    + "group/project"
            )
        )
        let wrapper = try #require(
            URL(
                string:
                    "glab://open?url=https%3A%2F%2F"
                    + "gitlab.example.com%2Fgroup%2Fproject"
            )
        )
        let invalid = try #require(
            URL(
                string:
                    "glab://open?url=http%3A%2F%2F"
                    + "gitlab.example.com%2Fgroup%2Fproject"
            )
        )

        #expect(model.receive(wrapper))
        #expect(model.pendingURL == target)
        #expect(!model.receive(invalid))
        #expect(model.pendingURL == target)

        model.clear()
        #expect(model.pendingURL == nil)
    }
}
