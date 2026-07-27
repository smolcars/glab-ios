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

