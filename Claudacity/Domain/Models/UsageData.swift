// MARK: - Imports
import Foundation

// MARK: - Usage Data
struct UsageData: Codable, Sendable, Equatable {
    let session: UsageLevel
    let daily: UsageLevel
    let weekly: UsageLevel
    let breakdown: TokenBreakdown
    let rate: RateLimit
    let updatedAt: Date

    static let empty = UsageData(
        session: .empty,
        daily: .empty,
        weekly: .empty,
        breakdown: .empty,
        rate: .empty,
        updatedAt: Date()
    )
}

// MARK: - Usage Level
struct UsageLevel: Codable, Sendable, Equatable {
    let used: Int64
    let limit: Int64
    let resetAt: Date

    var remaining: Int64 {
        max(0, limit - used)
    }

    var percentage: Double {
        guard limit > 0 else { return 0 }
        return Double(remaining) / Double(limit) * 100
    }

    var timeUntilReset: TimeInterval {
        resetAt.timeIntervalSinceNow
    }

    var formattedResetTime: String {
        let interval = timeUntilReset
        guard interval > 0 else { return "리셋됨" }

        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    static let empty = UsageLevel(used: 0, limit: 100000, resetAt: Date())
}

// MARK: - Token Breakdown
struct TokenBreakdown: Codable, Sendable, Equatable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cachedTokens: Int64

    var total: Int64 {
        inputTokens + outputTokens
    }

    static let empty = TokenBreakdown(inputTokens: 0, outputTokens: 0, cachedTokens: 0)
}

// MARK: - Rate Limit
struct RateLimit: Codable, Sendable, Equatable {
    let currentRPM: Int
    let limitRPM: Int

    static let empty = RateLimit(currentRPM: 0, limitRPM: 60)
}

// MARK: - Weekly Usage Level (2025년 8월 신규)
/// 주간 사용량 레벨 (모델별 분리)
struct WeeklyUsageLevel: Codable, Sendable, Equatable {
    let sonnetUsed: Int64        // Sonnet 4 사용량
    let opusUsed: Int64          // Opus 4 사용량 (Max 플랜만)
    let sonnetLimit: Int64       // Sonnet 주간 한도
    let opusLimit: Int64?        // Opus 주간 한도 (Max 플랜만)
    let resetAt: Date            // 주간 리셋 시간

    // MARK: - Computed Properties

    var totalUsed: Int64 { sonnetUsed + opusUsed }

    var sonnetRemaining: Int64 {
        max(0, sonnetLimit - sonnetUsed)
    }

    var opusRemaining: Int64? {
        guard let limit = opusLimit else { return nil }
        return max(0, limit - opusUsed)
    }

    /// Sonnet 잔여 퍼센트 (0-100)
    var sonnetPercentage: Double {
        guard sonnetLimit > 0 else { return 0 }
        return Double(sonnetRemaining) / Double(sonnetLimit) * 100
    }

    /// Opus 잔여 퍼센트 (0-100, Max 플랜만)
    var opusPercentage: Double? {
        guard let limit = opusLimit, limit > 0 else { return nil }
        guard let remaining = opusRemaining else { return nil }
        return Double(remaining) / Double(limit) * 100
    }

    var timeUntilReset: TimeInterval {
        resetAt.timeIntervalSinceNow
    }

    var formattedResetTime: String {
        let interval = timeUntilReset
        guard interval > 0 else { return "리셋됨" }

        let days = Int(interval) / 86400
        let hours = (Int(interval) % 86400) / 3600

        if days > 0 {
            return "\(days)d \(hours)h"
        } else {
            let minutes = (Int(interval) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    static let empty = WeeklyUsageLevel(
        sonnetUsed: 0,
        opusUsed: 0,
        sonnetLimit: 120_000,  // Pro 기본값 (60시간 × 2000 토큰)
        opusLimit: nil,
        resetAt: Date()
    )
}

// MARK: - Cache Statistics
/// 캐시 사용 통계
struct CacheStatistics: Codable, Sendable, Equatable {
    let creationTokens: Int64    // cache_creation_input_tokens 합계
    let readTokens: Int64        // cache_read_input_tokens 합계

    var totalCacheTokens: Int64 {
        creationTokens + readTokens
    }

    /// 캐시 히트율 (0-100%)
    /// rate limit에서 캐시 읽기로 절약된 비율
    var hitRate: Double {
        guard totalCacheTokens > 0 else { return 0 }
        return Double(readTokens) / Double(totalCacheTokens) * 100
    }

    /// Rate limit 절약률 (0-100%)
    /// 캐시 읽기 토큰은 rate limit에 포함되지 않으므로 절약됨
    var savingsPercentage: Double {
        hitRate  // 동일한 의미
    }

    /// 캐시로 절약된 토큰 수
    var tokensSaved: Int64 {
        readTokens
    }

    static let empty = CacheStatistics(creationTokens: 0, readTokens: 0)
}

// MARK: - Mock Data Extension
extension UsageData {
    static func mock(
        sessionPercentage: Double = 72,
        dailyPercentage: Double = 85,
        weeklyPercentage: Double = 91
    ) -> UsageData {
        let sessionLimit: Int64 = 100000
        let dailyLimit: Int64 = 500000
        let weeklyLimit: Int64 = 2000000

        return UsageData(
            session: UsageLevel(
                used: Int64(Double(sessionLimit) * (1 - sessionPercentage / 100)),
                limit: sessionLimit,
                resetAt: Date().addingTimeInterval(3600 * 3 + 60 * 24)
            ),
            daily: UsageLevel(
                used: Int64(Double(dailyLimit) * (1 - dailyPercentage / 100)),
                limit: dailyLimit,
                resetAt: Date().addingTimeInterval(3600 * 8)
            ),
            weekly: UsageLevel(
                used: Int64(Double(weeklyLimit) * (1 - weeklyPercentage / 100)),
                limit: weeklyLimit,
                resetAt: Date().addingTimeInterval(3600 * 24 * 3)
            ),
            breakdown: TokenBreakdown(
                inputTokens: 18000,
                outputTokens: 10000,
                cachedTokens: 5000
            ),
            rate: RateLimit(currentRPM: 12, limitRPM: 60),
            updatedAt: Date()
        )
    }
}
