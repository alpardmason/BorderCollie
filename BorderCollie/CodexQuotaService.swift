import Foundation

struct CodexQuotaService: UsageTrackingService {
    private let credentialResolver: CodexCredentialResolving
    private let usageClient: CodexUsageClient
    private let now: @Sendable () -> Date

    let toolID = "codex"

    static let live = CodexQuotaService(
        credentialResolver: CodexCredentialResolver(),
        usageClient: CodexUsageClient()
    )

    init(
        credentialResolver: CodexCredentialResolving,
        usageClient: CodexUsageClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialResolver = credentialResolver
        self.usageClient = usageClient
        self.now = now
    }

    func getSubscriptionQuota() async -> SubscriptionQuota {
        let credentials = credentialResolver.readCodexCredentials()

        switch credentials.status {
        case .notFound:
            return .notFound(tool: toolID)
        case .parseError:
            return .error(
                tool: toolID,
                status: .parseError,
                message: credentials.message ?? "Failed to parse credentials",
                now: now()
            )
        case .expired:
            if let accessToken = credentials.accessToken {
                let result = await usageClient.queryCodexQuota(
                    accessToken: accessToken,
                    accountID: credentials.accountID
                )

                if result.success {
                    return result
                }
            }

            return .error(
                tool: toolID,
                status: .expired,
                message: credentials.message ?? "Codex OAuth token may be stale",
                now: now()
            )
        case .valid:
            guard let accessToken = credentials.accessToken else {
                return .error(
                    tool: toolID,
                    status: .parseError,
                    message: "access_token is empty or missing",
                    now: now()
                )
            }

            return await usageClient.queryCodexQuota(
                accessToken: accessToken,
                accountID: credentials.accountID
            )
        }
    }

    func getSubscriptionQuota(tool: String) async -> SubscriptionQuota {
        guard tool == toolID else {
            return .notFound(tool: tool)
        }

        return await getSubscriptionQuota()
    }
}
