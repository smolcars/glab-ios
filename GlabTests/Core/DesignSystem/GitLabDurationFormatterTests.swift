import Foundation
import Testing
@testable import Glab

@Suite("GitLab duration formatting")
struct GitLabDurationFormatterTests {
    @Test(
        "Formats compact pipeline durations",
        arguments: [
            (0.0, "0s"),
            (34.5, "35s"),
            (60.0, "1m"),
            (90.0, "1m 30s"),
            (3_600.0, "1h"),
            (3_661.0, "1h 1m"),
        ]
    )
    func formats(
        seconds: TimeInterval,
        expected: String
    ) {
        #expect(
            GitLabDurationFormatter.string(
                seconds: seconds
            ) == expected
        )
    }

    @Test("Rejects unusable durations")
    func rejectsInvalidValues() {
        #expect(
            GitLabDurationFormatter.string(
                seconds: -1
            ) == nil
        )
        #expect(
            GitLabDurationFormatter.string(
                seconds: .infinity
            ) == nil
        )
        #expect(
            GitLabDurationFormatter.string(
                seconds: .nan
            ) == nil
        )
    }
}
