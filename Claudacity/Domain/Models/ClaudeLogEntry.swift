// MARK: - Imports
import Foundation

// MARK: - Claude Log Entry
/// Claude Code JSONL 로그 파일의 각 항목을 나타내는 모델
/// 경로: ~/.claude/projects/[project]/{sessionId}.jsonl
struct ClaudeLogEntry: Codable {
    let type: String?             // "user", "assistant", "file-history-snapshot" 등 (옵셔널로 변경)
    let timestamp: Date?
    let message: LogMessage?
    let sessionId: String?
    let uuid: String?
    
    /// usage 정보를 message 내부에서 가져옴
    var usage: TokenUsage? {
        message?.usage
    }
    
    /// 프로젝트 경로 (cwd 필드)
    let cwd: String?
    
    var projectPath: String? {
        cwd
    }

    enum CodingKeys: String, CodingKey {
        case type
        case timestamp
        case message
        case sessionId = "sessionId"
        case uuid
        case cwd
    }
    
    /// 커스텀 디코딩 - 다양한 JSON 형식 처리
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // 모든 필드를 옵셔널하게 디코딩
        type = try container.decodeIfPresent(String.self, forKey: .type)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        
        // timestamp 디코딩 시도 (여러 형식 지원)
        timestamp = try? container.decodeIfPresent(Date.self, forKey: .timestamp)
        
        // message 디코딩 시도 (실패해도 nil로 처리)
        message = try? container.decodeIfPresent(LogMessage.self, forKey: .message)
    }
    
    /// 수동 인코딩
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(type, forKey: .type)
        try container.encodeIfPresent(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(message, forKey: .message)
        try container.encodeIfPresent(sessionId, forKey: .sessionId)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encodeIfPresent(cwd, forKey: .cwd)
    }
}

// MARK: - Log Message
struct LogMessage: Codable {
    let role: String?
    let content: LogContent?
    let model: String?
    let usage: TokenUsage?
    let id: String?
    
    enum CodingKeys: String, CodingKey {
        case role
        case content
        case model
        case usage
        case id
    }
    
    // content가 String 또는 Array일 수 있음
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        role = try container.decodeIfPresent(String.self, forKey: .role)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        
        // usage 파싱 시도 (실패해도 nil로 처리)
        usage = try? container.decodeIfPresent(TokenUsage.self, forKey: .usage)
        
        // content 파싱 시도 - String 또는 Array 처리
        if let stringContent = try? container.decodeIfPresent(String.self, forKey: .content) {
            content = .string(stringContent)
        } else if let arrayContent = try? container.decodeIfPresent([ContentBlock].self, forKey: .content) {
            content = .array(arrayContent)
        } else {
            content = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(role, forKey: .role)
        try container.encodeIfPresent(model, forKey: .model)
        try container.encodeIfPresent(usage, forKey: .usage)
        try container.encodeIfPresent(id, forKey: .id)
    }
}

// MARK: - Log Content
enum LogContent: Codable {
    case string(String)
    case array([ContentBlock])
    
    var textContent: String? {
        switch self {
        case .string(let str):
            return str
        case .array(let blocks):
            return blocks.compactMap { $0.text }.joined(separator: "\n")
        }
    }
}

// MARK: - Content Block
struct ContentBlock: Codable {
    let type: String?
    let text: String?
    let thinking: String?
}

// MARK: - Token Usage
/// API 응답에 포함되는 토큰 사용량 정보
struct TokenUsage: Codable, Equatable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheCreationInputTokens: Int64?
    let cacheReadInputTokens: Int64?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    // MARK: - 기본 토큰 계산

    /// 단순 토큰 합계 (input + output)
    var simpleTokens: Int64 {
        inputTokens + outputTokens
    }

    /// 전체 캐시 토큰 (creation + read)
    var cachedTokens: Int64 {
        (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
    }

    // MARK: - Rate Limit 계산 (2025년 12월 기준)

    /// Rate limit 계산용 토큰 (input + output + cache_creation)
    /// 주의: cache_read는 rate limit에 포함되지 않음!
    /// 출처: Anthropic API 문서 - "cache_read_input_tokens Do NOT count towards ITPM"
    var rateLimitTokens: Int64 {
        inputTokens + outputTokens + (cacheCreationInputTokens ?? 0)
    }

    /// 캐시 읽기로 절약된 토큰 (rate limit에서 제외됨)
    var tokensSavedByCache: Int64 {
        cacheReadInputTokens ?? 0
    }

    /// 캐시 효율성 비율 (0.0 - 1.0)
    /// 캐시 히트율 = cache_read / (cache_creation + cache_read)
    var cacheEfficiency: Double {
        let total = cachedTokens
        guard total > 0 else { return 0 }
        return Double(cacheReadInputTokens ?? 0) / Double(total)
    }

    /// 캐시 효율성 퍼센트 (0 - 100)
    var cacheEfficiencyPercent: Double {
        cacheEfficiency * 100
    }

    // MARK: - 호환성 유지 (Deprecated)

    /// 기존 totalTokens 호환성 유지
    @available(*, deprecated, renamed: "rateLimitTokens",
               message: "Use rateLimitTokens for clarity. totalTokens is now an alias.")
    var totalTokens: Int64 {
        rateLimitTokens
    }

    /// 전체 토큰 (cache_read 포함) - 로깅/통계용
    var allTokens: Int64 {
        inputTokens + outputTokens + (cacheCreationInputTokens ?? 0) + (cacheReadInputTokens ?? 0)
    }

    // MARK: - Static & Operators

    static let zero = TokenUsage(
        inputTokens: 0,
        outputTokens: 0,
        cacheCreationInputTokens: 0,
        cacheReadInputTokens: 0
    )

    static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens,
            cacheCreationInputTokens: (lhs.cacheCreationInputTokens ?? 0) + (rhs.cacheCreationInputTokens ?? 0),
            cacheReadInputTokens: (lhs.cacheReadInputTokens ?? 0) + (rhs.cacheReadInputTokens ?? 0)
        )
    }
}

// MARK: - Aggregated Usage
/// 특정 기간 동안의 집계된 사용량
struct AggregatedUsage: Equatable {
    let inputTokens: Int64
    let outputTokens: Int64
    let cacheCreationTokens: Int64
    let cacheReadTokens: Int64
    let period: DateInterval
    let entryCount: Int

    // MARK: - Rate Limit 계산 (2025년 12월 기준)

    /// Rate limit 계산용 토큰 (input + output + cache_creation)
    /// 주의: cache_read는 rate limit에 포함되지 않음!
    var rateLimitTokens: Int64 {
        inputTokens + outputTokens + cacheCreationTokens
    }

    /// 기존 totalTokens 호환성 유지
    @available(*, deprecated, renamed: "rateLimitTokens")
    var totalTokens: Int64 { rateLimitTokens }

    /// 캐시 토큰 합계
    var cachedTokens: Int64 { cacheCreationTokens + cacheReadTokens }

    /// 캐시 읽기로 절약된 토큰
    var tokensSavedByCache: Int64 { cacheReadTokens }

    /// 캐시 효율성 비율 (0.0 - 1.0)
    var cacheEfficiency: Double {
        guard cachedTokens > 0 else { return 0 }
        return Double(cacheReadTokens) / Double(cachedTokens)
    }

    /// 캐시 효율성 퍼센트 (0 - 100)
    var cacheEfficiencyPercent: Double {
        cacheEfficiency * 100
    }

    // MARK: - 퍼센트 계산

    /// 한도 대비 사용 퍼센트 계산
    func usagePercentage(limit: Int64) -> Double {
        guard limit > 0 else { return 0 }
        return Double(rateLimitTokens) / Double(limit) * 100
    }

    /// 잔여 퍼센트 계산
    func remainingPercentage(limit: Int64) -> Double {
        max(0, 100 - usagePercentage(limit: limit))
    }

    // MARK: - Static

    static let empty = AggregatedUsage(
        inputTokens: 0,
        outputTokens: 0,
        cacheCreationTokens: 0,
        cacheReadTokens: 0,
        period: DateInterval(start: Date(), duration: 0),
        entryCount: 0
    )
}
