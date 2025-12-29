//
//  ContextCalculator.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import Foundation

// MARK: - Context Calculator Protocol

/// Protocol for calculating context usage from Claude Code conversation logs
protocol ContextCalculator: Sendable {
    /// Calculates the total context usage for a specific conversation
    ///
    /// - Parameter conversationPath: Path to the conversation directory containing JSONL files
    /// - Returns: Total number of tokens used in the conversation (sum of rateLimitTokens)
    /// - Throws: AppError if the conversation cannot be read or parsed
    func calculateContextUsage(forConversation conversationPath: String) async throws -> Int64

    /// Calculates context usage for multiple processes in parallel
    ///
    /// - Parameter processes: Array of active processes to calculate context for
    /// - Returns: Dictionary mapping process ID to total context tokens used
    func calculateContextUsage(forProcesses processes: [ActiveClaudeProcess]) async -> [Int: Int64]
}
