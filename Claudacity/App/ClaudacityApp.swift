// MARK: - Imports
import SwiftUI

// MARK: - App Entry Point
@main
struct ClaudacityApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        NSLog("[Claudacity] App init called")
    }

    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}
