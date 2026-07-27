import Foundation

nonisolated enum GitLabRelativeTimeFormatter {
    static func string(
        from date: Date,
        relativeTo referenceDate: Date = Date()
    ) -> String {
        let elapsed = max(
            0,
            referenceDate.timeIntervalSince(date)
        )

        switch elapsed {
        case ..<60:
            return "now"
        case ..<3_600:
            return "\(Int(elapsed / 60))m"
        case ..<86_400:
            return "\(Int(elapsed / 3_600))h"
        case ..<604_800:
            return "\(Int(elapsed / 86_400))d"
        case ..<31_536_000:
            return "\(Int(elapsed / 604_800))w"
        default:
            return "\(Int(elapsed / 31_536_000))y"
        }
    }
}

nonisolated enum GitLabIssueDateFormatter {
    static func dueDate(
        _ value: String,
        locale: Locale = .current
    ) -> String? {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = TimeZone(secondsFromGMT: 0)
        parser.dateFormat = "yyyy-MM-dd"
        parser.isLenient = false

        guard let date = parser.date(from: value) else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = locale
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}

nonisolated enum GitLabDescriptionFormatter {
    static func attributedString(_ value: String) -> AttributedString {
        let displayValue = valueWithoutTemplateComments(value)
            .split(
                separator: "\n",
                omittingEmptySubsequences: false
            )
        var isInsideCodeFence = false
        let valueWithoutCodeFences = displayValue
            .compactMap { line -> String? in
                if line.trimmingCharacters(
                    in: .whitespaces
                ).hasPrefix("```") {
                    isInsideCodeFence.toggle()
                    return nil
                }

                return isInsideCodeFence
                    ? String(line)
                    : valueWithoutHeadingMarker(String(line))
            }
            .joined(separator: "\n")
            .trimmingCharacters(
                in: .whitespacesAndNewlines
            )

        return (
            try? AttributedString(
                markdown: valueWithoutCodeFences,
                options: .init(
                    interpretedSyntax:
                        .inlineOnlyPreservingWhitespace
                )
            )
        )
            ?? AttributedString(valueWithoutCodeFences)
    }

    private static func valueWithoutTemplateComments(
        _ value: String
    ) -> String {
        guard
            let expression = try? NSRegularExpression(
                pattern: "<!--[\\s\\S]*?-->"
            )
        else {
            return value
        }

        return expression.stringByReplacingMatches(
            in: value,
            range: NSRange(
                value.startIndex..<value.endIndex,
                in: value
            ),
            withTemplate: ""
        )
    }

    private static func valueWithoutHeadingMarker(
        _ value: String
    ) -> String {
        let content = value.drop {
            $0.isWhitespace
        }
        let markerCount = content.prefix {
            $0 == "#"
        }.count

        guard
            (1...6).contains(markerCount),
            content.dropFirst(markerCount).first?
                .isWhitespace == true
        else {
            return value
        }

        return String(
            content
                .dropFirst(markerCount)
                .drop { $0.isWhitespace }
        )
    }
}
