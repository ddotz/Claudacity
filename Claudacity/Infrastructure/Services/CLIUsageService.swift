//
//  CLIUsageService.swift
//  Claudacity
//
//  Claude CLI /usage 명령어를 통해 사용량을 조회하는 서비스
//

import Foundation

// MARK: - CLI Usage Result

/// Claude CLI /usage 명령어 파싱 결과
struct CLIUsageResult: Sendable, Equatable {
    let sessionUsedPercent: Int       // 세션 사용량 % (예: 8 = 8% 사용, 92% 남음)
    let sessionResetTime: String?     // 세션 리셋 시간 (예: "4:59pm (KST)")
    let weeklyUsedPercent: Int        // 주간 사용량 % (예: 52 = 52% 사용, 48% 남음)
    let weeklyResetTime: String?      // 주간 리셋 시간 (예: "Dec 16, 10:59am (KST)")
    let fetchedAt: Date               // 조회 시점

    /// 세션 잔여 퍼센트 (0-100)
    var sessionRemainingPercent: Int {
        max(0, 100 - sessionUsedPercent)
    }

    /// 주간 잔여 퍼센트 (0-100)
    var weeklyRemainingPercent: Int {
        max(0, 100 - weeklyUsedPercent)
    }

    /// 세션 리셋까지 남은 시간 (Date 변환)
    var sessionResetDate: Date? {
        guard let timeString = sessionResetTime else { return nil }
        return parseResetTime(timeString, isToday: true)
    }

    /// 주간 리셋까지 남은 시간 (Date 변환)
    var weeklyResetDate: Date? {
        guard let timeString = weeklyResetTime else { return nil }
        return parseResetTime(timeString, isToday: false)
    }

    static let empty = CLIUsageResult(
        sessionUsedPercent: 0,
        sessionResetTime: nil,
        weeklyUsedPercent: 0,
        weeklyResetTime: nil,
        fetchedAt: Date()
    )
}

// MARK: - CLI Usage Service Protocol

protocol CLIUsageServiceProtocol: Sendable {
    func fetchUsage() async throws -> CLIUsageResult
    func isAvailable() async -> Bool
}

// MARK: - CLI Usage Service Implementation

final class CLIUsageService: CLIUsageServiceProtocol, @unchecked Sendable {

    // MARK: - Properties

    private let fileManager: FileManager
    private let timeout: TimeInterval
    private var cachedClaudePath: String?

    // MARK: - Init

    init(fileManager: FileManager = .default, timeout: TimeInterval = 30.0) {
        self.fileManager = fileManager
        self.timeout = timeout
    }

    // MARK: - Public Methods

    /// Claude CLI 사용량 조회
    func fetchUsage() async throws -> CLIUsageResult {
        logDebug("Fetching usage via CLI /usage command", category: .cli)

        // 1. Claude CLI 경로 확인
        guard let claudePath = await getClaudePath() else {
            throw AppError.cliNotInstalled
        }

        // 2. script 명령으로 Claude CLI 실행 (TTY 환경 제공)
        let output = try await runClaudeUsageWithScript(claudePath: claudePath)

        // 3. 출력 파싱
        let result = parseUsageOutput(output)

        logInfo("CLI usage fetched: session=\(result.sessionUsedPercent)%, weekly=\(result.weeklyUsedPercent)%", category: .cli)

        return result
    }

    /// Claude CLI 사용 가능 여부 확인
    func isAvailable() async -> Bool {
        return await getClaudePath() != nil
    }

    // MARK: - Private Methods

    /// Claude CLI 경로 찾기
    private func getClaudePath() async -> String? {
        if let cached = cachedClaudePath, fileManager.fileExists(atPath: cached) {
            logDebug("Using cached Claude path: \(cached)", category: .cli)
            return cached
        }

        // 환경 변수에서 확인
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_USAGE_CLI_PATH"],
           fileManager.fileExists(atPath: envPath) {
            cachedClaudePath = envPath
            logDebug("Claude found via env: \(envPath)", category: .cli)
            return envPath
        }

        // 일반적인 경로들 먼저 확인 (which보다 빠르고 확실함)
        // Note: NSHomeDirectory()는 보호된 폴더 접근 권한 요청을 유발하므로 사용하지 않음
        let homeDir = "/Users/\(NSUserName())"
        let commonPaths = [
            "\(homeDir)/.claude/local/claude",  // 최신 Claude Code 설치 경로
            "\(homeDir)/.claude/bin/claude",
            "\(homeDir)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude"
        ]

        for path in commonPaths {
            if fileManager.fileExists(atPath: path) {
                cachedClaudePath = path
                logDebug("Claude found at: \(path)", category: .cli)
                return path
            }
        }

        // Note: which 명령어 실행은 bash shell 초기화 과정에서 사용자 설정 파일을 읽으면서
        // 사진, 네트워크 볼륨 등 보호된 디렉토리 접근 권한 요청을 유발할 수 있으므로 제거됨.
        // 위의 commonPaths에서 찾지 못하면 Claude CLI가 설치되지 않은 것으로 간주.

        logWarning("Claude CLI not found in common paths", category: .cli)
        return nil
    }

    /// expect 스크립트를 사용한 Claude CLI /usage 실행
    private func runClaudeUsageWithScript(claudePath: String) async throws -> String {
        logDebug("Running Claude CLI /usage via expect script", category: .cli)

        // expect 스크립트 경로 찾기
        guard let scriptPath = Bundle.main.path(forResource: "claude-usage", ofType: "exp") else {
            logError("claude-usage.exp script not found in bundle", category: .cli)
            throw AppError.cliExecutionFailed("Expect script not found")
        }

        logDebug("Using expect script at: \(scriptPath)", category: .cli)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            // expect 스크립트 실행
            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            process.arguments = [scriptPath, claudePath]
            process.standardOutput = pipe
            process.standardError = pipe

            // 환경 변수
            var env = ProcessInfo.processInfo.environment
            env["CLAUDE_USAGE_CLI_PATH"] = claudePath
            process.environment = env

            // 타임아웃 (30초)
            let timeoutWork = DispatchWorkItem { [weak process] in
                if let p = process, p.isRunning {
                    logWarning("Expect script timed out after 30s", category: .cli)
                    p.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutWork)

            do {
                try process.run()
                process.waitUntilExit()
                timeoutWork.cancel()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""

                logDebug("Expect script output length: \(output.count) bytes", category: .cli)
                logDebug("Output preview: \(String(output.prefix(300)))", category: .cli)

                // Debug: Print full output to console for debugging
                print("=== EXPECT SCRIPT OUTPUT ===")
                print(output)
                print("=== END OUTPUT ===")

                if output.isEmpty {
                    logWarning("Expect script returned empty output", category: .cli)
                    print("⚠️ WARNING: Expect script returned empty output!")
                } else if output.contains("ERROR:") {
                    logError("Expect script returned error: \(output)", category: .cli)
                    print("❌ ERROR: Expect script returned error: \(output)")
                }

                continuation.resume(returning: output)
            } catch {
                timeoutWork.cancel()
                logError("Failed to run expect script", category: .cli, error: error)
                continuation.resume(throwing: AppError.cliExecutionFailed(error.localizedDescription))
            }
        }
    }

    /// Process 실행 유틸리티
    private func runProcess(_ command: String, arguments: [String]) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let pipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                continuation.resume(returning: output)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// expect 스크립트 출력 파싱
    /// 예상 형식:
    /// SESSION_USED:8
    /// SESSION_RESET:4:59pm (KST)
    /// WEEKLY_USED:52
    /// WEEKLY_RESET:Dec 16, 10:59am (KST)
    private func parseUsageOutput(_ output: String) -> CLIUsageResult {
        logDebug("Starting to parse expect script output", category: .cli)
        print("=== PARSING START ===")
        print("Output to parse (\(output.count) bytes):")
        print(output)

        var sessionUsed: Int = 0
        var sessionReset: String?
        var weeklyUsed: Int = 0
        var weeklyReset: String?

        // 라인별로 파싱
        let lines = output.components(separatedBy: .newlines)
        print("Total lines: \(lines.count)")

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("SESSION_USED:") {
                if let value = Int(trimmed.replacingOccurrences(of: "SESSION_USED:", with: "")) {
                    sessionUsed = value
                    logDebug("Parsed SESSION_USED: \(sessionUsed)%", category: .cli)
                    print("✓ Parsed SESSION_USED: \(sessionUsed)")
                }
            } else if trimmed.hasPrefix("SESSION_RESET:") {
                sessionReset = trimmed.replacingOccurrences(of: "SESSION_RESET:", with: "")
                logDebug("Parsed SESSION_RESET: \(sessionReset ?? "nil")", category: .cli)
                print("✓ Parsed SESSION_RESET: \(sessionReset ?? "nil")")
            } else if trimmed.hasPrefix("WEEKLY_USED:") {
                if let value = Int(trimmed.replacingOccurrences(of: "WEEKLY_USED:", with: "")) {
                    weeklyUsed = value
                    logDebug("Parsed WEEKLY_USED: \(weeklyUsed)%", category: .cli)
                    print("✓ Parsed WEEKLY_USED: \(weeklyUsed)")
                }
            } else if trimmed.hasPrefix("WEEKLY_RESET:") {
                weeklyReset = trimmed.replacingOccurrences(of: "WEEKLY_RESET:", with: "")
                logDebug("Parsed WEEKLY_RESET: \(weeklyReset ?? "nil")", category: .cli)
                print("✓ Parsed WEEKLY_RESET: \(weeklyReset ?? "nil")")
            } else if trimmed.hasPrefix("ERROR:") {
                logError("Expect script error: \(trimmed)", category: .cli)
                print("❌ ERROR: \(trimmed)")
            }
        }

        // 파싱 실패 경고
        if sessionUsed == 0 && weeklyUsed == 0 {
            logWarning("Failed to parse usage data from expect script output", category: .cli)
            logDebug("Full output:\n\(output)", category: .cli)
            print("❌ PARSING FAILED: No usage data found")
        }

        let result = CLIUsageResult(
            sessionUsedPercent: sessionUsed,
            sessionResetTime: sessionReset,
            weeklyUsedPercent: weeklyUsed,
            weeklyResetTime: weeklyReset,
            fetchedAt: Date()
        )

        print("=== PARSING RESULT ===")
        print("Session Used: \(result.sessionUsedPercent)%")
        print("Session Remaining: \(result.sessionRemainingPercent)%")
        print("Weekly Used: \(result.weeklyUsedPercent)%")
        print("Weekly Remaining: \(result.weeklyRemainingPercent)%")
        print("=== END PARSING ===")

        return result
    }
}

// MARK: - Reset Time Parsing Helper

/// 리셋 시간 문자열을 Date로 변환
/// - Parameters:
///   - timeString: "4:59pm (KST)" 또는 "Dec 16, 10:59am (KST)" 형식
///   - isToday: true면 오늘 날짜 기준, false면 날짜 포함된 문자열 파싱
/// - Returns: 파싱된 Date, 실패시 nil
private func parseResetTime(_ timeString: String, isToday: Bool) -> Date? {
    // 괄호 앞까지만 추출 (타임존 제외)
    let components = timeString.components(separatedBy: "(")
    let timePart = components[0].trimmingCharacters(in: .whitespaces)

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")

    if isToday {
        // "4:59pm" 또는 "4pm" 형식
        // 분이 없는 경우 처리
        let normalizedTime = normalizeTimeFormat(timePart)
        formatter.dateFormat = "h:mma"

        if let time = formatter.date(from: normalizedTime) {
            // 오늘 날짜에 시간 적용
            let calendar = Calendar.current
            let now = Date()
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: now)
            let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
            dateComponents.hour = timeComponents.hour
            dateComponents.minute = timeComponents.minute
            dateComponents.second = 0

            if let result = calendar.date(from: dateComponents) {
                // 이미 지났으면 내일로
                return result < now ? calendar.date(byAdding: .day, value: 1, to: result) : result
            }
        }
    } else {
        // "Dec 16, 10:59am" 형식
        // 콤마 유무 처리
        let normalizedDate = timePart.replacingOccurrences(of: ",", with: "")
        formatter.dateFormat = "MMM d h:mma"

        if let date = formatter.date(from: normalizeTimeFormat(normalizedDate)) {
            // 연도 추가 (현재 연도 또는 다음 연도)
            let calendar = Calendar.current
            var components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
            components.year = calendar.component(.year, from: Date())

            if let result = calendar.date(from: components) {
                // 이미 지났으면 내년으로
                return result < Date() ? calendar.date(byAdding: .year, value: 1, to: result) : result
            }
        }
    }

    return nil
}

/// 시간 형식 정규화 ("5pm" -> "5:00pm")
private func normalizeTimeFormat(_ time: String) -> String {
    // am/pm 앞에 분이 없으면 :00 추가
    let pattern = #"(\d{1,2})([aApP][mM])"#
    if let regex = try? NSRegularExpression(pattern: pattern),
       let match = regex.firstMatch(in: time, range: NSRange(time.startIndex..., in: time)),
       match.numberOfRanges == 3 {
        // 이미 콜론이 있으면 그대로
        if time.contains(":") { return time }

        let hourRange = Range(match.range(at: 1), in: time)!
        let ampmRange = Range(match.range(at: 2), in: time)!
        return String(time[hourRange]) + ":00" + String(time[ampmRange])
    }
    return time
}

// MARK: - Mock CLI Usage Service

final class MockCLIUsageService: CLIUsageServiceProtocol, @unchecked Sendable {
    var mockResult: CLIUsageResult?
    var shouldFail = false
    var isInstalled = true

    func fetchUsage() async throws -> CLIUsageResult {
        if shouldFail {
            throw AppError.cliExecutionFailed("Mock error")
        }
        return mockResult ?? CLIUsageResult(
            sessionUsedPercent: 8,
            sessionResetTime: "4:59pm (KST)",
            weeklyUsedPercent: 52,
            weeklyResetTime: "Dec 30, 10:59am (KST)",
            fetchedAt: Date()
        )
    }

    func isAvailable() async -> Bool {
        return isInstalled
    }
}
