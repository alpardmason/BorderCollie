import Combine
import Foundation

@MainActor
final class UsageTrackerViewModel: ObservableObject {
    @Published private(set) var quota: SubscriptionQuota?
    @Published private(set) var isLoading = false

    private let service: UsageTrackingService
    private var refreshTask: Task<Void, Never>?

    init(service: UsageTrackingService, initialQuota: SubscriptionQuota? = nil) {
        self.service = service
        self.quota = initialQuota
    }

    func refresh() {
        guard !isLoading else {
            return
        }

        isLoading = true

        refreshTask = Task { [service] in
            defer {
                isLoading = false
                refreshTask = nil
            }

            let result = await Self.queryQuotaWithTimeout(service: service)
            guard !Task.isCancelled else {
                return
            }

            switch result {
            case .success(let quota):
                self.quota = quota
            case .failure:
                self.quota = .error(
                    tool: service.toolID,
                    status: .valid,
                    message: "Quota query timed out. Try again in a moment.",
                    now: Date()
                )
            }
        }
    }

    private nonisolated static func queryQuotaWithTimeout(
        service: UsageTrackingService
    ) async -> Result<SubscriptionQuota, Error> {
        await withTaskGroup(of: Result<SubscriptionQuota, Error>.self) { group in
            group.addTask {
                .success(await service.getSubscriptionQuota())
            }

            group.addTask {
                do {
                    try await Task.sleep(for: .seconds(20))
                } catch {
                    return .failure(error)
                }

                return .failure(UsageTrackerRefreshError.timedOut)
            }

            let result = await group.next() ?? .failure(UsageTrackerRefreshError.timedOut)
            group.cancelAll()
            return result
        }
    }
}

private enum UsageTrackerRefreshError: Error {
    case timedOut
}
