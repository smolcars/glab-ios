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

nonisolated enum GitLabDurationFormatter {
    static func string(
        seconds: TimeInterval
    ) -> String? {
        guard
            seconds.isFinite,
            seconds >= 0
        else {
            return nil
        }

        let roundedSeconds =
            Int(seconds.rounded())
        if roundedSeconds < 60 {
            return "\(roundedSeconds)s"
        }

        let minutes =
            roundedSeconds / 60
        let remainingSeconds =
            roundedSeconds % 60
        if minutes < 60 {
            return remainingSeconds == 0
                ? "\(minutes)m"
                : "\(minutes)m \(remainingSeconds)s"
        }

        let hours = minutes / 60
        let remainingMinutes =
            minutes % 60
        return remainingMinutes == 0
            ? "\(hours)h"
            : "\(hours)h \(remainingMinutes)m"
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
