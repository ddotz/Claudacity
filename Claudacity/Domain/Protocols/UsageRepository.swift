// MARK: - Imports
import Foundation

// MARK: - Usage Repository Protocol
protocol UsageRepository: Sendable {
    func fetchUsage() async throws -> UsageData
    func getCachedUsage() -> UsageData?
}

// MARK: - Usage Data Source Protocol
protocol UsageDataSource: Sendable {
    func fetchUsage() async throws -> UsageData
}
