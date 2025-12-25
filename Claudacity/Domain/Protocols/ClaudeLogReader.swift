// MARK: - Imports
import Foundation

// MARK: - Claude Log Reader Protocol
/// Claude Code JSONL 로그 파일을 읽고 파싱하는 프로토콜
protocol ClaudeLogReader {
    /// 모든 프로젝트 로그 디렉토리 조회
    func getLogDirectories() -> [URL]

    /// 특정 프로젝트의 로그 항목 읽기
    func readEntries(from projectDir: URL) async throws -> [ClaudeLogEntry]

    /// 모든 프로젝트의 로그 항목 읽기
    func readAllEntries() async throws -> [ClaudeLogEntry]

    /// 파일 변경 감시 스트림
    func watchForChanges() -> AsyncStream<URL>

    /// Claude Code 설치 여부 확인
    var isClaudeCodeInstalled: Bool { get }
}

// MARK: - Usage Aggregator Protocol
/// 기간별 사용량 집계를 담당하는 프로토콜
protocol UsageAggregator {
    /// 특정 기간의 사용량 집계
    func aggregate(entries: [ClaudeLogEntry], period: DateInterval) -> AggregatedUsage

    /// 현재 5시간 윈도우의 사용량 집계
    func aggregateCurrentWindow(entries: [ClaudeLogEntry]) -> AggregatedUsage

    /// 오늘 사용량 집계
    func aggregateToday(entries: [ClaudeLogEntry]) -> AggregatedUsage

    /// 이번 주 사용량 집계 (달력 기준)
    func aggregateThisWeek(entries: [ClaudeLogEntry]) -> AggregatedUsage

    // MARK: - 주간 한도 관련 (2025년 8월 신규)

    /// 롤링 7일 주간 사용량 집계 (주간 한도용)
    func aggregateRollingWeek(entries: [ClaudeLogEntry]) -> AggregatedUsage

    /// 다음 주간 한도 리셋 시간 계산
    func nextWeeklyReset() -> Date

    /// 다음 5시간 세션 리셋 시간 계산
    func nextSessionReset(from lastActivity: Date?) -> Date

    // MARK: - 차트용

    /// 시간대별 사용량 집계 (차트용)
    func aggregateHourly(entries: [ClaudeLogEntry], hours: Int, bucketHours: Int) -> [Date: AggregatedUsage]

    /// 일별 사용량 집계 (차트용)
    func aggregateDaily(entries: [ClaudeLogEntry], days: Int) -> [Date: AggregatedUsage]
}
