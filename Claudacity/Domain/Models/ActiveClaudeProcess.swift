//
//  ActiveClaudeProcess.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import Foundation

// MARK: - Active Claude Process

/// Represents an actively running Claude Code process with its context usage information
struct ActiveClaudeProcess: Identifiable, Equatable, Sendable {
    // MARK: Properties

    /// Unique identifier (session ID hash)
    let id: Int

    /// Session ID from Claude Code
    let sessionId: String

    /// Process ID (if available, otherwise 0)
    let pid: Int32

    /// Working directory where Claude Code is running
    let workingDirectory: String

    /// Project name derived from working directory
    let projectName: String

    /// Total context tokens used in the conversation
    var contextTokensUsed: Int64

    /// Maximum context tokens allowed (Claude Code context window)
    let contextTokensLimit: Int64 = 200_000

    /// Last modified time of the session
    let lastModified: Date

    // MARK: Computed Properties

    /// Remaining context tokens available
    var contextRemainingTokens: Int64 {
        max(0, contextTokensLimit - contextTokensUsed)
    }

    /// Percentage of context used (0-100)
    var contextUsagePercent: Double {
        guard contextTokensLimit > 0 else { return 0 }
        return Double(contextTokensUsed) / Double(contextTokensLimit) * 100
    }

    /// Percentage of context remaining (0-100)
    var contextRemainingPercent: Double {
        max(0, 100 - contextUsagePercent)
    }

    /// Path to the conversation JSONL file
    var conversationPath: String {
        // Map working directory to ~/.claude/projects/-[encoded-path]/[sessionId].jsonl
        let encoded = workingDirectory
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let homeDirectory = NSHomeDirectory()
        return "\(homeDirectory)/.claude/projects/-\(encoded)/\(sessionId).jsonl"
    }

    /// Path to the conversation JSONL directory
    var conversationDirectory: String {
        // Map working directory to ~/.claude/projects/-[encoded-path]
        let encoded = workingDirectory
            .replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        let homeDirectory = NSHomeDirectory()
        return "\(homeDirectory)/.claude/projects/-\(encoded)"
    }

    /// Formatted context usage for display (e.g., "150K/200K")
    var formattedContextUsage: String {
        "\(formatTokenCount(contextTokensUsed))/\(formatTokenCount(contextTokensLimit))"
    }

    /// Formatted context remaining for display (e.g., "50K remaining")
    var formattedContextRemaining: String {
        "\(formatTokenCount(contextRemainingTokens)) remaining"
    }

    // MARK: Methods

    /// Formats a token count in thousands (K)
    private func formatTokenCount(_ count: Int64) -> String {
        String(format: "%.0fK", Double(count) / 1000)
    }
}

// MARK: - Process Snapshot

/// Represents a snapshot of all active Claude Code processes at a specific point in time
struct ProcessSnapshot: Sendable, Equatable {
    // MARK: Properties

    /// Timestamp when the snapshot was taken
    let timestamp: Date

    /// List of active processes at the time of snapshot
    let processes: [ActiveClaudeProcess]

    // MARK: Computed Properties

    /// Total number of active processes
    var totalProcesses: Int {
        processes.count
    }

    /// Total context tokens used across all processes
    var totalContextTokensUsed: Int64 {
        processes.reduce(0) { $0 + $1.contextTokensUsed }
    }

    /// Average context usage percentage across all processes
    var averageContextUsagePercent: Double {
        guard !processes.isEmpty else { return 0 }
        let sum = processes.reduce(0.0) { $0 + $1.contextUsagePercent }
        return sum / Double(processes.count)
    }
}
