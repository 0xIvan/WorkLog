import AppKit
import SwiftUI

@main
struct WorklogApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Worklog", id: "dashboard") {
            DashboardView()
                .environmentObject(appDelegate.appState)
        }
        .defaultSize(width: 1_020, height: 720)
    }
}
