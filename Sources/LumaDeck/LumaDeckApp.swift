import SwiftUI
import AppKit

@main
struct LumaDeckApp: App {
    @StateObject private var displays = DisplayManager()

    var body: some Scene {
        MenuBarExtra {
            DisplayPopoverView()
                .environmentObject(displays)
        } label: {
            Image(systemName: "display.2")
                .accessibilityLabel("LumaDeck")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(displays)
        }
    }
}
