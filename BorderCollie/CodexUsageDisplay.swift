import Foundation

enum UsageLimitResetStyle: Equatable, Sendable {
    case time
    case date
}

struct UsageLimitDisplay: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let tier: QuotaTier?
    let resetStyle: UsageLimitResetStyle

    var remainingPercentage: Double { remainingPercentage(from: tier?.utilization) }
    var resetsAt: String? { tier?.resetsAt }

    var percentageText: String {
        guard tier != nil else {
            return "--"
        }

        return "\(remainingPercentage.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    func resetText(timeZone: TimeZone = .current) -> String? {
        guard
            let resetsAt,
            let resetDate = ISO8601DateFormatter.codex.dateAllowingCodexFormats(from: resetsAt)
        else {
            return nil
        }

        switch resetStyle {
        case .time:
            return Self.timeFormatter(timeZone: timeZone).string(from: resetDate)
        case .date:
            return Self.dateFormatter(timeZone: timeZone).string(from: resetDate)
        }
    }

    private func remainingPercentage(from usedPercentage: Double?) -> Double {
        guard let usedPercentage else {
            return 0
        }

        return min(max(100 - usedPercentage, 0), 100)
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func dateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }
}

enum CodexUsageLimitKind: String, CaseIterable, Identifiable, Sendable {
    case fiveHour = "five_hour"
    case week = "seven_day"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour:
            "5h"
        case .week:
            "Weekly"
        }
    }
}

struct CodexUsageLimitDisplay: Identifiable, Equatable, Sendable {
    let kind: CodexUsageLimitKind
    let tier: QuotaTier?

    var id: String { kind.id }
    var title: String { kind.title }
    var remainingPercentage: Double { remainingPercentage(from: tier?.utilization) }
    var resetsAt: String? { tier?.resetsAt }

    var percentageText: String {
        guard tier != nil else {
            return "--"
        }

        return "\(remainingPercentage.formatted(.number.precision(.fractionLength(0...1))))%"
    }

    func resetText(timeZone: TimeZone = .current) -> String? {
        guard
            let resetsAt,
            let resetDate = ISO8601DateFormatter.codex.dateAllowingCodexFormats(from: resetsAt)
        else {
            return nil
        }

        switch kind {
        case .fiveHour:
            return Self.timeFormatter(timeZone: timeZone).string(from: resetDate)
        case .week:
            return Self.weekDateFormatter(timeZone: timeZone).string(from: resetDate)
        }
    }

    static func expectedLimits(from quota: SubscriptionQuota) -> [CodexUsageLimitDisplay] {
        CodexUsageLimitKind.allCases.map { kind in
            CodexUsageLimitDisplay(
                kind: kind,
                tier: quota.tiers.first { $0.name == kind.rawValue }
            )
        }
    }

    static func usageLimits(from quota: SubscriptionQuota) -> [UsageLimitDisplay] {
        expectedLimits(from: quota).map { limit in
            UsageLimitDisplay(
                id: limit.id,
                title: limit.title,
                tier: limit.tier,
                resetStyle: limit.kind == .fiveHour ? .time : .date
            )
        }
    }

    private func remainingPercentage(from usedPercentage: Double?) -> Double {
        guard let usedPercentage else {
            return 0
        }

        return min(max(100 - usedPercentage, 0), 100)
    }

    private static func timeFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }

    private static func weekDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate("MMM d")
        return formatter
    }
}
