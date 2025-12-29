// MARK: - Imports
import Foundation
import OSLog

// MARK: - Usage Aggregator Implementation
/// 기간별 사용량 집계를 담당하는 구현체
final class UsageAggregatorImpl: UsageAggregator {
    // MARK: Properties
    private let calendar = Calendar.current
    private let logger = Logger(subsystem: "com.claudacity.app", category: "UsageAggregator")

    // MARK: - UsageAggregator Protocol

    func aggregate(entries: [ClaudeLogEntry], period: DateInterval) -> AggregatedUsage {
        let filtered = entries.filter { entry in
            guard let timestamp = entry.timestamp else { return false }
            return period.contains(timestamp)
        }

        var totalInput: Int64 = 0
        var totalOutput: Int64 = 0
        var totalCacheCreation: Int64 = 0
        var totalCacheRead: Int64 = 0
        var count = 0

        for entry in filtered {
            if let usage = entry.usage {
                totalInput += usage.inputTokens
                totalOutput += usage.outputTokens
                totalCacheCreation += usage.cacheCreationInputTokens ?? 0
                totalCacheRead += usage.cacheReadInputTokens ?? 0
                count += 1
            }
        }

        return AggregatedUsage(
            inputTokens: totalInput,
            outputTokens: totalOutput,
            cacheCreationTokens: totalCacheCreation,
            cacheReadTokens: totalCacheRead,
            period: period,
            entryCount: count
        )
    }

    func aggregateCurrentWindow(entries: [ClaudeLogEntry]) -> AggregatedUsage {
        // 5시간 윈도우 계산
        // Claude의 리셋 시간을 정확히 알 수 없으므로, 가장 최근 5시간 기준
        let now = Date()
        let windowStart = now.addingTimeInterval(-SubscriptionPlan.sessionResetInterval)
        let period = DateInterval(start: windowStart, end: now)

        return aggregate(entries: entries, period: period)
    }

    func aggregateToday(entries: [ClaudeLogEntry]) -> AggregatedUsage {
        let now = Date()
        guard let startOfDay = calendar.startOfDay(for: now) as Date?,
              let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else {
            return .empty
        }

        let period = DateInterval(start: startOfDay, end: endOfDay)
        return aggregate(entries: entries, period: period)
    }

    func aggregateThisWeek(entries: [ClaudeLogEntry]) -> AggregatedUsage {
        let now = Date()
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now) else {
            return .empty
        }

        return aggregate(entries: entries, period: weekInterval)
    }

    // MARK: - 주간 한도 관련 (2025년 8월 신규)

    func aggregateRollingWeek(entries: [ClaudeLogEntry]) -> AggregatedUsage {
        // 롤링 7일 윈도우 계산 (주간 한도용)
        let now = Date()
        let weekStart = now.addingTimeInterval(-SubscriptionPlan.weeklyResetInterval)
        let period = DateInterval(start: weekStart, end: now)

        logger.debug("Rolling week aggregation: \(weekStart) to \(now)")
        return aggregate(entries: entries, period: period)
    }

    func nextWeeklyReset() -> Date {
        // Claude 주간 한도는 매주 월요일 00:00 UTC에 리셋됨 (추정)
        let now = Date()
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(identifier: "UTC")!

        // 현재 주의 다음 월요일 찾기
        var components = utcCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)
        components.weekday = 2  // 월요일
        components.hour = 0
        components.minute = 0
        components.second = 0

        if let nextMonday = utcCalendar.date(from: components) {
            // 이미 이번 주 월요일이 지났다면 다음 주 월요일로
            if nextMonday <= now {
                return utcCalendar.date(byAdding: .weekOfYear, value: 1, to: nextMonday) ?? now.addingTimeInterval(SubscriptionPlan.weeklyResetInterval)
            }
            return nextMonday
        }

        // Fallback: 현재 시간 + 7일
        return now.addingTimeInterval(SubscriptionPlan.weeklyResetInterval)
    }

    func nextSessionReset(from lastActivity: Date?) -> Date {
        // 5시간 세션 리셋 시간 계산
        // 마지막 활동 시점이 없으면 현재 시간 기준
        let baseTime = lastActivity ?? Date()
        return baseTime.addingTimeInterval(SubscriptionPlan.sessionResetInterval)
    }

    // MARK: - Additional Helpers

    /// 특정 프로젝트의 사용량 집계
    func aggregateByProject(entries: [ClaudeLogEntry]) -> [String: AggregatedUsage] {
        var projectUsage: [String: [ClaudeLogEntry]] = [:]

        for entry in entries {
            let project = entry.projectPath ?? "unknown"
            projectUsage[project, default: []].append(entry)
        }

        var result: [String: AggregatedUsage] = [:]
        for (project, projectEntries) in projectUsage {
            let period = DateInterval(
                start: projectEntries.compactMap { $0.timestamp }.min() ?? Date(),
                end: projectEntries.compactMap { $0.timestamp }.max() ?? Date()
            )
            result[project] = aggregate(entries: projectEntries, period: period)
        }

        return result
    }

    /// 시간대별 사용량 집계 (차트용) - 최적화된 O(N) 버전
    /// 시간대별 사용량 집계를 담당하는 구현체 (bucketHours 단위 지원)
    func aggregateHourly(entries: [ClaudeLogEntry], hours: Int = 24, bucketHours: Int = 1) -> [Date: AggregatedUsage] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let now = Date()
        var result: [Date: AggregatedUsage] = [:]

        // 시간대별 누적기 초기화
        struct HourlyAccumulator {
            var inputTokens: Int64 = 0
            var outputTokens: Int64 = 0
            var cacheCreationTokens: Int64 = 0
            var cacheReadTokens: Int64 = 0
            var entryCount: Int = 0
        }
        var accumulators: [Date: HourlyAccumulator] = [:]

        // 시간대 키 미리 계산 (bucketHours 단위)
        var hourKeys: [Date] = []

        // 기준 시간을 bucketHours 단위로 절삭
        let currentComponents = calendar.dateComponents([.year, .month, .day, .hour], from: now)
        let currentHour = currentComponents.hour ?? 0
        let truncatedHour = (currentHour / bucketHours) * bucketHours

        var baseComponents = currentComponents
        baseComponents.hour = truncatedHour
        baseComponents.minute = 0
        baseComponents.second = 0

        guard let baseDate = calendar.date(from: baseComponents) else { return [:] }

        logger.debug("[버킷] 현재 시간: \(now), 기준 시간: \(baseDate)")

        for offset in 0..<(hours / bucketHours) {
            if let bucketStart = calendar.date(byAdding: .hour, value: -offset * bucketHours, to: baseDate) {
                hourKeys.append(bucketStart)
                accumulators[bucketStart] = HourlyAccumulator()
            }
        }

        // 윈도우 시작 시간
        guard let windowStart = hourKeys.min() else {
            return result
        }

        logger.debug("[버킷] 윈도우 시작: \(windowStart), 종료: \(now), 버킷 개수: \(hourKeys.count)")
        
        // 단일 순회로 모든 엔트리 집계
        for entry in entries {
            guard let timestamp = entry.timestamp,
                  timestamp >= windowStart,
                  let usage = entry.usage else { continue }
            
            // 해당 타임스탬프가 속하는 버킷 찾기
            let tComponents = calendar.dateComponents([.year, .month, .day, .hour], from: timestamp)
            let tHour = tComponents.hour ?? 0
            let tTruncatedHour = (tHour / bucketHours) * bucketHours
            
            var tBaseComponents = tComponents
            tBaseComponents.hour = tTruncatedHour
            tBaseComponents.minute = 0
            tBaseComponents.second = 0
            
            guard let bucketStart = calendar.date(from: tBaseComponents) else { continue }
            
            if accumulators[bucketStart] != nil {
                accumulators[bucketStart]!.inputTokens += usage.inputTokens
                accumulators[bucketStart]!.outputTokens += usage.outputTokens
                accumulators[bucketStart]!.cacheCreationTokens += usage.cacheCreationInputTokens ?? 0
                accumulators[bucketStart]!.cacheReadTokens += usage.cacheReadInputTokens ?? 0
                accumulators[bucketStart]!.entryCount += 1
            }
        }
        
        // 결과 변환
        for hour in hourKeys {
            let acc = accumulators[hour] ?? HourlyAccumulator()
            let bucketEnd = calendar.date(byAdding: .hour, value: bucketHours, to: hour) ?? hour
            result[hour] = AggregatedUsage(
                inputTokens: acc.inputTokens,
                outputTokens: acc.outputTokens,
                cacheCreationTokens: acc.cacheCreationTokens,
                cacheReadTokens: acc.cacheReadTokens,
                period: DateInterval(start: hour, end: bucketEnd),
                entryCount: acc.entryCount
            )
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("[성능] aggregateHourly: \(hours)시간(\(bucketHours)h bucket), \(entries.count) entries, 소요시간: \(String(format: "%.3f", elapsed))s")
        
        return result
    }
    
    /// 일별 사용량 집계 (차트용) - 최적화된 O(N) 버전
    func aggregateDaily(entries: [ClaudeLogEntry], days: Int = 7) -> [Date: AggregatedUsage] {
        let startTime = CFAbsoluteTimeGetCurrent()
        let now = Date()
        var result: [Date: AggregatedUsage] = [:]
        
        // 일별 누적기 초기화
        struct DailyAccumulator {
            var inputTokens: Int64 = 0
            var outputTokens: Int64 = 0
            var cacheCreationTokens: Int64 = 0
            var cacheReadTokens: Int64 = 0
            var entryCount: Int = 0
        }
        var accumulators: [Date: DailyAccumulator] = [:]
        
        // 일별 키 미리 계산
        var dayKeys: [Date] = []
        for dayOffset in 0..<days {
            if let dayStart = calendar.date(byAdding: .day, value: -dayOffset, to: calendar.startOfDay(for: now)) {
                dayKeys.append(dayStart)
                accumulators[dayStart] = DailyAccumulator()
            }
        }
        
        guard let windowStart = dayKeys.min() else {
            return result
        }
        
        // 단일 순회로 모든 엔트리 집계
        for entry in entries {
            guard let timestamp = entry.timestamp,
                  timestamp >= windowStart,
                  let usage = entry.usage else { continue }
            
            let dayStart = calendar.startOfDay(for: timestamp)
            
            if accumulators[dayStart] != nil {
                accumulators[dayStart]!.inputTokens += usage.inputTokens
                accumulators[dayStart]!.outputTokens += usage.outputTokens
                accumulators[dayStart]!.cacheCreationTokens += usage.cacheCreationInputTokens ?? 0
                accumulators[dayStart]!.cacheReadTokens += usage.cacheReadInputTokens ?? 0
                accumulators[dayStart]!.entryCount += 1
            }
        }
        
        // 결과 변환
        for day in dayKeys {
            let acc = accumulators[day] ?? DailyAccumulator()
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            result[day] = AggregatedUsage(
                inputTokens: acc.inputTokens,
                outputTokens: acc.outputTokens,
                cacheCreationTokens: acc.cacheCreationTokens,
                cacheReadTokens: acc.cacheReadTokens,
                period: DateInterval(start: day, end: dayEnd),
                entryCount: acc.entryCount
            )
        }
        
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        logger.debug("[성능] aggregateDaily: \(days)일, \(entries.count) entries, 소요시간: \(String(format: "%.3f", elapsed))s")
        
        return result
    }
}

