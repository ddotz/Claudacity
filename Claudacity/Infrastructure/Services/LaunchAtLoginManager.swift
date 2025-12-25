//
//  LaunchAtLoginManager.swift
//  Claudacity
//

// MARK: - Imports
import Foundation
import ServiceManagement
import OSLog

// MARK: - Launch At Login Manager
/// Manages the app's launch at login setting using SMAppService (macOS 13+)
final class LaunchAtLoginManager: @unchecked Sendable {

    // MARK: - Singleton
    static let shared = LaunchAtLoginManager()

    // MARK: - Properties
    private let appService: SMAppService

    // MARK: - Initialization
    private init() {
        self.appService = SMAppService.mainApp
        logDebug("LaunchAtLoginManager initialized", category: .data)
    }

    // MARK: - Public Methods

    /// Returns whether the app is set to launch at login
    var isEnabled: Bool {
        appService.status == .enabled
    }

    /// Sets whether the app should launch at login
    /// - Parameter enabled: Whether to enable launch at login
    func setLaunchAtLogin(enabled: Bool) {
        do {
            if enabled {
                try appService.register()
                logInfo("Launch at login enabled", category: .data)
            } else {
                try appService.unregister()
                logInfo("Launch at login disabled", category: .data)
            }
        } catch {
            logError("Failed to set launch at login: \(error.localizedDescription)", category: .data)
        }
    }

    /// Synchronizes the setting with the current system state
    /// Call this on app launch to ensure consistency
    func synchronize(with settingsStore: SettingsStore) {
        let systemEnabled = isEnabled
        let settingEnabled = settingsStore.settings.launchAtLogin

        if systemEnabled != settingEnabled {
            // Update settings to match system state
            settingsStore.update { settings in
                settings.launchAtLogin = systemEnabled
            }
            logDebug("Synchronized launch at login setting: \(systemEnabled)", category: .data)
        }
    }
}

// MARK: - Status Description Helper
extension LaunchAtLoginManager {
    /// Returns a human-readable description of the current status
    var statusDescription: String {
        switch appService.status {
        case .notRegistered:
            return "Not Registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires Approval"
        case .notFound:
            return "Not Found"
        @unknown default:
            return "Unknown"
        }
    }
}
