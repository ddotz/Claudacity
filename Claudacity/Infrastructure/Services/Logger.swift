//
//  Logger.swift
//  Claudacity
//
//  Created by Claude Code
//

import Foundation
import OSLog

// MARK: - Log Categories

enum LogCategory: String {
    case app = "App"
    case network = "Network"
    case storage = "Storage"
    case ui = "UI"
    case notification = "Notification"
    case menuBar = "MenuBar"
    case repository = "Repository"
    case data = "Data"
    case cli = "CLI"
}

// MARK: - Logger

final class AppLogger: @unchecked Sendable {

    // MARK: - Singleton

    static let shared = AppLogger()

    // MARK: - Properties

    private let subsystem: String
    private var loggers: [LogCategory: Logger] = [:]

    // MARK: - Init

    private init() {
        self.subsystem = Bundle.main.bundleIdentifier ?? "com.claudacity"

        // Pre-create loggers for all categories
        for category in LogCategory.allCases {
            loggers[category] = Logger(subsystem: subsystem, category: category.rawValue)
        }
    }

    // MARK: - Private Methods

    private func logger(for category: LogCategory) -> Logger {
        if let existing = loggers[category] {
            return existing
        }
        let newLogger = Logger(subsystem: subsystem, category: category.rawValue)
        loggers[category] = newLogger
        return newLogger
    }

    // MARK: - Public Methods

    /// Log debug information (development only)
    func debug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
        #if DEBUG
        let fileName = (file as NSString).lastPathComponent
        logger(for: category).debug("[\(fileName):\(line)] \(function) - \(message)")
        #endif
    }

    /// Log general information
    func info(_ message: String, category: LogCategory = .app) {
        logger(for: category).info("\(message)")
    }

    /// Log notices (more important than info)
    func notice(_ message: String, category: LogCategory = .app) {
        logger(for: category).notice("\(message)")
    }

    /// Log warnings (potential issues)
    func warning(_ message: String, category: LogCategory = .app) {
        logger(for: category).warning("\(message)")
    }

    /// Log errors
    func error(_ message: String, category: LogCategory = .app, error: Error? = nil) {
        if let error = error {
            logger(for: category).error("\(message): \(error.localizedDescription)")
        } else {
            logger(for: category).error("\(message)")
        }
    }

    /// Log critical errors (app may crash)
    func critical(_ message: String, category: LogCategory = .app, error: Error? = nil) {
        if let error = error {
            logger(for: category).critical("\(message): \(error.localizedDescription)")
        } else {
            logger(for: category).critical("\(message)")
        }
    }

    /// Log with signpost for performance measurement
    func signpostBegin(_ name: StaticString, category: LogCategory = .app) -> OSSignpostID {
        let signpostID = OSSignpostID(log: OSLog(subsystem: subsystem, category: category.rawValue))
        os_signpost(.begin, log: OSLog(subsystem: subsystem, category: category.rawValue), name: name, signpostID: signpostID)
        return signpostID
    }

    func signpostEnd(_ name: StaticString, signpostID: OSSignpostID, category: LogCategory = .app) {
        os_signpost(.end, log: OSLog(subsystem: subsystem, category: category.rawValue), name: name, signpostID: signpostID)
    }
}

// MARK: - LogCategory + CaseIterable

extension LogCategory: CaseIterable {}

// MARK: - Global Convenience Functions

/// Quick debug log
func logDebug(_ message: String, category: LogCategory = .app, file: String = #file, function: String = #function, line: Int = #line) {
    AppLogger.shared.debug(message, category: category, file: file, function: function, line: line)
}

/// Quick info log
func logInfo(_ message: String, category: LogCategory = .app) {
    AppLogger.shared.info(message, category: category)
}

/// Quick warning log
func logWarning(_ message: String, category: LogCategory = .app) {
    AppLogger.shared.warning(message, category: category)
}

/// Quick error log
func logError(_ message: String, category: LogCategory = .app, error: Error? = nil) {
    AppLogger.shared.error(message, category: category, error: error)
}
