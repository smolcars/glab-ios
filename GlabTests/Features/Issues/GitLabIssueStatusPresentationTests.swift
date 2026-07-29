import Testing
@testable import Glab

@Suite("GitLab issue status presentation")
struct GitLabIssueStatusPresentationTests {
    @Test(
        "Categories use compact semantic symbols",
        arguments: [
            (
                GitLabIssueStatusCategory.triage,
                "tray.full",
                GitLabIssueStatusTone.secondary
            ),
            (
                GitLabIssueStatusCategory.toDo,
                "circle",
                GitLabIssueStatusTone.secondary
            ),
            (
                GitLabIssueStatusCategory.inProgress,
                "circle.lefthalf.filled",
                GitLabIssueStatusTone.active
            ),
            (
                GitLabIssueStatusCategory.done,
                "checkmark.circle.fill",
                GitLabIssueStatusTone.complete
            ),
            (
                GitLabIssueStatusCategory.canceled,
                "xmark.circle.fill",
                GitLabIssueStatusTone.canceled
            ),
        ]
    )
    func categoryPresentation(
        category:
            GitLabIssueStatusCategory,
        systemImage: String,
        tone: GitLabIssueStatusTone
    ) {
        let presentation =
            GitLabIssueStatusPresentation(
                status:
                    makeStatus(
                        category: category
                    ),
                isStale: false
            )

        #expect(
            presentation.systemImage
                == systemImage
        )
        #expect(presentation.tone == tone)
        #expect(
            presentation
                .accessibilityLabel
                == "Work item status, Example"
        )
    }

    @Test("Missing and stale statuses are explicit")
    func fallbackPresentation() {
        let missing =
            GitLabIssueStatusPresentation(
                status: nil,
                isStale: false
            )
        #expect(missing.title == "Set status")
        #expect(
            missing.systemImage
                == "circle.dashed"
        )
        #expect(
            missing.accessibilityLabel
                == "Work item status not set"
        )

        let stale =
            GitLabIssueStatusPresentation(
                status:
                    makeStatus(
                        category: .inProgress
                    ),
                isStale: true
            )
        #expect(stale.isStale)
        #expect(
            stale.accessibilityLabel
                == "Work item status, Example, may be out of date"
        )
    }
}

private nonisolated func makeStatus(
    category:
        GitLabIssueStatusCategory
) -> GitLabIssueWorkItemStatus {
    GitLabIssueWorkItemStatus(
        id: "status-example",
        name: "Example",
        description: nil,
        iconName: nil,
        color: nil,
        position: 0,
        category: category
    )
}
