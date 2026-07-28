import Foundation

enum GitLabUnifiedDiffFixtures {
    static let representative = """
    diff --git a/Sources/Old.swift b/Sources/New.swift
    similarity index 92%
    --- a/Sources/Old.swift
    +++ b/Sources/New.swift
    @@ -2,3 +2,4 @@ struct Example {
     let first = 1
    -let old = 2
    +let new = 2
    +let extra = 3
     let last = 4
    \\ No newline at end of file
    @@ -10 +11,0 @@ extension Example {
    -let removed = true
    """

    static let oneThousandLines =
        makeContextPatch(lineCount: 1_000)

    static let tenThousandLines =
        makeContextPatch(lineCount: 10_000)

    static let fiftyThousandLines =
        makeContextPatch(lineCount: 50_000)

    private static func makeContextPatch(
        lineCount: Int
    ) -> String {
        precondition(lineCount > 1)
        var lines: [String] = []
        lines.reserveCapacity(lineCount)
        lines.append(
            "@@ -1,\(lineCount - 1) +1,\(lineCount - 1) @@"
        )

        for index in 1..<lineCount {
            lines.append(
                " let value\(index) = \(index)"
            )
        }
        return lines.joined(separator: "\n")
    }
}
