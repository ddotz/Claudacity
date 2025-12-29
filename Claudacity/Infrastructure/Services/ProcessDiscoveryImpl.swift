//
//  ProcessDiscoveryImpl.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import Foundation
import OSLog

// MARK: - Process Discovery Implementation

final class ProcessDiscoveryImpl: ProcessDiscovery {
    // MARK: Properties

    private let logger = Logger(subsystem: "com.claudacity.app", category: "ProcessDiscovery")

    // MARK: Public Methods

    func discoverActiveProcesses() async throws -> [ActiveClaudeProcess] {
        let pids = try await findClaudeProcesses()
        logger.debug("Found \(pids.count) claude processes: \(pids.map { String($0) }.joined(separator: ", "))")

        var processes: [ActiveClaudeProcess] = []

        for pid in pids {
            do {
                let workingDirectory = try await getWorkingDirectory(forPID: pid)

                // Filter out plugin directories
                if workingDirectory.contains("/.claude/plugins/") {
                    logger.debug("Skipping plugin process PID \(pid): \(workingDirectory)")
                    continue
                }

                let projectName = extractProjectName(from: workingDirectory)

                let process = ActiveClaudeProcess(
                    id: Int(pid),
                    sessionId: "temp-\(pid)", // Temporary, will be replaced by ActiveProcessMonitor
                    pid: pid,
                    workingDirectory: workingDirectory,
                    projectName: projectName,
                    contextTokensUsed: 0,
                    lastModified: Date()
                )

                processes.append(process)
                logger.debug("Discovered process PID \(pid): \(projectName) at \(workingDirectory)")
            } catch {
                logger.warning("Failed to get working directory for PID \(pid): \(error.localizedDescription)")
                continue
            }
        }

        return processes
    }

    func getWorkingDirectory(forPID pid: Int32) async throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["-a", "-p", String(pid), "-d", "cwd", "-Fn"]
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Read output BEFORE waiting to prevent deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let _ = errorPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw AppError.cliExecutionFailed("lsof failed with status \(process.terminationStatus)")
            }

            return try parseLsofOutput(output)
        } catch {
            throw AppError.cliExecutionFailed("Failed to execute lsof: \(error.localizedDescription)")
        }
    }

    func isProcessRunning(_ pid: Int32) async -> Bool {
        let process = Process()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-p", String(pid)]
        process.standardOutput = Pipe()
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: Private Methods

    private func findClaudeProcesses() async throws -> [Int32] {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["aux"]
        process.standardOutput = pipe
        process.standardError = errorPipe

        do {
            try process.run()

            // Read output BEFORE waiting for exit to prevent deadlock
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let _ = errorPipe.fileHandleForReading.readDataToEndOfFile()

            process.waitUntilExit()

            let output = String(data: data, encoding: .utf8) ?? ""

            guard process.terminationStatus == 0 else {
                throw AppError.cliExecutionFailed("ps failed with status \(process.terminationStatus)")
            }

            return parseProcessList(output)
        } catch {
            throw AppError.cliExecutionFailed("Failed to execute ps: \(error.localizedDescription)")
        }
    }

    private func parseProcessList(_ output: String) -> [Int32] {
        let lines = output.components(separatedBy: .newlines)
        var pids: [Int32] = []

        for line in lines {
            // Skip header and empty lines
            guard !line.isEmpty, !line.starts(with: "USER") else { continue }

            // Check if line contains "claude" or "/claude"
            guard line.contains("claude") else { continue }

            // Filter out unwanted processes
            if shouldFilterProcess(line) {
                continue
            }

            // Extract PID (second column in ps aux output)
            let components = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard components.count >= 2, let pid = Int32(components[1]) else { continue }

            pids.append(pid)
        }

        return pids
    }

    private func shouldFilterProcess(_ line: String) -> Bool {
        let excludePatterns = [
            "Claude.app",           // Claude Desktop app
            "Claude Helper",        // Claude Desktop helpers
            "grep claude",          // Our own grep command
            "ps aux",               // Our own ps command
            ".exp",                 // Expect scripts
            "claude-usage.exp",     // Our usage monitoring script
            "mcp-server",           // MCP servers
            "worker-service",       // Claude plugin workers
            "shell-snapshots",      // Shell snapshot processes
            ".claude/plugins",      // Plugin processes (generic)
            "node ",                // Node.js processes (MCP servers)
            "bun ",                 // Bun processes (plugin workers)
            "python",               // Python processes (MCP servers)
            "/usr/bin/uv",          // UV tool processes
            "chroma-mcp",           // Chroma MCP server
            "/bin/zsh",             // Shell processes
            "/bin/bash"             // Bash shell processes
        ]

        for pattern in excludePatterns {
            if line.contains(pattern) {
                return true
            }
        }

        return false
    }

    private func parseLsofOutput(_ output: String) throws -> String {
        // lsof -Fn output format:
        // p<pid>
        // fcwd
        // n<directory>

        let lines = output.components(separatedBy: .newlines)
        var foundCwd = false

        for line in lines {
            // Look for "fcwd" line first
            if line == "fcwd" {
                foundCwd = true
                continue
            }

            // After finding "fcwd", the next "n" line is the working directory
            if foundCwd && line.hasPrefix("n") {
                let path = String(line.dropFirst())
                return path
            }
        }

        throw AppError.cliExecutionFailed("Could not parse working directory from lsof output")
    }

    private func extractProjectName(from path: String) -> String {
        let url = URL(fileURLWithPath: path)
        return url.lastPathComponent
    }
}
