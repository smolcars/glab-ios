import Testing
import UIKit
@testable import Glab

@Suite("GitLab icon assets")
struct GitLabIconTests {
    @Test(
        "Bundles every declared official GitLab icon",
        arguments: GitLabIcon.allCases
    )
    @MainActor
    func bundlesIcon(icon: GitLabIcon) {
        #expect(
            UIImage(named: icon.assetName) != nil,
            "Missing asset for \(icon.assetName)"
        )
    }

    @Test("Uses the upstream designed icon sizes")
    func usesDesignedSizes() {
        #expect(GitLabIcon.workItemIssue.designedPointSize == 16)
        #expect(GitLabIcon.pipelineSuccess.designedPointSize == 14)
    }

    @Test("Bundles the upstream license")
    func bundlesLicense() {
        #expect(
            Bundle.main.url(
                forResource: "GitLabSVGs-LICENSE",
                withExtension: "txt"
            ) != nil
        )
    }
}
