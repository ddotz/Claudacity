// MARK: - Imports
import SwiftUI

// MARK: - Settings View
struct SettingsView: View {
    // MARK: Properties
    @ObservedObject private var settingsStore = Dependencies.shared.settingsStore

    // MARK: Body
    var body: some View {
        TabView {
            AppearanceSettingsView(settingsStore: settingsStore)
                .tabItem {
                    Label(String(localized: "settings.appearance"), systemImage: "paintbrush")
                }

            NotificationSettingsView(settingsStore: settingsStore)
                .tabItem {
                    Label(String(localized: "settings.notifications"), systemImage: "bell")
                }

            GeneralSettingsView(settingsStore: settingsStore)
                .tabItem {
                    Label(String(localized: "settings.general"), systemImage: "gearshape")
                }
        }
        .frame(width: 450, height: 300)
        .preferredColorScheme(settingsStore.theme.colorScheme)
        .onAppear {
            // 설정창이 열릴 때 앱을 포그라운드로
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Appearance Settings
struct AppearanceSettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.colorScheme) private var systemColorScheme

    var body: some View {
        Form {
            // Theme Section
            Section(String(localized: "settings.theme")) {
                ThemePickerView(selectedTheme: Binding(
                    get: { settingsStore.theme },
                    set: { settingsStore.theme = $0 }
                ))
            }

            // Icon Style Section
            Section(String(localized: "settings.icon_style")) {
                Picker(String(localized: "settings.icon"), selection: Binding(
                    get: { settingsStore.iconStyle },
                    set: { settingsStore.iconStyle = $0 }
                )) {
                    ForEach(IconStyle.allCases) { style in
                        if style == .claudacity {
                            // Claudacity 시그니처 아이콘
                            Label {
                                Text(style.displayName)
                            } icon: {
                                Image(nsImage: IconGenerator.shared.createGaugeIcon(forPercentage: 75))
                                    .renderingMode(.template)
                            }
                            .tag(style)
                        } else {
                            Label(style.displayName, systemImage: style.systemImageName)
                                .tag(style)
                        }
                    }
                }

                // Icon Preview
                HStack {
                    Text(String(localized: "settings.preview"))
                    Spacer()
                    if settingsStore.iconStyle == .claudacity {
                        // Claudacity 시그니처 아이콘 (75% 게이지)
                        Image(nsImage: IconGenerator.shared.createGaugeIcon(forPercentage: 75))
                            .renderingMode(.template)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    } else {
                        Image(systemName: settingsStore.iconStyle.systemImageName)
                            .font(.title2)
                            .foregroundColor(.accentColor)
                    }
                }
            }

            // Display Section
            Section(String(localized: "settings.display_options")) {
                Toggle(String(localized: "settings.show_percentage"), isOn: Binding(
                    get: { settingsStore.showPercentage },
                    set: { settingsStore.showPercentage = $0 }
                ))

                Toggle(String(localized: "settings.show_reset_time"), isOn: Binding(
                    get: { settingsStore.showResetTime },
                    set: { settingsStore.showResetTime = $0 }
                ))

                Picker(String(localized: "settings.time_format"), selection: Binding(
                    get: { settingsStore.resetTimeFormat },
                    set: { settingsStore.resetTimeFormat = $0 }
                )) {
                    ForEach(ResetTimeFormat.allCases) { format in
                        Text(format.displayName).tag(format)
                    }
                }
                .disabled(!settingsStore.showResetTime)

                Toggle(String(localized: "settings.show_progress_bar"), isOn: Binding(
                    get: { settingsStore.enableAnimations },
                    set: { settingsStore.enableAnimations = $0 }
                ))

                Picker(String(localized: "settings.display_mode"), selection: Binding(
                    get: { settingsStore.displayMode },
                    set: { settingsStore.displayMode = $0 }
                )) {
                    ForEach(DisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Theme Picker View
struct ThemePickerView: View {
    @Binding var selectedTheme: Theme

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Theme.allCases) { theme in
                Button {
                    selectedTheme = theme
                } label: {
                    HStack(spacing: 6) {
                        themeIcon(for: theme)
                        Text(theme.displayName)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedTheme == theme ? Color.accentColor : Color.clear)
                    )
                    .foregroundColor(selectedTheme == theme ? .white : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
    }

    @ViewBuilder
    private func themeIcon(for theme: Theme) -> some View {
        switch theme {
        case .system:
            Image(systemName: "circle.lefthalf.filled")
        case .light:
            Image(systemName: "sun.max")
        case .dark:
            Image(systemName: "moon")
        }
    }
}

// MARK: - Notification Settings
struct NotificationSettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var lowThresholdText: String = ""
    @State private var criticalThresholdText: String = ""

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "settings.low_notification"), isOn: Binding(
                    get: { settingsStore.settings.enableLowNotification },
                    set: { newValue in settingsStore.update { $0.enableLowNotification = newValue } }
                ))

                if settingsStore.settings.enableLowNotification {
                    HStack {
                        Text(String(localized: "settings.threshold"))
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("", text: $lowThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .onAppear {
                                lowThresholdText = "\(settingsStore.lowThreshold)"
                            }
                            .onChange(of: lowThresholdText) { _, newValue in
                                if let value = Int(newValue), value >= 1, value <= 99 {
                                    settingsStore.lowThreshold = value
                                }
                            }
                        Text("%")
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 16)
                }
            }

            Section {
                Toggle(String(localized: "settings.critical_notification"), isOn: Binding(
                    get: { settingsStore.settings.enableCriticalNotification },
                    set: { newValue in settingsStore.update { $0.enableCriticalNotification = newValue } }
                ))

                if settingsStore.settings.enableCriticalNotification {
                    HStack {
                        Text(String(localized: "settings.threshold"))
                            .foregroundColor(.secondary)
                        Spacer()
                        TextField("", text: $criticalThresholdText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .multilineTextAlignment(.trailing)
                            .onAppear {
                                criticalThresholdText = "\(settingsStore.criticalThreshold)"
                            }
                            .onChange(of: criticalThresholdText) { _, newValue in
                                if let value = Int(newValue), value >= 1, value <= 99 {
                                    settingsStore.criticalThreshold = value
                                }
                            }
                        Text("%")
                            .foregroundColor(.secondary)
                    }
                    .padding(.leading, 16)
                }
            }

        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - General Settings
struct GeneralSettingsView: View {
    @ObservedObject var settingsStore: SettingsStore
    @State private var cachedPath: String?
    @State private var showResetConfirmation = false

    private var refreshOptions: [(String, TimeInterval)] {
        [
            (String(localized: "time.5min"), 300),
            (String(localized: "time.10min"), 600),
            (String(localized: "time.15min"), 900),
            (String(localized: "time.30min"), 1800)
        ]
    }

    var body: some View {
        Form {
            // Startup Section
            Section(String(localized: "settings.startup")) {
                Toggle(String(localized: "settings.launch_at_login"), isOn: Binding(
                    get: { settingsStore.launchAtLogin },
                    set: { settingsStore.launchAtLogin = $0 }
                ))
                .help(String(localized: "settings.launch_help"))
            }

            // Refresh Section
            Section(String(localized: "settings.refresh")) {
                Picker(String(localized: "settings.refresh_interval"), selection: Binding(
                    get: { settingsStore.refreshInterval },
                    set: { settingsStore.refreshInterval = $0 }
                )) {
                    ForEach(refreshOptions, id: \.1) { option in
                        Text(option.0).tag(option.1)
                    }
                }
            }

            // CLI Path Section
            Section("Claude CLI") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Cached Path:")
                            .foregroundColor(.secondary)
                        Spacer()
                    }

                    if let path = cachedPath {
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                    } else {
                        Text("Not set (will scan on next usage)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .italic()
                    }

                    Button {
                        showResetConfirmation = true
                    } label: {
                        Label("Reset CLI Path", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.link)
                    .disabled(cachedPath == nil)
                    .help("Reset cached CLI path. App will rescan on next usage.")
                }
            }

            // About Section
            Section(String(localized: "settings.about")) {
                HStack {
                    Text(String(localized: "settings.version"))
                    Spacer()
                    Text(Bundle.main.appVersion)
                        .foregroundColor(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            updateCachedPath()
        }
        .alert("Reset CLI Path?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                resetCLIPath()
            }
        } message: {
            Text("This will clear the cached CLI path. The app will rescan for the Claude CLI on next usage.")
        }
    }

    private func updateCachedPath() {
        cachedPath = Dependencies.shared.cliUsageService.getCachedClaudePath()
    }

    private func resetCLIPath() {
        Dependencies.shared.cliUsageService.resetClaudePath()
        updateCachedPath()
    }

    private func formatTokens(_ tokens: Int64) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM tokens/5h", Double(tokens) / 1_000_000)
        } else if tokens >= 1_000 {
            return String(format: "%.0fK tokens/5h", Double(tokens) / 1_000)
        }
        return "\(tokens) tokens/5h"
    }
}

// MARK: - Bundle Extension
extension Bundle {
    var appVersion: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    var buildNumber: String {
        infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
}

// MARK: - Preview
#Preview {
    SettingsView()
}
