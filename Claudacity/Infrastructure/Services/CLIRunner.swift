//
//  CLIRunner.swift
//  Claudacity
//
//  Created by Claude Code
//

import Foundation

// MARK: - CLI Runner Protocol

protocol CLIRunnerProtocol: Sendable {
    func isClaudeCodeInstalled() async -> Bool
    func getClaudeCodePath() async -> String?
    func runCommand(_ command: String, arguments: [String]) async throws -> CLIOutput
    func getUsageFromCLI() async throws -> CLIUsageData?
}

// MARK: - CLI Output

struct CLIOutput: Sendable {
    let stdout: String
    let stderr: String
    let exitCode: Int32

    var isSuccess: Bool {
        exitCode == 0
    }
}

// MARK: - CLI Usage Data

struct CLIUsageData: Codable, Sendable {
    let totalTokensUsed: Int64?
    let sessionTokensUsed: Int64?
    let dailyTokensUsed: Int64?
    let weeklyTokensUsed: Int64?
    let inputTokens: Int64?
    let outputTokens: Int64?
    let lastUpdated: Date?

    static let empty = CLIUsageData(
        totalTokensUsed: nil,
        sessionTokensUsed: nil,
        dailyTokensUsed: nil,
        weeklyTokensUsed: nil,
        inputTokens: nil,
        outputTokens: nil,
        lastUpdated: nil
    )
}

// MARK: - CLI Runner Implementation

final class CLIRunner: CLIRunnerProtocol, @unchecked Sendable {

    // MARK: - Properties

    private let fileManager: FileManager
    private let processTimeout: TimeInterval
    private var cachedClaudePath: String?

    // UserDefaults key for persistent CLI path storage (shared with CLIUsageService)
    private static let claudePathKey = "claudeCliPath"

    // MARK: - Init

    init(fileManager: FileManager = .default, timeout: TimeInterval = 30.0) {
        self.fileManager = fileManager
        self.processTimeout = timeout
    }

    // MARK: - Public Methods

    /// Check if Claude Code CLI is installed on the system
    func isClaudeCodeInstalled() async -> Bool {
        logDebug("Checking if Claude Code is installed", category: .cli)

        // First try to find in PATH using 'which'
        if let path = await getClaudeCodePath(), !path.isEmpty {
            logInfo("Claude Code found at: \(path)", category: .cli)
            return true
        }

        logInfo("Claude Code not found", category: .cli)
        return false
    }

    /// Get the path to Claude Code executable
    func getClaudeCodePath() async -> String? {
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

        // 3. 파일 시스템 탐색 (첫 실행 시에만 발생)
        logDebug("No cached path found, scanning file system (first run)...", category: .cli)
        if let foundPath = scanForClaudePath() {
            cachedClaudePath = foundPath
            saveClaudePathToUserDefaults(foundPath)
            logInfo("Claude CLI found and cached at: \(foundPath)", category: .cli)
            return foundPath
        }

        return nil
    }

    /// 파일 시스템에서 Claude CLI 경로 검색 (권한 요청 발생 가능)
    private func scanForClaudePath() -> String? {
        // Note: 이 함수는 처음 한 번만 실행되며, 권한 요청이 발생할 수 있습니다.
        // 찾은 경로는 UserDefaults에 저장되어 이후 실행 시에는 이 함수가 호출되지 않습니다.

        // Note: 'which' 명령어는 shell 초기화 과정에서 권한 요청을 유발할 수 있으므로
        // 직접 경로 확인만 수행

        // Common paths where Claude Code might be installed
        // Note: tilde(~) 경로와 expandingTildeInPath는 권한 요청을 유발할 수 있으므로
        // NSUserName()을 사용한 명시적 경로 사용
        let homeDir = "/Users/\(NSUserName())"
        let possiblePaths = [
            "\(homeDir)/.claude/local/claude",  // 최신 Claude Code 설치 경로
            "\(homeDir)/.claude/bin/claude",
            "\(homeDir)/.local/bin/claude",
            "/usr/local/bin/claude",
            "/opt/homebrew/bin/claude",
            "/usr/bin/claude"
        ]

        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                logDebug("Claude Code found at: \(path)", category: .cli)
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

    /// Run a shell command and return the output
    func runCommand(_ command: String, arguments: [String] = []) async throws -> CLIOutput {
        logDebug("Running command: \(command) \(arguments.joined(separator: " "))", category: .cli)

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()

            process.executableURL = URL(fileURLWithPath: command)
            process.arguments = arguments
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // 환경 변수 설정 - 전체 환경 변수 상속 대신 필요한 것만 명시적으로 설정
            // Note: NSHomeDirectory()는 보호된 폴더 접근 권한 요청을 유발하므로 사용하지 않음
            let environment: [String: String] = [
                "PATH": "/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin",
                "HOME": "/Users/\(NSUserName())",
                "LANG": "en_US.UTF-8"
            ]
            process.environment = environment

            // Timeout handling
            let timeoutWorkItem = DispatchWorkItem { [weak process] in
                if let process = process, process.isRunning {
                    logWarning("Command timed out, terminating process", category: .cli)
                    process.terminate()
                }
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + processTimeout, execute: timeoutWorkItem)

            do {
                try process.run()
                process.waitUntilExit()

                timeoutWorkItem.cancel()

                let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

                let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
                let stderr = String(data: stderrData, encoding: .utf8) ?? ""

                let output = CLIOutput(
                    stdout: stdout,
                    stderr: stderr,
                    exitCode: process.terminationStatus
                )

                if output.isSuccess {
                    logDebug("Command succeeded", category: .cli)
                } else {
                    logWarning("Command failed with exit code \(output.exitCode): \(stderr)", category: .cli)
                }

                continuation.resume(returning: output)
            } catch {
                timeoutWorkItem.cancel()
                logError("Failed to run command", category: .cli, error: error)
                continuation.resume(throwing: AppError.cliExecutionFailed(error.localizedDescription))
            }
        }
    }

    /// Get usage data from Claude Code CLI
    func getUsageFromCLI() async throws -> CLIUsageData? {
        guard let claudePath = await getClaudeCodePath() else {
            throw AppError.cliNotInstalled
        }

        logDebug("Fetching usage data from CLI", category: .cli)

        // Try to get usage information
        // Note: This assumes Claude Code CLI has a usage command or similar
        // The actual command may need to be adjusted based on Claude Code CLI implementation
        do {
            // Try 'claude usage' or 'claude --usage' or similar
            let output = try await runCommand(claudePath, arguments: ["usage", "--json"])

            if output.isSuccess {
                return parseUsageOutput(output.stdout)
            }

            // If that fails, try alternative commands
            let altOutput = try await runCommand(claudePath, arguments: ["status", "--json"])
            if altOutput.isSuccess {
                return parseUsageOutput(altOutput.stdout)
            }

            logWarning("Could not get usage data from CLI", category: .cli)
            return nil
        } catch {
            logError("Failed to get usage from CLI", category: .cli, error: error)
            throw error
        }
    }

    // MARK: - Private Methods

    private func parseUsageOutput(_ output: String) -> CLIUsageData? {
        guard !output.isEmpty else { return nil }

        let data = output.data(using: .utf8)!

        // Try to parse as JSON
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(CLIUsageData.self, from: data)
        } catch {
            logDebug("Failed to parse CLI output as JSON: \(error)", category: .cli)
        }

        // Try to parse as key-value pairs
        return parseKeyValueOutput(output)
    }

    private func parseKeyValueOutput(_ output: String) -> CLIUsageData? {
        var totalTokens: Int64?
        var sessionTokens: Int64?
        var dailyTokens: Int64?
        var weeklyTokens: Int64?
        var inputTokens: Int64?
        var outputTokens: Int64?

        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            let parts = line.split(separator: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2 else { continue }

            let key = parts[0].lowercased()
            let value = parts[1]

            if let intValue = Int64(value.replacingOccurrences(of: ",", with: "")) {
                switch key {
                case let k where k.contains("total") && k.contains("token"):
                    totalTokens = intValue
                case let k where k.contains("session") && k.contains("token"):
                    sessionTokens = intValue
                case let k where k.contains("daily") && k.contains("token"):
                    dailyTokens = intValue
                case let k where k.contains("weekly") && k.contains("token"):
                    weeklyTokens = intValue
                case let k where k.contains("input") && k.contains("token"):
                    inputTokens = intValue
                case let k where k.contains("output") && k.contains("token"):
                    outputTokens = intValue
                default:
                    break
                }
            }
        }

        // Only return if we parsed at least some data
        if totalTokens != nil || sessionTokens != nil || dailyTokens != nil {
            return CLIUsageData(
                totalTokensUsed: totalTokens,
                sessionTokensUsed: sessionTokens,
                dailyTokensUsed: dailyTokens,
                weeklyTokensUsed: weeklyTokens,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                lastUpdated: Date()
            )
        }

        return nil
    }
}

// MARK: - Mock CLI Runner (for development/testing)

final class MockCLIRunner: CLIRunnerProtocol, @unchecked Sendable {

    var isInstalled: Bool = true
    var mockPath: String? = "/usr/local/bin/claude"
    var mockUsageData: CLIUsageData? = nil  // 실제 CLI 데이터 없음을 시뮬레이션

    func isClaudeCodeInstalled() async -> Bool {
        return isInstalled
    }

    func getClaudeCodePath() async -> String? {
        return isInstalled ? mockPath : nil
    }

    func runCommand(_ command: String, arguments: [String]) async throws -> CLIOutput {
        if !isInstalled {
            throw AppError.cliNotInstalled
        }
        return CLIOutput(stdout: "Mock output", stderr: "", exitCode: 0)
    }

    func getUsageFromCLI() async throws -> CLIUsageData? {
        if !isInstalled {
            throw AppError.cliNotInstalled
        }
        return mockUsageData
    }
}
