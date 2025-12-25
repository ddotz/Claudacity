// MARK: - Imports
import Foundation
import Combine
import AppKit

// MARK: - Settings Store
final class SettingsStore: ObservableObject {
    // MARK: Constants
    private enum Keys {
        static let settings = "app_settings"
    }

    // MARK: Properties
    @Published private(set) var settings: AppSettings

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // MARK: Init
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.settings = Self.load(from: defaults) ?? .default
    }

    // MARK: Public Methods
    func update(_ settings: AppSettings) {
        self.settings = settings
        save(settings)
    }

    func update(_ transform: (inout AppSettings) -> Void) {
        var newSettings = settings
        transform(&newSettings)
        update(newSettings)
    }

    func reset() {
        update(.default)
    }

    // MARK: Private Methods
    private func save(_ settings: AppSettings) {
        guard let data = try? encoder.encode(settings) else { return }
        defaults.set(data, forKey: Keys.settings)
    }

    private static func load(from defaults: UserDefaults) -> AppSettings? {
        guard let data = defaults.data(forKey: Keys.settings) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

// MARK: - Convenience Accessors
extension SettingsStore {
    // MARK: Appearance
    var showPercentage: Bool {
        get { settings.showPercentage }
        set { update { $0.showPercentage = newValue } }
    }

    var showResetTime: Bool {
        get { settings.showResetTime }
        set { update { $0.showResetTime = newValue } }
    }

    var resetTimeFormat: ResetTimeFormat {
        get { settings.resetTimeFormat }
        set { update { $0.resetTimeFormat = newValue } }
    }

    var displayMode: DisplayMode {
        get { settings.displayMode }
        set { update { $0.displayMode = newValue } }
    }

    var theme: Theme {
        get { settings.theme }
        set {
            update { $0.theme = newValue }
            applyTheme(newValue)
        }
    }

    var enableAnimations: Bool {
        get { settings.enableAnimations }
        set { update { $0.enableAnimations = newValue } }
    }

    var iconStyle: IconStyle {
        get { settings.iconStyle }
        set { update { $0.iconStyle = newValue } }
    }

    // MARK: Notifications
    var lowThreshold: Int {
        get { settings.lowThreshold }
        set { update { $0.lowThreshold = newValue } }
    }

    var criticalThreshold: Int {
        get { settings.criticalThreshold }
        set { update { $0.criticalThreshold = newValue } }
    }

    var enableLowNotification: Bool {
        get { settings.enableLowNotification }
        set { update { $0.enableLowNotification = newValue } }
    }

    var enableCriticalNotification: Bool {
        get { settings.enableCriticalNotification }
        set { update { $0.enableCriticalNotification = newValue } }
    }

    var enableSound: Bool {
        get { settings.enableSound }
        set { update { $0.enableSound = newValue } }
    }

    // MARK: General
    var refreshInterval: TimeInterval {
        get { settings.refreshInterval }
        set { update { $0.refreshInterval = newValue } }
    }

    var launchAtLogin: Bool {
        get { settings.launchAtLogin }
        set {
            update { $0.launchAtLogin = newValue }
            LaunchAtLoginManager.shared.setLaunchAtLogin(enabled: newValue)
        }
    }

    var language: Language {
        get { settings.language }
        set { update { $0.language = newValue } }
    }
}

// MARK: - Theme Application
extension SettingsStore {
    /// Applies the theme to the app's appearance
    func applyTheme(_ theme: Theme) {
        DispatchQueue.main.async {
            switch theme {
            case .system:
                NSApp.appearance = nil
            case .light:
                NSApp.appearance = NSAppearance(named: .aqua)
            case .dark:
                NSApp.appearance = NSAppearance(named: .darkAqua)
            }
        }
    }

    /// Call this on app launch to apply saved theme
    func applyCurrentTheme() {
        applyTheme(settings.theme)
    }
}
