import Foundation

enum CursorUsageLimitKind: String, CaseIterable, Identifiable, Sendable {
    case autoComposer = "cursor_auto_composer"
    case api = "cursor_api"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .autoComposer:
            "Auto + Composer"
        case .api:
            "API"
        }
    }
}

enum CursorUsageLimitDisplay {
    static func usageLimits(from quota: SubscriptionQuota) -> [UsageLimitDisplay] {
        CursorUsageLimitKind.allCases.map { kind in
            UsageLimitDisplay(
                id: kind.id,
                title: kind.title,
                tier: quota.tiers.first { $0.name == kind.rawValue },
                resetStyle: .date
            )
        }
    }
}
