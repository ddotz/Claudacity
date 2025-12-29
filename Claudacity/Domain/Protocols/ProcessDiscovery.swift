//
//  ProcessDiscovery.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import Foundation

// MARK: - Process Discovery Protocol

/// Protocol for discovering and managing active Claude Code processes
protocol ProcessDiscovery: Sendable {
    /// Discovers all actively running Claude Code processes
    ///
    /// - Returns: Array of active Claude Code processes with their basic information
    /// - Throws: AppError if process discovery fails
    func discoverActiveProcesses() async throws -> [ActiveClaudeProcess]

    /// Gets the working directory for a specific process ID
    ///
    /// - Parameter pid: The process ID to query
    /// - Returns: The working directory path
    /// - Throws: AppError if the working directory cannot be determined
    func getWorkingDirectory(forPID pid: Int32) async throws -> String

    /// Checks if a process with the given PID is currently running
    ///
    /// - Parameter pid: The process ID to check
    /// - Returns: True if the process is running, false otherwise
    func isProcessRunning(_ pid: Int32) async -> Bool
}
