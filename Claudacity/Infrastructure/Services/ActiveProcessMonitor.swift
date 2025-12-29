//
//  ActiveProcessMonitor.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import Foundation
import Combine
import OSLog

// MARK: - Active Process Monitor Protocol

/// Protocol for monitoring active Claude Code processes and their context usage
protocol ActiveProcessMonitor: Sendable {
    /// Starts monitoring active processes with the specified polling interval
    ///
    /// - Parameter interval: Time interval between process scans (default: 5 seconds)
    func startMonitoring(interval: TimeInterval)

    /// Stops monitoring active processes
    func stopMonitoring()

    /// Gets the current snapshot of active processes
    ///
    /// - Returns: Current process snapshot
    func getCurrentSnapshot() async -> ProcessSnapshot

    /// Publisher that emits process snapshots whenever they are updated
    var processUpdates: AnyPublisher<ProcessSnapshot, Never> { get }
}

// MARK: - Active Process Monitor Implementation

final class ActiveProcessMonitorImpl: ActiveProcessMonitor, @unchecked Sendable {
    // MARK: Properties

    private let processDiscovery: ProcessDiscovery
    private let logReader: ClaudeLogReader
    private let logger = Logger(subsystem: "com.claudacity.app", category: "ActiveProcessMonitor")

    private let processUpdatesSubject = PassthroughSubject<ProcessSnapshot, Never>()
    private var monitorTask: Task<Void, Never>?
    private var currentSnapshot: ProcessSnapshot?

    // MARK: Computed Properties

    var processUpdates: AnyPublisher<ProcessSnapshot, Never> {
        processUpdatesSubject.eraseToAnyPublisher()
    }

    // MARK: Initialization

    init(
        processDiscovery: ProcessDiscovery,
        logReader: ClaudeLogReader
    ) {
        self.processDiscovery = processDiscovery
        self.logReader = logReader
    }

    deinit {
        stopMonitoring()
    }

    // MARK: Public Methods

    func startMonitoring(interval: TimeInterval = 5.0) {
        // Cancel any existing monitoring task
        stopMonitoring()

        logger.info("Starting process monitoring with \(interval)s interval")

        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateProcesses()

                // Sleep for the specified interval
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    // Task was cancelled
                    break
                }
            }
        }
    }

    func stopMonitoring() {
        logger.info("Stopping process monitoring")
        monitorTask?.cancel()
        monitorTask = nil
    }

    func getCurrentSnapshot() async -> ProcessSnapshot {
        if let snapshot = currentSnapshot {
            return snapshot
        }

        // No snapshot available yet, create one now
        await updateProcesses()
        return currentSnapshot ?? ProcessSnapshot(timestamp: Date(), processes: [])
    }

    // MARK: Private Methods

    private func updateProcesses() async {
        do {
            // Discover active Claude Code processes with their PIDs
            let pidProcesses = try await processDiscovery.discoverActiveProcesses()

            logger.debug("Found \(pidProcesses.count) active Claude Code processes")

            guard !pidProcesses.isEmpty else {
                let emptySnapshot = ProcessSnapshot(timestamp: Date(), processes: [])
                currentSnapshot = emptySnapshot
                processUpdatesSubject.send(emptySnapshot)
                return
            }

            // Fetch context for each unique working directory from JSONL logs
            var processesWithContext: [ActiveClaudeProcess] = []
            var processedWorkingDirs = Set<String>()

            for pidProcess in pidProcesses {
                // Skip if already processed this working directory
                guard !processedWorkingDirs.contains(pidProcess.workingDirectory) else {
                    continue
                }
                processedWorkingDirs.insert(pidProcess.workingDirectory)

                // Get conversation directory for this working directory
                let encoded = pidProcess.workingDirectory
                    .replacingOccurrences(of: "/", with: "-")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                let homeDirectory = NSHomeDirectory()
                let conversationDir = URL(fileURLWithPath: "\(homeDirectory)/.claude/projects/-\(encoded)")

                // Read active sessions and get context from JSONL logs
                do {
                    let sessions = try await logReader.readEntriesBySession(
                        from: conversationDir,
                        activeMinutes: 30
                    )

                    // Find the most recent session with usage data
                    if let latestSession = sessions.first {
                        let contextTokens = calculateContextFromUsage(latestSession.entries)

                        let process = ActiveClaudeProcess(
                            id: pidProcess.pid.hashValue,
                            sessionId: latestSession.sessionId,
                            pid: pidProcess.pid,
                            workingDirectory: pidProcess.workingDirectory,
                            projectName: pidProcess.projectName,
                            contextTokensUsed: contextTokens,
                            lastModified: latestSession.lastModified
                        )

                        processesWithContext.append(process)

                        logger.debug("PID \(pidProcess.pid) context: \(contextTokens)/200000 (\(Int(Double(contextTokens) / 2000))%)")
                    } else {
                        // No session found, add with 0 context
                        let process = ActiveClaudeProcess(
                            id: pidProcess.pid.hashValue,
                            sessionId: "pid-\(pidProcess.pid)",
                            pid: pidProcess.pid,
                            workingDirectory: pidProcess.workingDirectory,
                            projectName: pidProcess.projectName,
                            contextTokensUsed: 0,
                            lastModified: Date()
                        )
                        processesWithContext.append(process)
                    }
                } catch {
                    logger.warning("Failed to read JSONL for PID \(pidProcess.pid): \(error.localizedDescription)")

                    // Add process with 0 context if reading fails
                    let process = ActiveClaudeProcess(
                        id: pidProcess.pid.hashValue,
                        sessionId: "pid-\(pidProcess.pid)",
                        pid: pidProcess.pid,
                        workingDirectory: pidProcess.workingDirectory,
                        projectName: pidProcess.projectName,
                        contextTokensUsed: 0,
                        lastModified: Date()
                    )
                    processesWithContext.append(process)
                }
            }

            // Create snapshot
            let snapshot = ProcessSnapshot(timestamp: Date(), processes: processesWithContext)
            currentSnapshot = snapshot

            // Publish update
            processUpdatesSubject.send(snapshot)

            logger.debug("Updated process snapshot: \(processesWithContext.count) active processes")
        } catch {
            logger.error("Failed to update processes: \(error.localizedDescription)")

            // Publish empty snapshot on error
            let emptySnapshot = ProcessSnapshot(timestamp: Date(), processes: [])
            currentSnapshot = emptySnapshot
            processUpdatesSubject.send(emptySnapshot)
        }
    }

    // MARK: - Helper Methods

    /// Calculate context window usage from the last usage entry in JSONL
    /// Formula: cache_read_input_tokens + cache_creation_input_tokens + input_tokens
    private func calculateContextFromUsage(_ entries: [ClaudeLogEntry]) -> Int64 {
        // Find the last entry with usage data (most recent API call)
        guard let lastEntryWithUsage = entries.last(where: { $0.usage != nil }),
              let usage = lastEntryWithUsage.usage else {
            return 0
        }

        // Context window = cache_read (previous context) + cache_creation (new cache) + input (current input)
        let cacheRead = usage.cacheReadInputTokens ?? 0
        let cacheCreation = usage.cacheCreationInputTokens ?? 0
        let input = usage.inputTokens

        let total = cacheRead + cacheCreation + input

        logger.debug("Context calculation: cache_read=\(cacheRead), cache_creation=\(cacheCreation), input=\(input), total=\(total)")

        return total
    }
}
