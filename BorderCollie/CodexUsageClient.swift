import Foundation

struct CodexUsageClient: Sendable {
    private let httpClient: CodexUsageHTTPClient
    private let endpoint: URL
    private let now: @Sendable () -> Date

    init(
        httpClient: CodexUsageHTTPClient = URLSessionCodexUsageHTTPClient(),
        endpoint: URL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.httpClient = httpClient
        self.endpoint = endpoint
        self.now = now
    }

    func queryCodexQuota(
        accessToken: String,
        accountID: String?,
        toolLabel: String = "codex",
        expiredMessage: String = "Authentication failed. Please re-login with Codex CLI."
    ) async -> SubscriptionQuota {
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("codex-cli", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

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
            return decodeQuotaResponse(data, toolLabel: toolLabel)
        case 401, 403:
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .expired,
                message: "\(expiredMessage) (HTTP \(response.statusCode))",
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

    private func decodeQuotaResponse(_ data: Data, toolLabel: String) -> SubscriptionQuota {
        let usageResponse: CodexUsageResponse
        do {
            usageResponse = try JSONDecoder().decode(CodexUsageResponse.self, from: data)
        } catch {
            return SubscriptionQuota.error(
                tool: toolLabel,
                status: .valid,
                message: "Failed to parse API response: \(error.localizedDescription)",
                now: now()
            )
        }

        let windows = [
            usageResponse.rateLimit?.primaryWindow,
            usageResponse.rateLimit?.secondaryWindow,
        ]

        let tiers = windows.compactMap { window -> QuotaTier? in
            guard let window, let usedPercent = window.usedPercent else {
                return nil
            }

            let name = window.limitWindowSeconds
                .map(CodexUsageFormatting.windowSecondsToTierName)
                ?? "unknown"

            return QuotaTier(
                name: name,
                utilization: usedPercent,
                resetsAt: window.resetAt.flatMap(CodexUsageFormatting.unixTimestampToISO8601)
            )
        }

        return SubscriptionQuota(
            tool: toolLabel,
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: tiers,
            extraUsage: nil,
            error: nil,
            queriedAt: now().millisecondsSince1970
        )
    }

    private func bodyPreview(from data: Data) -> String {
        let body = String(data: data, encoding: .utf8) ?? ""
        guard body.count > 300 else {
            return body
        }
        return "\(body.prefix(300))..."
    }
}

private struct CodexUsageResponse: Decodable {
    let rateLimit: CodexRateLimit?

    enum CodingKeys: String, CodingKey {
        case rateLimit = "rate_limit"
    }
}

private struct CodexRateLimit: Decodable {
    let primaryWindow: CodexRateLimitWindow?
    let secondaryWindow: CodexRateLimitWindow?

    enum CodingKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }
}

private struct CodexRateLimitWindow: Decodable {
    let usedPercent: Double?
    let limitWindowSeconds: Int?
    let resetAt: Int?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case limitWindowSeconds = "limit_window_seconds"
        case resetAt = "reset_at"
    }
}
