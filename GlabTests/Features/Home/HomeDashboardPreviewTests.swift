import Foundation
import Testing
@testable import Glab

@Suite("Home dashboard preview")
struct HomeDashboardPreviewTests {
    @Test("Merges scopes by recency and removes overlapping work")
    func mergesScopes() {
        let oldest = item(
            id: "merge-request:1:1",
            title: "Oldest",
            seconds: 1
        )
        let overlap = item(
            id: "merge-request:1:2",
            title: "Overlap",
            seconds: 2
        )
        let newest = item(
            id: "merge-request:1:3",
            title: "Newest",
            seconds: 3
        )
        let fourth = item(
            id: "merge-request:1:4",
            title: "Fourth",
            seconds: 4
        )

        let preview = HomeDashboardPreview.merge(
            [
                [oldest, overlap],
                [overlap, newest],
                [fourth],
            ],
            limit: 3
        )

        #expect(
            preview.map(\.title)
                == ["Fourth", "Newest", "Overlap"]
        )
    }

    private func item(
        id: String,
        title: String,
        seconds: TimeInterval
    ) -> GitLabHomeWorkItem {
        GitLabHomeWorkItem(
            id: id,
            title: title,
            detail: id,
            webURL: nil,
            updatedAt:
                Date(
                    timeIntervalSince1970:
                        seconds
                )
        )
    }
}
