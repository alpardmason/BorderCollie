import Foundation
import Testing
@testable import BorderCollie

struct BorderCollieTests {
    @Test func mapsKnownAndUnknownQuotaWindows() {
        #expect(CodexUsageFormatting.windowSecondsToTierName(18_000) == "five_hour")
        #expect(CodexUsageFormatting.windowSecondsToTierName(604_800) == "seven_day")
        #expect(CodexUsageFormatting.windowSecondsToTierName(3_600) == "1_hour")
        #expect(CodexUsageFormatting.windowSecondsToTierName(172_800) == "2_day")
    }

    @Test func convertsUnixTimestampToISO8601() {
        #expect(CodexUsageFormatting.unixTimestampToISO8601(1_780_000_000) == "2026-05-28T20:26:40Z")
        #expect(CodexUsageFormatting.unixTimestampToISO8601(-1) == nil)
    }

    @Test func countdownParsesNormalizedResetTimestamp() {
        let now = ISO8601DateFormatter.codexWithoutFractionalSeconds.date(from: "2026-05-28T18:56:40Z")!

        #expect(
            CodexUsageFormatting.countdownString(
                until: "2026-05-28T20:26:40Z",
                now: now
            ) == "1h30m"
        )
    }

    @Test func codexUsageLimitDisplayShowsRemainingUsageAndResetText() {
        let quota = SubscriptionQuota(
            tool: "codex",
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: [
                QuotaTier(name: "seven_day", utilization: 40, resetsAt: "2026-07-07T12:00:00Z"),
                QuotaTier(name: "five_hour", utilization: 80, resetsAt: "2026-07-02T19:24:00Z"),
            ],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )

        let limits = CodexUsageLimitDisplay.expectedLimits(from: quota)

        #expect(limits.map(\.title) == ["5h", "Weekly"])
        #expect(limits.map(\.percentageText) == ["20%", "60%"])
        #expect(limits.map { $0.resetText(timeZone: TimeZone(secondsFromGMT: 0)!) } == ["7:24 PM", "Jul 7"])
    }

    @Test func cursorUsageLimitDisplayShowsMonthlyBuckets() {
        let quota = SubscriptionQuota(
            tool: "cursor",
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: [
                QuotaTier(name: "cursor_api", utilization: 0, resetsAt: "2026-07-30T03:12:17Z"),
                QuotaTier(name: "cursor_auto_composer", utilization: 1.25, resetsAt: "2026-07-30T03:12:17Z"),
            ],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )

        let limits = CursorUsageLimitDisplay.usageLimits(from: quota)

        #expect(limits.map(\.title) == ["Auto + Composer", "API"])
        #expect(limits.map(\.percentageText) == ["98.75%", "100%"])
        #expect(limits.map { $0.resetText(timeZone: TimeZone(secondsFromGMT: 0)!) } == ["Jul 30", "Jul 30"])
    }

    @Test func codexCompactSummaryShowsRemainingUsage() {
        let quota = SubscriptionQuota(
            tool: "codex",
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: [
                QuotaTier(name: "five_hour", utilization: 20, resetsAt: nil),
                QuotaTier(name: "seven_day", utilization: 10, resetsAt: nil),
            ],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )

        #expect(CodexUsageLimitDisplay.compactSummary(from: quota) == "5h: 80% | 7d: 90%")
    }

    @Test func cursorCompactSummaryShowsRemainingUsage() {
        let quota = SubscriptionQuota(
            tool: "cursor",
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: [
                QuotaTier(name: "cursor_api", utilization: 40, resetsAt: nil),
                QuotaTier(name: "cursor_auto_composer", utilization: 5, resetsAt: nil),
            ],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )

        #expect(CursorUsageLimitDisplay.compactSummary(from: quota) == "Auto: 95% | API: 60%")
    }

    @Test func compactSummaryHandlesMissingClampedAndRoundedTiers() {
        let codexQuota = SubscriptionQuota(
            tool: "codex",
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: [
                QuotaTier(name: "five_hour", utilization: 20.4, resetsAt: nil),
            ],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )
        let cursorQuota = SubscriptionQuota(
            tool: "cursor",
            credentialStatus: .valid,
            credentialMessage: nil,
            success: true,
            tiers: [
                QuotaTier(name: "cursor_auto_composer", utilization: -2, resetsAt: nil),
                QuotaTier(name: "cursor_api", utilization: 125, resetsAt: nil),
            ],
            extraUsage: nil,
            error: nil,
            queriedAt: nil
        )

        #expect(CodexUsageLimitDisplay.compactSummary(from: codexQuota) == "5h: 80% | 7d: --")
        #expect(CursorUsageLimitDisplay.compactSummary(from: cursorQuota) == "Auto: 100% | API: 0%")
    }

    @Test func credentialParserRejectsNonChatGPTOAuthMode() {
        let credentials = CodexCredentialResolver.parseCodexCredentialsJSON(
            """
            {
              "auth_mode": "api_key",
              "tokens": {
                "access_token": "token"
              }
            }
            """
        )

        #expect(credentials.status == .notFound)
        #expect(credentials.accessToken == nil)
    }

    @Test func credentialParserReportsMissingTokenAsParseError() {
        let credentials = CodexCredentialResolver.parseCodexCredentialsJSON(
            """
            {
              "auth_mode": "chatgpt",
              "tokens": {}
            }
            """
        )

        #expect(credentials.status == .parseError)
        #expect(credentials.message == "access_token is empty or missing")
    }

    @Test func credentialParserPreservesStaleTokenForOptimisticRemoteAttempt() {
        let now = ISO8601DateFormatter.codexWithoutFractionalSeconds.date(from: "2026-07-02T12:00:00Z")!
        let credentials = CodexCredentialResolver.parseCodexCredentialsJSON(
            """
            {
              "auth_mode": "chatgpt",
              "tokens": {
                "access_token": "token",
                "account_id": "acct_123"
              },
              "last_refresh": "2026-06-20T12:00:00Z"
            }
            """,
            now: now
        )

        #expect(credentials.status == .expired)
        #expect(credentials.accessToken == "token")
        #expect(credentials.accountID == "acct_123")
    }

    @Test func quotaClientNormalizesSuccessfulUsageResponse() async {
        let now = ISO8601DateFormatter.codexWithoutFractionalSeconds.date(from: "2026-07-02T12:00:00Z")!
        let httpClient = CapturingHTTPClient(
            statusCode: 200,
            body:
            """
            {
              "rate_limit": {
                "primary_window": {
                  "used_percent": 42.5,
                  "limit_window_seconds": 18000,
                  "reset_at": 1780000000
                },
                "secondary_window": {
                  "used_percent": 12.0,
                  "limit_window_seconds": 604800,
                  "reset_at": 1780500000
                }
              }
            }
            """
        )
        let client = CodexUsageClient(
            httpClient: httpClient,
            endpoint: URL(string: "https://example.test/usage")!,
            now: { now }
        )

        let quota = await client.queryCodexQuota(
            accessToken: "secret-token",
            accountID: "acct_123"
        )

        #expect(quota.success)
        #expect(quota.credentialStatus == .valid)
        #expect(quota.queriedAt == 1_782_993_600_000)
        #expect(quota.tiers == [
            QuotaTier(name: "five_hour", utilization: 42.5, resetsAt: "2026-05-28T20:26:40Z"),
            QuotaTier(name: "seven_day", utilization: 12.0, resetsAt: "2026-06-03T15:20:00Z"),
        ])

        let request = await httpClient.lastRequest()
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer secret-token")
        #expect(request?.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "acct_123")
        #expect(request?.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request?.timeoutInterval == 15)
    }

    @Test func quotaClientMapsUnauthorizedResponseToExpiredCredentials() async {
        let httpClient = CapturingHTTPClient(statusCode: 401, body: "{}")
        let client = CodexUsageClient(
            httpClient: httpClient,
            endpoint: URL(string: "https://example.test/usage")!,
            now: { Date(timeIntervalSince1970: 1_783_080_000) }
        )

        let quota = await client.queryCodexQuota(
            accessToken: "secret-token",
            accountID: nil
        )

        #expect(!quota.success)
        #expect(quota.credentialStatus == .expired)
        #expect(quota.error == "Authentication failed. Please re-login with Codex CLI. (HTTP 401)")
        #expect(quota.queriedAt == 1_783_080_000_000)
    }

    @Test func cursorCredentialResolverReadsTokenFromStateDatabase() {
        let resolver = CursorCredentialResolver(
            stateDatabaseURL: URL(fileURLWithPath: "/tmp/state.vscdb"),
            fileExists: { _ in true },
            databaseReader: { _ in "cursor-token\n" }
        )

        let credentials = resolver.readCursorCredentials()

        #expect(credentials.status == .valid)
        #expect(credentials.accessToken == "cursor-token")
    }

    @Test func cursorUsageClientNormalizesCurrentPeriodUsageResponse() async {
        let now = ISO8601DateFormatter.codexWithoutFractionalSeconds.date(from: "2026-07-03T12:00:00Z")!
        let httpClient = CapturingHTTPClient(
            statusCode: 200,
            body:
            """
            {
              "billingCycleStart": "1782807137000",
              "billingCycleEnd": "1785399137000",
              "planUsage": {
                "totalSpend": 55,
                "includedSpend": 55,
                "remaining": 6945,
                "limit": 7000,
                "autoPercentUsed": 0.1375,
                "apiPercentUsed": 0,
                "totalPercentUsed": 0.10784313725490195
              },
              "enabled": true,
              "displayMessage": "You've used 1% of your included usage"
            }
            """
        )
        let client = CursorUsageClient(
            httpClient: httpClient,
            endpoint: URL(string: "https://example.test/cursor")!,
            now: { now }
        )

        let quota = await client.queryCursorQuota(accessToken: "cursor-secret")

        #expect(quota.success)
        #expect(quota.credentialStatus == .valid)
        #expect(quota.queriedAt == 1_783_080_000_000)
        #expect(quota.extraUsage == "You've used 1% of your included usage")
        #expect(quota.tiers == [
            QuotaTier(name: "cursor_auto_composer", utilization: 0.1375, resetsAt: "2026-07-30T03:12:17Z"),
            QuotaTier(name: "cursor_api", utilization: 0, resetsAt: "2026-07-30T03:12:17Z"),
        ])

        let request = await httpClient.lastRequest()
        #expect(request?.httpMethod == "POST")
        #expect(request?.httpBody == Data("{}".utf8))
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer cursor-secret")
        #expect(request?.value(forHTTPHeaderField: "Connect-Protocol-Version") == "1")
        #expect(request?.timeoutInterval == 15)
    }

    @Test func cursorUsageClientMapsUnauthorizedResponseToExpiredCredentials() async {
        let httpClient = CapturingHTTPClient(statusCode: 403, body: "{}")
        let client = CursorUsageClient(
            httpClient: httpClient,
            endpoint: URL(string: "https://example.test/cursor")!,
            now: { Date(timeIntervalSince1970: 1_783_080_000) }
        )

        let quota = await client.queryCursorQuota(accessToken: "cursor-secret")

        #expect(!quota.success)
        #expect(quota.credentialStatus == .expired)
        #expect(quota.error == "Authentication failed. Please sign in to Cursor again. (HTTP 403)")
        #expect(quota.queriedAt == 1_783_080_000_000)
    }

    @Test func cursorQuotaServiceMapsMissingCredentials() async {
        let service = CursorQuotaService(
            credentialResolver: StubCursorCredentialResolver(
                credentials: CursorCredentials(accessToken: nil, status: .notFound, message: nil)
            ),
            usageClient: CursorUsageClient(
                httpClient: CapturingHTTPClient(statusCode: 200, body: "{}"),
                endpoint: URL(string: "https://example.test/cursor")!
            )
        )

        let quota = await service.getSubscriptionQuota()

        #expect(quota == .notFound(tool: "cursor"))
    }

    @MainActor
    @Test func menuBarViewModelRefreshesAgentsConcurrentlyInFixedOrder() async {
        let probe = RefreshConcurrencyProbe()
        let codexService = StubUsageTrackingService(
            toolID: "codex",
            quota: SubscriptionQuota(
                tool: "codex",
                credentialStatus: .valid,
                credentialMessage: nil,
                success: true,
                tiers: [
                    QuotaTier(name: "five_hour", utilization: 20, resetsAt: nil),
                    QuotaTier(name: "seven_day", utilization: 10, resetsAt: nil),
                ],
                extraUsage: nil,
                error: nil,
                queriedAt: nil
            ),
            onQuery: {
                await probe.enter()
                try? await Task.sleep(for: .milliseconds(50))
                await probe.leave()
            }
        )
        let cursorService = StubUsageTrackingService(
            toolID: "cursor",
            quota: .notFound(tool: "cursor"),
            onQuery: {
                await probe.enter()
                try? await Task.sleep(for: .milliseconds(50))
                await probe.leave()
            }
        )
        let viewModel = MenuBarUsageViewModel(
            agents: [
                .codex(service: codexService),
                .cursor(service: cursorService),
            ]
        )

        await viewModel.refresh()

        #expect(await probe.maxRunningCount() == 2)
        #expect(viewModel.rows.map(\.title) == ["Codex", "Cursor"])
        #expect(viewModel.rows.map(\.detail) == ["5h: 80% | 7d: 90%", "Sign in required"])
        #expect(viewModel.rows.map(\.state) == [.success, .unavailable])
    }

    @MainActor
    @Test func menuBarViewModelPreservesRowsAndSkipsOverlappingRefresh() async {
        let serviceState = CountingUsageServiceState(
            quota: SubscriptionQuota(
                tool: "codex",
                credentialStatus: .valid,
                credentialMessage: nil,
                success: true,
                tiers: [
                    QuotaTier(name: "five_hour", utilization: 25, resetsAt: nil),
                    QuotaTier(name: "seven_day", utilization: 15, resetsAt: nil),
                ],
                extraUsage: nil,
                error: nil,
                queriedAt: nil
            )
        )
        let viewModel = MenuBarUsageViewModel(
            agents: [
                .codex(service: CountingUsageTrackingService(toolID: "codex", state: serviceState)),
            ],
            initialRows: [
                MenuBarUsageRow(id: "codex", title: "Codex", detail: "5h: 80% | 7d: 90%", state: .success),
            ]
        )

        let refreshTask = Task { @MainActor in
            await viewModel.refresh()
        }
        while !viewModel.isRefreshing {
            await Task.yield()
        }

        #expect(viewModel.rows.first?.detail == "5h: 80% | 7d: 90%")

        await viewModel.refresh()
        await refreshTask.value

        #expect(await serviceState.callCount() == 1)
        #expect(viewModel.rows.first?.detail == "5h: 75% | 7d: 85%")
    }

    @MainActor
    @Test func menuBarViewModelMapsUnsuccessfulQuotaStates() async {
        let viewModel = MenuBarUsageViewModel(
            agents: [
                .codex(service: StubUsageTrackingService(toolID: "missing", quota: .notFound(tool: "missing"))),
                .codex(
                    service: StubUsageTrackingService(
                        toolID: "expired",
                        quota: .error(tool: "expired", status: .expired, message: "expired")
                    )
                ),
                .codex(
                    service: StubUsageTrackingService(
                        toolID: "parse",
                        quota: .error(tool: "parse", status: .parseError, message: "parse")
                    )
                ),
                .codex(
                    service: StubUsageTrackingService(
                        toolID: "valid-failure",
                        quota: .error(tool: "valid-failure", status: .valid, message: "remote")
                    )
                ),
            ]
        )

        await viewModel.refresh()

        #expect(viewModel.rows.map(\.detail) == [
            "Sign in required",
            "Sign in again",
            "Credential issue",
            "Query failed",
        ])
    }
}

private actor CapturingHTTPClient: CodexUsageHTTPClient {
    private var requests: [URLRequest] = []
    private let statusCode: Int
    private let body: String

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: nil
        )!
        return (Data(body.utf8), response)
    }

    func lastRequest() -> URLRequest? {
        requests.last
    }
}

private struct StubCursorCredentialResolver: CursorCredentialResolving {
    let credentials: CursorCredentials

    func readCursorCredentials() -> CursorCredentials {
        credentials
    }
}

private struct StubUsageTrackingService: UsageTrackingService {
    let toolID: String
    let quota: SubscriptionQuota
    var onQuery: (@Sendable () async -> Void)?

    func getSubscriptionQuota() async -> SubscriptionQuota {
        if let onQuery {
            await onQuery()
        }

        return quota
    }
}

private actor RefreshConcurrencyProbe {
    private var runningCount = 0
    private var maxRunning = 0

    func enter() {
        runningCount += 1
        maxRunning = max(maxRunning, runningCount)
    }

    func leave() {
        runningCount -= 1
    }

    func maxRunningCount() -> Int {
        maxRunning
    }
}

private actor CountingUsageServiceState {
    private let quota: SubscriptionQuota
    private var queries = 0

    init(quota: SubscriptionQuota) {
        self.quota = quota
    }

    func query() async -> SubscriptionQuota {
        queries += 1
        try? await Task.sleep(for: .milliseconds(50))
        return quota
    }

    func callCount() -> Int {
        queries
    }
}

private struct CountingUsageTrackingService: UsageTrackingService {
    let toolID: String
    let state: CountingUsageServiceState

    func getSubscriptionQuota() async -> SubscriptionQuota {
        await state.query()
    }
}
