// MARK: - Imports
import AppKit
import SwiftUI
import Combine
import OSLog
import UserNotifications

// MARK: - AppDelegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: Properties
    private var menuBarController: MenuBarController?
    private var cancellables = Set<AnyCancellable>()

    // MARK: Lifecycle
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[Claudacity] applicationDidFinishLaunching called")

        logInfo("Claudacity app launched", category: .app)
        applySettings()
        setupMenuBar()
        setupNotificationDelegate()
        requestNotificationPermission()

        NSLog("[Claudacity] applicationDidFinishLaunching completed")
    }

    private func setupNotificationDelegate() {
        UNUserNotificationCenter.current().delegate = self
    }

    func applicationWillTerminate(_ notification: Notification) {
        logInfo("Claudacity app terminating", category: .app)
        menuBarController = nil
    }

    // MARK: Private Methods
    private func applySettings() {
        let settingsStore = Dependencies.shared.settingsStore

        // Apply saved theme
        settingsStore.applyCurrentTheme()

        // Sync launch at login setting with system
        LaunchAtLoginManager.shared.synchronize(with: settingsStore)

        logDebug("Settings applied", category: .app)
    }

    private func setupMenuBar() {
        let dependencies = Dependencies.shared
        menuBarController = MenuBarController(
            viewModel: dependencies.usageViewModel
        )
        menuBarController?.setup()
        logDebug("MenuBar setup complete", category: .menuBar)
    }

    private func requestNotificationPermission() {
        Task {
            let notificationService = Dependencies.shared.notificationService
            let granted = await notificationService.requestPermission()
            if granted {
                logInfo("Notification permission granted", category: .notification)
            } else {
                logWarning("Notification permission denied", category: .notification)
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // 앱이 포그라운드에 있어도 배너와 소리 표시
        completionHandler([.banner, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // 알림 클릭 시 처리
        completionHandler()
    }
}
