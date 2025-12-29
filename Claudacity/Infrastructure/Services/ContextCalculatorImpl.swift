//
//  ContextCalculatorImpl.swift
//  Claudacity
//
//  Created by Claude on 2025-12-28.
//

import Foundation
import OSLog

// MARK: - Context Calculator Implementation

final class ContextCalculatorImpl: ContextCalculator {
    // MARK: Properties

    private let logReader: ClaudeLogReader
    private let logger = Logger(subsystem: "com.claudacity.app", category: "ContextCalculator")

    // MARK: Initialization

    init(logReader: ClaudeLogReader) {
        self.logReader = logReader
    }

    // MARK: Public Methods

    func calculateContextUsage(forConversation conversationPath: String) async throws -> Int64 {
        let conversationURL = URL(fileURLWithPath: conversationPath)

        // Check if session file exists
        guard FileManager.default.fileExists(atPath: conversationPath) else {
            logger.debug("Session file does not exist: \(conversationPath)")
            return 0
        }

        do {
            // 특정 세션 파일 직접 읽기
            let allEntries = try await logReader.readSessionFile(conversationURL)
            logger.debug("Read \(allEntries.count) total entries from \(conversationPath)")

            // Find the last summary event (indicates context compaction)
            var lastSummaryIndex: Int? = nil
            for (index, entry) in allEntries.enumerated().reversed() {
                if entry.type == "summary" {
                    lastSummaryIndex = index
                    break
                }
            }

            // Get entries after last summary (active context)
            let activeEntries: [ClaudeLogEntry]
            if let summaryIndex = lastSummaryIndex {
                // Take entries after the last summary
                activeEntries = Array(allEntries.suffix(from: summaryIndex + 1))
                logger.debug("Found summary at index \(summaryIndex), calculating context from \(activeEntries.count) entries after it")
            } else {
                // No summary found - session hasn't been compacted yet
                // Take all entries (this is the current active session)
                activeEntries = allEntries
                logger.debug("No summary found, using all \(activeEntries.count) entries")
            }

            // Get the most recent entry with usage (contains current context state)
            if let lastEntry = activeEntries.last(where: { $0.usage != nil }),
               let usage = lastEntry.usage {
                // Context = cached content + new content being created + input
                // Note: output_tokens are not yet in context window
                let cacheRead = usage.cacheReadInputTokens ?? 0
                let cacheCreation = usage.cacheCreationInputTokens ?? 0
                let inputTokens = usage.inputTokens
                let activeTokens = cacheRead + cacheCreation + inputTokens

                logger.debug("Active context from last entry: cache_read=\(cacheRead), cache_creation=\(cacheCreation), input=\(inputTokens), total=\(activeTokens)")
                return activeTokens
            }

            // Fallback: sum all rate limit tokens if no cache info
            let activeTokens = activeEntries.reduce(Int64(0)) { sum, entry in
                let tokens = entry.usage?.rateLimitTokens ?? 0
                return sum + tokens
            }

            logger.debug("Active context (fallback): \(activeTokens) tokens from \(activeEntries.count) entries")
            return activeTokens
        } catch {
            logger.warning("Failed to read conversation at \(conversationPath): \(error.localizedDescription)")
            return 0
        }
    }

    func calculateContextUsage(forProcesses processes: [ActiveClaudeProcess]) async -> [Int: Int64] {
        await withTaskGroup(of: (Int, Int64).self) { group in
            for process in processes {
                group.addTask {
                    let tokens = (try? await self.calculateContextUsage(
                        forConversation: process.conversationPath
                    )) ?? 0
                    return (process.id, tokens)
                }
            }

            var results: [Int: Int64] = [:]
            for await (id, tokens) in group {
                results[id] = tokens
            }

            return results
        }
    }
}
