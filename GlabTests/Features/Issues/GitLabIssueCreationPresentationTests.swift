import Foundation
import Testing
@testable import Glab

@Suite("Issue creation presentation")
struct GitLabIssueCreationPresentationTests {
    @Test("Unknown delivery gives an explicit check action")
    func unknownDelivery() {
        let presentation =
            GitLabIssueCreationFailurePresentation(
                failure:
                    .deliveryCheckRequired
            )

        #expect(
            presentation.title
                == "Creation status unknown"
        )
        #expect(
            presentation.action
                == .confirmCheckedGitLab
        )
        #expect(
            presentation.message.contains(
                "Check the project"
            )
        )
    }

    @Test("Read-only failure never offers a write recovery action")
    func readOnly() {
        let presentation =
            GitLabIssueCreationFailurePresentation(
                failure: .readOnly
            )

        #expect(
            presentation.title
                == "Read-only account"
        )
        #expect(presentation.action == nil)
    }

    @Test("Project verification failure offers a safe read retry")
    func projectVerification() {
        let presentation =
            GitLabIssueCreationFailurePresentation(
                failure:
                    .projectVerification(
                        .api(
                            .connectivity(
                                .notConnectedToInternet
                            )
                        )
                    )
            )

        #expect(
            presentation.title
                == "Couldn’t verify project"
        )
        #expect(
            presentation.action
                == .retryProjectVerification
        )
    }

    @Test("Validation exposes the focused field message")
    func validation() {
        let presentation =
            GitLabIssueCreationFailurePresentation(
                failure:
                    .validation(.emptyTitle)
            )

        #expect(
            presentation.message
                == "Enter an issue title."
        )
        #expect(presentation.action == nil)
    }

    @Test("Due-date bridge preserves the selected calendar day")
    func dueDateBridge() throws {
        var calendar = Calendar(
            identifier: .gregorian
        )
        calendar.timeZone = try #require(
            TimeZone(
                secondsFromGMT:
                    -(5 * 60 * 60)
            )
        )
        let selected = try #require(
            calendar.date(
                from: DateComponents(
                    year: 2026,
                    month: 11,
                    day: 3,
                    hour: 18
                )
            )
        )

        let dueDate =
            GitLabIssueCreationDateBridge
                .dueDate(
                    from: selected,
                    calendar: calendar
                )

        #expect(
            dueDate
                == GitLabIssueDueDate(
                    year: 2026,
                    month: 11,
                    day: 3
                )
        )
        let restored = try #require(
            GitLabIssueCreationDateBridge
                .date(
                    from: dueDate,
                    calendar: calendar
                )
        )
        let restoredComponents =
            calendar.dateComponents(
                [.year, .month, .day],
                from: restored
            )
        #expect(restoredComponents.year == 2026)
        #expect(restoredComponents.month == 11)
        #expect(restoredComponents.day == 3)
    }
}
