import AppKit
import Combine
import SwiftUI

@MainActor
final class StatusBarController: NSObject {
    private let appState: AppState
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var cancellables: Set<AnyCancellable> = []

    init(appState: AppState) {
        self.appState = appState
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        configureButton()
        configurePopover()
        bindState()
        updateButton()
    }

    private func configureButton() {
        guard let button = statusItem.button else {
            return
        }

        button.target = self
        button.action = #selector(togglePopover)
        button.font = statusTextFont()
        button.image = nil
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 260)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarContentView(
                openDashboard: { [weak appState] in
                    appState?.openDashboardWindow()
                }
            )
            .environmentObject(appState)
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(popoverDidClose),
            name: NSPopover.didCloseNotification,
            object: popover
        )
    }

    private func bindState() {
        appState.$todaySummary
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateButton()
                }
            }
            .store(in: &cancellables)
    }

    private func updateButton() {
        guard let button = statusItem.button else {
            return
        }

        button.attributedTitle = statusTitle(appState.menuBarTitle)
        button.setAccessibilityLabel("Worklog \(appState.menuBarTitle)")
    }

    private func statusTitle(_ value: String) -> NSAttributedString {
        let title = NSMutableAttributedString()

        if let image = statusImage() {
            let attachment = NSTextAttachment()
            attachment.image = image
            attachment.bounds = NSRect(x: 0, y: -2.5, width: 16, height: 16)
            title.append(NSAttributedString(attachment: attachment))
        }

        title.append(NSAttributedString(string: " "))
        title.append(
            NSAttributedString(
                string: value,
                attributes: [
                    .font: statusTextFont()
                ]
            )
        )

        return title
    }

    private func statusTextFont() -> NSFont {
        let nativeFont = NSFont.menuBarFont(ofSize: 0)

        return NSFontManager.shared.convert(nativeFont, toSize: nativeFont.pointSize + 1)
    }

    private func statusImage() -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
        let image = NSImage(
            systemSymbolName: "circle.bottomthird.split",
            accessibilityDescription: "Worklog"
        )?
            .withSymbolConfiguration(configuration)

        image?.isTemplate = true

        return image
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        button.highlight(true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func popoverDidClose() {
        statusItem.button?.highlight(false)
    }
}
