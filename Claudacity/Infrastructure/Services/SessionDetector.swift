//
//  SessionDetector.swift
//  Claudacity
//

// MARK: - Imports
import Foundation
import Combine
import OSLog

// MARK: - Session Detector Protocol
@MainActor
protocol SessionDetectorProtocol {
    func startMonitoring() async
    func stopMonitoring()
}

// MARK: - Session Detector
/// Automatically detects session starts and ends based on usage patterns
@MainActor
final class SessionDetector: SessionDetectorProtocol {

    // MARK: - Configuration
    private enum Config {
        /// How long to wait without usage changes before considering session idle
        static let idleTimeoutMinutes: TimeInterval = 30

        /// Minimum usage change to consider as active usage
        static let minimumUsageChangeThreshold: Int64 = 100

        /// How often to check for idle timeout (in seconds)
        static let idleCheckIntervalSeconds: TimeInterval = 60

        /// Threshold percentage change to detect session reset
        static let sessionResetThreshold: Double = 50.0
    }

    // MARK: - Properties
    private let dataManager: DataManagerProtocol
    private let settingsStore: SettingsStore
    private var cancellables = Set<AnyCancellable>()

    private var monitoringTask: Task<Void, Never>?
    private var lastUsageUpdate: Date = Date()
    private var lastUsageValue: Int64 = 0
    private var lastPercentage: Double = 100
    private var isMonitoring = false

    // MARK: - Callbacks
    var onSessionStarted: ((Session) -> Void)?
    var onSessionEnded: ((Session) -> Void)?
    var onIdleDetected: (() -> Void)?

    // MARK: - Initialization
    init(dataManager: DataManagerProtocol, settingsStore: SettingsStore) {
        self.dataManager = dataManager
        self.settingsStore = settingsStore
        logDebug("SessionDetector initialized", category: .data)
    }

    deinit {
        monitoringTask?.cancel()
    }

    // MARK: - Public Methods

    /// Starts monitoring for session changes
    func startMonitoring() async {
        guard !isMonitoring else { return }
        isMonitoring = true

        logInfo("Session monitoring started", category: .data)

        // Check if there's an existing active session or create one
        await ensureActiveSession()

        // Start idle monitoring
        startIdleMonitoring()
    }

    /// Stops session monitoring
    func stopMonitoring() {
        guard isMonitoring else { return }
        isMonitoring = false

        monitoringTask?.cancel()
        monitoringTask = nil

        logInfo("Session monitoring stopped", category: .data)
    }

    /// Call this when new usage data is received
    func updateUsage(percentage: Double, tokensUsed: Int64) async {
        let now = Date()

        // Check for session reset (percentage suddenly increased significantly)
        if lastPercentage < 30 && percentage > Config.sessionResetThreshold {
            logInfo("Session reset detected: \(Int(lastPercentage))% -> \(Int(percentage))%", category: .data)
            await handleSessionReset()
        }

        // Check for significant usage change
        let usageChange = tokensUsed - lastUsageValue
        if usageChange > Config.minimumUsageChangeThreshold {
            lastUsageUpdate = now
            logDebug("Usage activity detected: +\(usageChange) tokens", category: .data)
        }

        lastUsageValue = tokensUsed
        lastPercentage = percentage
    }

    /// Call this when the app becomes active
    func appDidBecomeActive() async {
        logDebug("App became active, checking session", category: .data)
        await ensureActiveSession()
    }

    /// Call this when the app resigns active
    func appWillResignActive() async {
        logDebug("App will resign active", category: .data)
        // Don't end session here - user might be switching apps briefly
    }

    /// Call this when the app will terminate
    func appWillTerminate() async {
        logInfo("App terminating, ending current session", category: .data)
        await endCurrentSession(reason: "앱 종료")
    }

    // MARK: - Private Methods

    private func ensureActiveSession() async {
        do {
            if let currentSession = try await dataManager.getCurrentSession() {
                logDebug("Active session found: \(currentSession.name)", category: .data)
            } else {
                let session = try await dataManager.createSession(name: nil)
                logInfo("Created new session on app launch: \(session.name)", category: .data)
                onSessionStarted?(session)
            }
        } catch {
            logError("Failed to ensure active session", category: .data, error: error)
        }
    }

    private func startIdleMonitoring() {
        monitoringTask?.cancel()

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self, self.isMonitoring else { break }

                await self.checkForIdleTimeout()

                try? await Task.sleep(nanoseconds: UInt64(Config.idleCheckIntervalSeconds * 1_000_000_000))
            }
        }
    }

    private func checkForIdleTimeout() async {
        let idleTime = Date().timeIntervalSince(lastUsageUpdate)
        let timeoutSeconds = Config.idleTimeoutMinutes * 60

        if idleTime > timeoutSeconds {
            logInfo("Idle timeout reached (\(Int(idleTime / 60)) minutes)", category: .data)
            onIdleDetected?()
            await handleIdleTimeout()
        }
    }

    private func handleIdleTimeout() async {
        // End current session due to idle
        await endCurrentSession(reason: "유휴 시간 초과")
    }

    private func handleSessionReset() async {
        // End old session and start new one
        await endCurrentSession(reason: "세션 리셋 감지")

        do {
            let session = try await dataManager.createSession(name: nil)
            logInfo("Started new session after reset: \(session.name)", category: .data)
            onSessionStarted?(session)

            // Reset idle timer
            lastUsageUpdate = Date()
        } catch {
            logError("Failed to create session after reset", category: .data, error: error)
        }
    }

    private func endCurrentSession(reason: String) async {
        do {
            if let currentSession = try await dataManager.getCurrentSession() {
                try await dataManager.endCurrentSession()
                logInfo("Session ended: \(currentSession.name) - \(reason)", category: .data)
                onSessionEnded?(currentSession)
            }
        } catch {
            logError("Failed to end session", category: .data, error: error)
        }
    }
}

// MARK: - Session Detector Factory
extension SessionDetector {
    static func create(dataManager: DataManagerProtocol, settingsStore: SettingsStore) -> SessionDetector {
        return SessionDetector(dataManager: dataManager, settingsStore: settingsStore)
    }
}
