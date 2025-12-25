// MARK: - Imports
import Foundation
import OSLog

// MARK: - Usage Repository Implementation
final class UsageRepositoryImpl: UsageRepository, @unchecked Sendable {
    // MARK: Properties
    private let dataSource: UsageDataSource
    private var cachedUsage: UsageData?
    private let lock = NSLock()

    // MARK: Init
    init(dataSource: UsageDataSource) {
        self.dataSource = dataSource
        logDebug("UsageRepositoryImpl initialized", category: .repository)
    }

    // MARK: UsageRepository
    func fetchUsage() async throws -> UsageData {
        logDebug("Fetching usage from data source...", category: .repository)
        let data = try await dataSource.fetchUsage()
        cache(data)
        logInfo("Usage fetched and cached successfully", category: .repository)
        return data
    }

    func getCachedUsage() -> UsageData? {
        lock.lock()
        defer { lock.unlock() }
        if cachedUsage != nil {
            logDebug("Returning cached usage data", category: .repository)
        }
        return cachedUsage
    }

    // MARK: Private Methods
    private func cache(_ data: UsageData) {
        lock.lock()
        defer { lock.unlock() }
        cachedUsage = data
    }
}
