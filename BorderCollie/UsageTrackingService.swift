import Foundation

protocol UsageTrackingService: Sendable {
    var toolID: String { get }

    func getSubscriptionQuota() async -> SubscriptionQuota
}

protocol UsageHTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionUsageHTTPClient: UsageHTTPClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

typealias CodexUsageHTTPClient = UsageHTTPClient
typealias URLSessionCodexUsageHTTPClient = URLSessionUsageHTTPClient
