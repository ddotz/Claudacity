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

        // 1. Expect 스크립트 경로 확인
        guard let scriptPath = getExpectScriptPath() else {
            throw AppError.cliExecutionFailed("Expect script not found in bundle")
        }

        // 2. Claude CLI 경로 확인
        guard let claudePath = await getClaudePath() else {
            throw AppError.cliNotInstalled
        }

        // 3. Expect 스크립트 실행
        let output = try await runExpectScript(scriptPath: scriptPath, claudePath: claudePath)

        // 4. 출력 파싱
        let result = parseExpectOutput(output)

        logInfo("CLI usage fetched: session=\(result.sessionUsedPercent)%, weekly=\(result.weeklyUsedPercent)%", category: .cli)

        return result
    }

    /// Claude CLI 사용 가능 여부 확인
    func isAvailable() async -> Bool {
        guard getExpectScriptPath() != nil else { return false }
        return await getClaudePath() != nil
    }

    // MARK: - Private Methods

    /// 번들 내 Expect 스크립트 경로 반환
    private func getExpectScriptPath() -> String? {
        let scriptName = "claude-usage.exp"

        // 1. Bundle.main.path 시도
        if let bundlePath = Bundle.main.path(forResource: "claude-usage", ofType: "exp") {
            logDebug("Script found via Bundle.main.path: \(bundlePath)", category: .cli)
            return bundlePath
        }

        // 2. Bundle.main.resourceURL 시도
        if let resourceURL = Bundle.main.resourceURL {
            let scriptURL = resourceURL.appendingPathComponent(scriptName)
            if fileManager.fileExists(atPath: scriptURL.path) {
                logDebug("Script found via resourceURL: \(scriptURL.path)", category: .cli)
                return scriptURL.path
            }
        }

        // 3. Bundle.main.bundleURL 직접 접근
        let bundleResourcePath = Bundle.main.bundleURL
            .appendingPathComponent("Contents/Resources")
            .appendingPathComponent(scriptName).path
        if fileManager.fileExists(atPath: bundleResourcePath) {
            logDebug("Script found via bundleURL: \(bundleResourcePath)", category: .cli)
            return bundleResourcePath
        }

        // 4. 프로젝트 소스 폴더에서 찾기 (개발용)
        let projectPath = "/Users/\(NSUserName())/Code/Claudacity/Claudacity/Resources/\(scriptName)"
        if fileManager.fileExists(atPath: projectPath) {
            logDebug("Script found in project: \(projectPath)", category: .cli)
            return projectPath
        }

        // Note: DerivedData 전체 스캔은 불필요한 권한 요청(Apple Music, 네트워크 볼륨 등)을 
        // 유발하므로 제거됨. 번들 빌드 시 스크립트는 Bundle.main에서 찾아야 함.

        logWarning("Expect script not found anywhere", category: .cli)
        return nil
    }

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

    /// Expect 스크립트 실행
    private func runExpectScript(scriptPath: String, claudePath: String) async throws -> String {
        logDebug("Running expect script: \(scriptPath) with claude at: \(claudePath)", category: .cli)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: "/usr/bin/expect")
            process.arguments = ["-f", scriptPath, claudePath]
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // 환경 변수 설정 - 전체 환경 변수 상속 대신 필요한 것만 명시적으로 설정
            // Note: NSHomeDirectory()는 보호된 폴더 접근 권한 요청을 유발하므로 사용하지 않음
            let env: [String: String] = [
                "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
                "TERM": "xterm-256color",
                "HOME": "/Users/\(NSUserName())",
                "LANG": "en_US.UTF-8"
            ]
            process.environment = env

            // 타임아웃 처리
            let timeoutWork = DispatchWorkItem { [weak process] in
                if let p = process, p.isRunning {
                    logWarning("Expect script timed out, terminating", category: .cli)
                    p.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

            do {
                try process.run()
                process.waitUntilExit()
                timeoutWork.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                if process.terminationStatus != 0 && process.terminationStatus != 127 {
                    // 에러지만 출력이 있으면 파싱 시도
                    if stdout.contains("SESSION_USED") {
                        continuation.resume(returning: stdout)
                        return
                    }

                    logWarning("Expect script failed: exit=\(process.terminationStatus), stderr=\(stderr)", category: .cli)
                    continuation.resume(throwing: AppError.cliExecutionFailed(stderr.isEmpty ? "Exit code \(process.terminationStatus)" : stderr))
                    return
                }

                continuation.resume(returning: stdout)
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

    /// Expect 스크립트 출력 파싱
    private func parseExpectOutput(_ output: String) -> CLIUsageResult {
        var sessionUsed: Int = 0
        var sessionReset: String?
        var weeklyUsed: Int = 0
        var weeklyReset: String?

        let lines = output.components(separatedBy: .newlines)

        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1).map { String($0) }
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "SESSION_USED":
                sessionUsed = Int(value) ?? 0
            case "SESSION_RESET":
                sessionReset = value
            case "WEEKLY_USED":
                weeklyUsed = Int(value) ?? 0
            case "WEEKLY_RESET":
                weeklyReset = value
            default:
                break
            }
        }

        logDebug("Parsed: session=\(sessionUsed)%, reset=\(sessionReset ?? "nil"), weekly=\(weeklyUsed)%, reset=\(weeklyReset ?? "nil")", category: .cli)

        return CLIUsageResult(
            sessionUsedPercent: sessionUsed,
            sessionResetTime: sessionReset,
            weeklyUsedPercent: weeklyUsed,
            weeklyResetTime: weeklyReset,
            fetchedAt: Date()
        )
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
