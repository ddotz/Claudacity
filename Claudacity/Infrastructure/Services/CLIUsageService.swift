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
    func resetClaudePath()
    func getCachedClaudePath() -> String?
}

// MARK: - CLI Usage Service Implementation

final class CLIUsageService: CLIUsageServiceProtocol, @unchecked Sendable {

    // MARK: - Properties

    private let fileManager: FileManager
    private let timeout: TimeInterval
    private var cachedClaudePath: String?

    // UserDefaults key for persistent CLI path storage
    private static let claudePathKey = "claudeCliPath"

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
        // 1. 메모리 캐시 확인 (앱 실행 중 여러 번 호출될 때 빠른 응답)
        if let cached = cachedClaudePath, fileManager.fileExists(atPath: cached) {
            logDebug("Using memory-cached Claude path: \(cached)", category: .cli)
            return cached
        }

        // 2. UserDefaults 영구 캐시 확인 (앱 재시작 후에도 유지)
        if let persistedPath = UserDefaults.standard.string(forKey: Self.claudePathKey),
           fileManager.fileExists(atPath: persistedPath) {
            cachedClaudePath = persistedPath
            logDebug("Using UserDefaults cached Claude path: \(persistedPath)", category: .cli)
            return persistedPath
        }

        // 3. 환경 변수에서 확인
        if let envPath = ProcessInfo.processInfo.environment["CLAUDE_USAGE_CLI_PATH"],
           fileManager.fileExists(atPath: envPath) {
            cachedClaudePath = envPath
            saveClaudePathToUserDefaults(envPath)
            logDebug("Claude found via env: \(envPath)", category: .cli)
            return envPath
        }

        // 4. 파일 시스템 탐색 (첫 실행 시에만 발생)
        logDebug("No cached path found, scanning file system (first run)...", category: .cli)
        if let foundPath = scanFileSystemForClaudePath() {
            cachedClaudePath = foundPath
            saveClaudePathToUserDefaults(foundPath)
            logInfo("Claude CLI found and cached at: \(foundPath)", category: .cli)
            return foundPath
        }

        // Note: which 명령어 실행은 bash shell 초기화 과정에서 사용자 설정 파일을 읽으면서
        // 사진, 네트워크 볼륨 등 보호된 디렉토리 접근 권한 요청을 유발할 수 있으므로 제거됨.
        // 위의 commonPaths에서 찾지 못하면 Claude CLI가 설치되지 않은 것으로 간주.

        logWarning("Claude CLI not found in common paths", category: .cli)
        return nil
    }

    /// 파일 시스템에서 Claude CLI 경로 검색 (권한 요청 발생 가능)
    private func scanFileSystemForClaudePath() -> String? {
        // Note: 이 함수는 처음 한 번만 실행되며, 권한 요청이 발생할 수 있습니다.
        // 찾은 경로는 UserDefaults에 저장되어 이후 실행 시에는 이 함수가 호출되지 않습니다.

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
                return path
            }
        }

        return nil
    }

    /// UserDefaults에 Claude CLI 경로 저장
    private func saveClaudePathToUserDefaults(_ path: String) {
        UserDefaults.standard.set(path, forKey: Self.claudePathKey)
        logDebug("Saved Claude CLI path to UserDefaults: \(path)", category: .cli)
    }

    /// UserDefaults에서 저장된 경로 삭제 (경로가 더 이상 유효하지 않을 때)
    func resetClaudePath() {
        UserDefaults.standard.removeObject(forKey: Self.claudePathKey)
        cachedClaudePath = nil
        logInfo("Reset cached Claude CLI path", category: .cli)
    }

    /// 현재 캐시된 CLI 경로 반환
    func getCachedClaudePath() -> String? {
        if let cached = cachedClaudePath {
            return cached
        }
        return UserDefaults.standard.string(forKey: Self.claudePathKey)
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

            // 환경 변수 - 필요한 것만 명시적으로 설정 (권한 요청 방지)
            // Note: ProcessInfo.processInfo.environment 전체를 자식 프로세스에 전달하면
            // iTunes/Music 폴더 등 보호된 디렉토리 경로가 포함되어 권한 요청을 유발할 수 있음
            // 따라서 필요한 환경 변수만 개별적으로 읽어서 전달

            // HOME 경로는 환경 변수에서 가져오기 (커스텀 홈 디렉토리 지원)
            let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? "/Users/\(NSUserName())"

            // Claude CLI 디렉토리를 PATH에 추가 (CLI 내부에서 필요할 수 있음)
            let claudeDir = (claudePath as NSString).deletingLastPathComponent
            let pathValue = "\(claudeDir):/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin"

            let environment: [String: String] = [
                "PATH": pathValue,
                "HOME": homeDir,
                "LANG": "en_US.UTF-8",
                "CLAUDE_USAGE_CLI_PATH": claudePath
            ]
            process.environment = environment

            // 타임아웃 (15초 - expect 스크립트는 10초)
            let timeoutWork = DispatchWorkItem { [weak process] in
                if let p = process, p.isRunning {
                    logWarning("Expect script timed out after 15s", category: .cli)
                    p.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + 15, execute: timeoutWork)

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
    var mockPath: String? = "/usr/local/bin/claude"

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

    func resetClaudePath() {
        mockPath = nil
    }

    func getCachedClaudePath() -> String? {
        return mockPath
    }
}
