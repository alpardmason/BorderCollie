import Foundation

struct CursorQuotaService: UsageTrackingService {
    private let credentialResolver: CursorCredentialResolving
    private let usageClient: CursorUsageClient
    private let now: @Sendable () -> Date

    let toolID = "cursor"

    static let live = CursorQuotaService(
        credentialResolver: CursorCredentialResolver(),
        usageClient: CursorUsageClient()
    )

    init(
        credentialResolver: CursorCredentialResolving,
        usageClient: CursorUsageClient,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.credentialResolver = credentialResolver
        self.usageClient = usageClient
        self.now = now
    }

    func getSubscriptionQuota() async -> SubscriptionQuota {
        let credentials = credentialResolver.readCursorCredentials()

        switch credentials.status {
        case .notFound:
            return .notFound(tool: toolID)
        case .parseError:
            return .error(
                tool: toolID,
                status: .parseError,
                message: credentials.message ?? "Failed to parse Cursor credentials",
                now: now()
            )
        case .expired:
            return .error(
                tool: toolID,
                status: .expired,
                message: credentials.message ?? "Cursor credentials need refresh",
                now: now()
            )
        case .valid:
            guard let accessToken = credentials.accessToken else {
                return .error(
                    tool: toolID,
                    status: .parseError,
                    message: "Cursor access token is empty or missing",
                    now: now()
                )
            }

            return await usageClient.queryCursorQuota(accessToken: accessToken)
        }
    }
}
