import Foundation

enum CredentialStatus: String, Codable, Equatable, Sendable {
    case valid
    case expired
    case notFound = "not_found"
    case parseError = "parse_error"
}

struct QuotaTier: Codable, Equatable, Sendable, Identifiable {
    var id: String { name }

    let name: String
    let utilization: Double
    let resetsAt: String?
}

struct SubscriptionQuota: Codable, Equatable, Sendable {
    let tool: String
    let credentialStatus: CredentialStatus
    let credentialMessage: String?
    let success: Bool
    let tiers: [QuotaTier]
    let extraUsage: String?
    let error: String?
    let queriedAt: Int64?

    static func notFound(tool: String) -> SubscriptionQuota {
        SubscriptionQuota(
            tool: tool,
            credentialStatus: .notFound,
            credentialMessage: nil,
            success: false,
            tiers: [],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )
    }

    static func error(
        tool: String,
        status: CredentialStatus,
        message: String,
        now: Date = Date()
    ) -> SubscriptionQuota {
        SubscriptionQuota(
            tool: tool,
            credentialStatus: status,
            credentialMessage: message,
            success: false,
            tiers: [],
            extraUsage: nil,
            error: message,
            queriedAt: now.millisecondsSince1970
        )
    }
}

struct CodexCredentials: Equatable, Sendable {
    let accessToken: String?
    let accountID: String?
    let status: CredentialStatus
    let message: String?
}

enum CodexUsageFormatting {
    static func windowSecondsToTierName(_ seconds: Int) -> String {
        switch seconds {
        case 18_000:
            "five_hour"
        case 604_800:
            "seven_day"
        default:
            secondsToGenericTierName(seconds)
        }
    }

    static func unixTimestampToISO8601(_ timestamp: Int) -> String? {
        guard timestamp >= 0 else {
            return nil
        }

        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return iso8601Formatter.string(from: date)
    }

    static func countdownString(until resetsAt: String?, now: Date = Date()) -> String? {
        guard
            let resetsAt,
            let resetDate = ISO8601DateFormatter.codex.dateAllowingCodexFormats(from: resetsAt)
        else {
            return nil
        }

        let diffSeconds = Int(resetDate.timeIntervalSince(now))
        guard diffSeconds > 0 else {
            return nil
        }

        let hours = diffSeconds / 3_600
        let minutes = (diffSeconds % 3_600) / 60

        if hours > 24 {
            return "\(hours / 24)d\(hours % 24)h"
        }
        if hours > 0 {
            return "\(hours)h\(minutes)m"
        }
        return "\(minutes)m"
    }

    private static func secondsToGenericTierName(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        if hours >= 24 {
            return "\(hours / 24)_day"
        }
        return "\(hours)_hour"
    }

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }
}

extension ISO8601DateFormatter {
    static let codex: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let codexWithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    func dateAllowingCodexFormats(from string: String) -> Date? {
        date(from: string) ?? ISO8601DateFormatter.codexWithoutFractionalSeconds.date(from: string)
    }
}
