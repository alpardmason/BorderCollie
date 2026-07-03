import Foundation

struct CursorUsageClient: Sendable {
    private let httpClient: UsageHTTPClient
    private let endpoint: URL
    private let now: @Sendable () -> Date

    init(
        httpClient: UsageHTTPClient = URLSessionUsageHTTPClient(),
        endpoint: URL = URL(string: "https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.now = now
    }

    func queryCursorQuota(accessToken: String, toolLabel: String = "cursor") async -> SubscriptionQuota {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.setValue("Cursor", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await httpClient.data(for: request)
        } catch {
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .valid,
                message: "Network error: \(error.localizedDescription)",
                now: now()
            )
        }

        switch response.statusCode {
        case 200..<300:
            return decodeCurrentPeriodUsage(data, toolLabel: toolLabel)
        case 401, 403:
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .expired,
                message: "Authentication failed. Please sign in to Cursor again. (HTTP \(response.statusCode))",
                now: now()
            )
        default:
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .valid,
                message: "API error (HTTP \(response.statusCode)): \(bodyPreview(from: data))",
                now: now()
            )
        }
    }

    private func decodeCurrentPeriodUsage(_ data: Data, toolLabel: String) -> SubscriptionQuota {
        let usageResponse: CursorCurrentPeriodUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(CursorCurrentPeriodUsageResponse.self, from: data)
        } catch {
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .valid,
                message: "Failed to parse API response: \(error.localizedDescription)",
                now: now()
            )
        }

        guard let planUsage = usageResponse.planUsage else {
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .valid,
                message: "Cursor usage response did not include current plan usage.",
                now: now()
            )
        }

        let resetAt = Self.millisecondsStringToISO8601(usageResponse.billingCycleEnd)
        let tiers = [
            planUsage.autoPercentUsed.map {
                QuotaTier(name: CursorUsageLimitKind.autoComposer.rawValue, utilization: $0, resetsAt: resetAt)
            },
            planUsage.apiPercentUsed.map {
                QuotaTier(name: CursorUsageLimitKind.api.rawValue, utilization: $0, resetsAt: resetAt)
            },
        ].compactMap { $0 }

        return SubscriptionQuota(
            tool: toolLabel,
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: tiers,
            extraUsage: usageResponse.displayMessage,
            error: nil,
            queriedAt: now().millisecondsSince1970
        )
    }

    static func millisecondsStringToISO8601(_ value: String?) -> String? {
        guard
            let value,
            let milliseconds = Double(value),
            milliseconds >= 0
        else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: milliseconds / 1_000))
    }

    private func bodyPreview(from data: Data) -> String {
        let body = String(data: data, encoding: .utf8) ?? ""
        guard body.count > 300 else {
            return body
        }
        return "\(body.prefix(300))..."
    }
}

private struct CursorCurrentPeriodUsageResponse: Decodable {
    let billingCycleEnd: String?
    let planUsage: CursorPlanUsage?
    let displayMessage: String?
}

private struct CursorPlanUsage: Decodable {
    let autoPercentUsed: Double?
    let apiPercentUsed: Double?
}
