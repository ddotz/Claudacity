// MARK: - Imports
import Foundation
import SwiftData
import OSLog

// MARK: - Data Manager Protocol
@MainActor
protocol DataManagerProtocol {
    func createSession(name: String?) async throws -> Session
    func endCurrentSession() async throws
    func getCurrentSession() async throws -> Session?
    func getRecentSessions(limit: Int) async throws -> [Session]
    func updateSessionTokens(_ session: Session, input: Int64, output: Int64, cached: Int64) async throws

    func recordUsage(from usageData: UsageData) async throws
    func getUsageRecords(type: UsageRecord.RecordType, since: Date) async throws -> [UsageRecord]
    func cleanupOldRecords(olderThan days: Int) async throws
}

// MARK: - Data Manager
@MainActor
final class DataManager: DataManagerProtocol {
    // MARK: Properties
    private let modelContainer: ModelContainer
    private var modelContext: ModelContext {
        modelContainer.mainContext
    }

    // MARK: Configuration
    private static let maxRecordsToKeep = 1000
    private static let recordIntervalMinutes = 5

    // MARK: Initialization
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        logDebug("DataManager initialized", category: .data)
    }

    // MARK: Session Management
    func createSession(name: String? = nil) async throws -> Session {
        // End any existing active session
        try await endCurrentSession()

        // Create new session
        let existingCount = try await getSessionCount()
        let sessionName = name ?? Session.generateName(index: existingCount + 1)

        let session = Session(name: sessionName)
        modelContext.insert(session)

        try modelContext.save()
        logInfo("Created new session: \(sessionName)", category: .data)

        return session
    }

    func endCurrentSession() async throws {
        if let currentSession = try await getCurrentSession() {
            currentSession.end()
            try modelContext.save()
            logInfo("Ended session: \(currentSession.name)", category: .data)
        }
    }

    func getCurrentSession() async throws -> Session? {
        let descriptor = FetchDescriptor<Session>(
            predicate: #Predicate { $0.isActive },
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )

        let sessions = try modelContext.fetch(descriptor)
        return sessions.first
    }

    func getRecentSessions(limit: Int = 10) async throws -> [Session] {
        var descriptor = FetchDescriptor<Session>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit

        return try modelContext.fetch(descriptor)
    }

    func updateSessionTokens(_ session: Session, input: Int64, output: Int64, cached: Int64) async throws {
        session.updateTokens(input: input, output: output, cached: cached)
        try modelContext.save()
    }

    private func getSessionCount() async throws -> Int {
        let descriptor = FetchDescriptor<Session>()
        return try modelContext.fetchCount(descriptor)
    }

    // MARK: Usage Recording
    func recordUsage(from usageData: UsageData) async throws {
        // Check if we should record (avoid too frequent recording)
        if try await shouldSkipRecording(for: .session) {
            return
        }

        // Record all types
        for type in UsageRecord.RecordType.allCases {
            let record = UsageRecord(from: usageData, type: type)
            modelContext.insert(record)
        }

        try modelContext.save()
        logDebug("Recorded usage data", category: .data)

        // Cleanup old records periodically
        try await cleanupOldRecordsIfNeeded()
    }

    func getUsageRecords(type: UsageRecord.RecordType, since date: Date) async throws -> [UsageRecord] {
        let predicate = UsageRecord.predicate(for: type, since: date)
        let descriptor = FetchDescriptor<UsageRecord>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )

        return try modelContext.fetch(descriptor)
    }

    func cleanupOldRecords(olderThan days: Int = 30) async throws {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate = #Predicate<UsageRecord> { record in
            record.timestamp < cutoffDate
        }

        let descriptor = FetchDescriptor<UsageRecord>(predicate: predicate)
        let oldRecords = try modelContext.fetch(descriptor)

        for record in oldRecords {
            modelContext.delete(record)
        }

        if !oldRecords.isEmpty {
            try modelContext.save()
            logInfo("Cleaned up \(oldRecords.count) old records", category: .data)
        }
    }

    // MARK: Private Helpers
    private func shouldSkipRecording(for type: UsageRecord.RecordType) async throws -> Bool {
        let interval = TimeInterval(Self.recordIntervalMinutes * 60)
        let cutoffDate = Date().addingTimeInterval(-interval)

        let predicate = UsageRecord.predicate(for: type, since: cutoffDate)
        let descriptor = FetchDescriptor<UsageRecord>(predicate: predicate)
        let recentCount = try modelContext.fetchCount(descriptor)

        return recentCount > 0
    }

    private func cleanupOldRecordsIfNeeded() async throws {
        let descriptor = FetchDescriptor<UsageRecord>()
        let totalCount = try modelContext.fetchCount(descriptor)

        if totalCount > Self.maxRecordsToKeep {
            try await cleanupOldRecords(olderThan: 7)
        }
    }
}

// MARK: - Model Container Factory
enum DataManagerFactory {
    static func createModelContainer() throws -> ModelContainer {
        let schema = Schema([
            Session.self,
            UsageRecord.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }

    static func createInMemoryContainer() throws -> ModelContainer {
        let schema = Schema([
            Session.self,
            UsageRecord.self
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}
