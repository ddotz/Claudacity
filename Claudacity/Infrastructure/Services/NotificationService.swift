// MARK: - Imports
import Foundation
import UserNotifications
import OSLog

// MARK: - Notification Type
enum NotificationType: String {
    case lowUsage = "low_usage"
    case criticalUsage = "critical_usage"
    case fastConsumption = "fast_consumption"
    case resetComplete = "reset_complete"
}

// MARK: - Notification Request
struct NotificationRequest {
    let type: NotificationType
    let title: String
    let body: String
    let sound: Bool
}

// MARK: - Protocol
protocol NotificationServiceProtocol: Sendable {
    func requestPermission() async -> Bool
    func send(_ notification: NotificationRequest) async
}

// MARK: - Notification Service
final class NotificationService: NotificationServiceProtocol, @unchecked Sendable {
    // MARK: Properties
    private let center = UNUserNotificationCenter.current()

    // MARK: NotificationServiceProtocol
    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    func send(_ notification: NotificationRequest) async {
        // 권한 확인
        let settings = await center.notificationSettings()
        writeLog("[NotificationService] Authorization status: \(settings.authorizationStatus.rawValue)")

        guard settings.authorizationStatus == .authorized else {
            writeLog("[NotificationService] Not authorized! Status: \(settings.authorizationStatus.rawValue)")
            return
        }

        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.body = notification.body

        if notification.sound {
            content.sound = .default
        }

        let request = UNNotificationRequest(
            identifier: "\(notification.type.rawValue)_\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            writeLog("[NotificationService] SUCCESS: \(notification.type.rawValue) - \(notification.title)")
            logDebug("Notification sent: \(notification.type.rawValue)", category: .notification)
        } catch {
            writeLog("[NotificationService] FAILED: \(notification.type.rawValue) - \(error.localizedDescription)")
            logError("Failed to send notification: \(notification.type.rawValue)", category: .notification, error: error)
        }
    }

    private func writeLog(_ message: String) {
        let logFile = URL(fileURLWithPath: "/tmp/claudacity_jsonl_debug.log")
        let line = "\(Date()): \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let handle = try? FileHandle(forWritingTo: logFile) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    // MARK: Convenience Methods
    func sendLowUsageNotification(percentage: Int) async {
        await send(NotificationRequest(
            type: .lowUsage,
            title: "잔량 낮음",
            body: "토큰 잔여량이 \(percentage)%입니다.",
            sound: true
        ))
    }

    func sendCriticalUsageNotification(percentage: Int) async {
        await send(NotificationRequest(
            type: .criticalUsage,
            title: "거의 소진됨",
            body: "토큰 잔여량이 \(percentage)%입니다. 곧 사용량이 소진됩니다.",
            sound: true
        ))
    }

    func sendResetNotification() async {
        await send(NotificationRequest(
            type: .resetComplete,
            title: "할당량 리셋",
            body: "토큰 할당량이 리셋되었습니다.",
            sound: false
        ))
    }
}
