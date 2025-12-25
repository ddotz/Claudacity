// MARK: - Imports
import Foundation
import SwiftData

// MARK: - Session Model
@Model
final class Session {
    // MARK: Properties
    @Attribute(.unique) var id: UUID
    var name: String
    var startTime: Date
    var endTime: Date?
    var tokensUsed: Int64
    var inputTokens: Int64
    var outputTokens: Int64
    var cachedTokens: Int64
    var isActive: Bool

    // MARK: Computed Properties
    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) % 3600 / 60
        if hours > 0 {
            return "\(hours)시간 \(minutes)분"
        }
        return "\(minutes)분"
    }

    var formattedStartTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: startTime)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd"
        return formatter.string(from: startTime)
    }

    var tokensPerMinute: Int {
        guard duration > 0 else { return 0 }
        return Int(Double(tokensUsed) / duration * 60)
    }

    // MARK: Initialization
    init(
        id: UUID = UUID(),
        name: String = "",
        startTime: Date = Date(),
        endTime: Date? = nil,
        tokensUsed: Int64 = 0,
        inputTokens: Int64 = 0,
        outputTokens: Int64 = 0,
        cachedTokens: Int64 = 0,
        isActive: Bool = true
    ) {
        self.id = id
        self.name = name
        self.startTime = startTime
        self.endTime = endTime
        self.tokensUsed = tokensUsed
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cachedTokens = cachedTokens
        self.isActive = isActive
    }

    // MARK: Methods
    func end() {
        endTime = Date()
        isActive = false
    }

    func updateTokens(input: Int64, output: Int64, cached: Int64) {
        inputTokens = input
        outputTokens = output
        cachedTokens = cached
        tokensUsed = input + output
    }
}

// MARK: - Session Extensions
extension Session {
    static func generateName(index: Int? = nil) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        let timeStr = formatter.string(from: Date())

        if let index = index {
            return "세션 #\(index) (\(timeStr))"
        }
        return "세션 \(timeStr)"
    }
}
