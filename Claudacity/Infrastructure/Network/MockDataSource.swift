// MARK: - Imports
import Foundation

// MARK: - Mock Data Source
final class MockDataSource: UsageDataSource, @unchecked Sendable {
    // MARK: Properties
    var mockUsage: UsageData?
    var mockError: Error?
    var fetchDelay: TimeInterval = 0.5
    private(set) var fetchCallCount = 0

    // MARK: UsageDataSource
    func fetchUsage() async throws -> UsageData {
        fetchCallCount += 1

        if fetchDelay > 0 {
            try await Task.sleep(nanoseconds: UInt64(fetchDelay * 1_000_000_000))
        }

        if let error = mockError {
            throw error
        }

        return mockUsage ?? .mock()
    }

    // MARK: Helpers
    func reset() {
        mockUsage = nil
        mockError = nil
        fetchCallCount = 0
        fetchDelay = 0.5
    }
}
