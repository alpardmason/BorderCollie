import Foundation

enum UsageQuotaQueryError: Error, Equatable {
    case timedOut
}

enum UsageQuotaQuery {
    static func query(
        service: any UsageTrackingService,
        timeout: Duration = .seconds(20)
    ) async -> Result<SubscriptionQuota, UsageQuotaQueryError> {
        await withTaskGroup(of: Result<SubscriptionQuota, UsageQuotaQueryError>.self) { group in
            group.addTask {
                .success(await service.getSubscriptionQuota())
            }

            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return .failure(.timedOut)
                }

                return .failure(.timedOut)
            }

            let result = await group.next() ?? .failure(.timedOut)
            group.cancelAll()
            return result
        }
    }
}
