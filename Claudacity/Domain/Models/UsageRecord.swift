// MARK: - Imports
import Foundation
import SwiftData

// MARK: - Usage Record Model
/// 시간별 사용량 기록 (통계 및 차트용)
@Model
final class UsageRecord {
    // MARK: Properties
    @Attribute(.unique) var id: UUID
    var timestamp: Date
    var usedTokens: Int64
    var limitTokens: Int64
    var inputTokens: Int64
    var outputTokens: Int64
    var cachedTokens: Int64
    var recordType: String  // "session", "daily", "weekly"

    // MARK: Computed Properties
    var percentage: Double {
        guard limitTokens > 0 else { return 0 }
        return Double(limitTokens - usedTokens) / Double(limitTokens) * 100
    }

    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: timestamp)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: timestamp)
    }

    var formattedDateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: timestamp)
    }

    // MARK: Initialization
    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        usedTokens: Int64 = 0,
        limitTokens: Int64 = 0,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cachedTokens: Int64 = 0,
        recordType: RecordType = .session
    ) {
        self.id = id
        self.timestamp = timestamp
        self.usedTokens = usedTokens
        self.limitTokens = limitTokens
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.recordType = recordType.rawValue
    }

    // MARK: Convenience Init
    convenience init(from usageData: UsageData, type: RecordType) {
        let level: UsageLevel
        switch type {
        case .session:
            level = usageData.session
        case .daily:
            level = usageData.daily
        case .weekly:
            level = usageData.weekly
        }

        self.init(
            timestamp: usageData.updatedAt,
            usedTokens: level.used,
            limitTokens: level.limit,
            inputTokens: usageData.breakdown.inputTokens,
            outputTokens: usageData.breakdown.outputTokens,
            cachedTokens: usageData.breakdown.cachedTokens,
            recordType: type
        )
    }
}

// MARK: - Record Type
extension UsageRecord {
    enum RecordType: String, Codable, CaseIterable {
        case session = "session"
        case daily = "daily"
        case weekly = "weekly"

        var displayName: String {
            switch self {
            case .session: return "세션"
            case .daily: return "일간"
            case .weekly: return "주간"
            }
        }
    }

    var type: RecordType {
        RecordType(rawValue: recordType) ?? .session
    }
}

// MARK: - Query Helpers
extension UsageRecord {
    static func predicate(for type: RecordType) -> Predicate<UsageRecord> {
        let typeString = type.rawValue
        return #Predicate<UsageRecord> { record in
            record.recordType == typeString
        }
    }

    static func predicate(since date: Date) -> Predicate<UsageRecord> {
        return #Predicate<UsageRecord> { record in
            record.timestamp >= date
        }
    }

    static func predicate(for type: RecordType, since date: Date) -> Predicate<UsageRecord> {
        let typeString = type.rawValue
        return #Predicate<UsageRecord> { record in
            record.recordType == typeString && record.timestamp >= date
        }
    }
}
