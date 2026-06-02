import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import WorklogCore

struct ActiveWindowReader {
    func currentSnapshot() -> ActivitySnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        let appName = application.localizedName ?? "Unknown"
        let bundleIdentifier = application.bundleIdentifier ?? ""
        let processIdentifier = application.processIdentifier
        let windowTitle = focusedWindowTitle(processIdentifier: processIdentifier)
        let chromeInfo = chromeTabInfo(bundleIdentifier: bundleIdentifier, appName: appName)

        return ActivitySnapshot(
            appName: appName,
            bundleIdentifier: bundleIdentifier,
            processIdentifier: processIdentifier,
            windowTitle: chromeInfo?.title ?? windowTitle,
            url: chromeInfo?.url,
            source: chromeInfo == nil ? .macOS : .chrome,
            isPrivate: chromeInfo?.isPrivate ?? false
        )
    }

    func accessibilityIsTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary

        AXIsProcessTrustedWithOptions(options)
    }

    private func focusedWindowTitle(processIdentifier: pid_t) -> String {
        if let title = accessibilityWindowTitle(processIdentifier: processIdentifier), !title.isEmpty {
            return title
        }

        return graphicsWindowTitle(processIdentifier: processIdentifier)
    }

    private func accessibilityWindowTitle(processIdentifier: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var focusedWindow: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindow
        )

        guard windowResult == .success, let focusedWindow else {
            return nil
        }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(
            focusedWindow as! AXUIElement,
            kAXTitleAttribute as CFString,
            &titleValue
        )

        guard titleResult == .success else {
            return nil
        }

        return titleValue as? String
    }

    private func graphicsWindowTitle(processIdentifier: pid_t) -> String {
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return ""
        }

        let window = windows.first { info in
            guard
                let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
                let layer = info[kCGWindowLayer as String] as? Int
            else {
                return false
            }

            return ownerPID == processIdentifier && layer == 0
        }

        return window?[kCGWindowName as String] as? String ?? ""
    }

    private func chromeTabInfo(bundleIdentifier: String, appName: String) -> ChromeTabInfo? {
        let normalizedBundle = bundleIdentifier.lowercased()
        let normalizedName = appName.lowercased()
        guard normalizedBundle.contains("chrome") || normalizedName.contains("chrome") else {
            return nil
        }

        let source = """
        tell application id "com.google.Chrome"
            if (count of windows) is 0 then return ""
            set windowMode to mode of front window as string
            if windowMode is "incognito" then return windowMode
            set activeTab to active tab of front window
            return windowMode & linefeed & (URL of activeTab) & linefeed & (title of activeTab)
        end tell
        """

        var error: NSDictionary?
        guard let result = NSAppleScript(source: source)?.executeAndReturnError(&error).stringValue else {
            return nil
        }

        let lines = result
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let mode = lines.first else {
            return nil
        }

        if mode.caseInsensitiveCompare("incognito") == .orderedSame {
            return ChromeTabInfo(url: nil, title: "Incognito", isPrivate: true)
        }

        return ChromeTabInfo(
            url: lines.dropFirst().first,
            title: lines.dropFirst(2).first ?? "",
            isPrivate: false
        )
    }
}

private struct ChromeTabInfo {
    var url: String?
    var title: String
    var isPrivate: Bool
}
