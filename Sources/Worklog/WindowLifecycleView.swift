import AppKit
import SwiftUI

struct WindowLifecycleView: NSViewRepresentable {
    @EnvironmentObject private var appState: AppState

    var id: String

    func makeNSView(context: Context) -> WindowLifecycleNSView {
        let view = WindowLifecycleNSView()
        view.id = id
        view.appState = appState

        return view
    }

    func updateNSView(_ nsView: WindowLifecycleNSView, context: Context) {
        nsView.id = id
        nsView.appState = appState
        nsView.attachToWindowIfNeeded()
    }
}

@MainActor
final class WindowLifecycleNSView: NSView {
    weak var appState: AppState?
    var id = ""

    private weak var trackedWindow: NSWindow?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToWindowIfNeeded()
    }

    func attachToWindowIfNeeded() {
        guard let window, trackedWindow !== window else {
            return
        }

        NotificationCenter.default.removeObserver(self)

        trackedWindow = window
        appState?.appWindowDidAppear(id: id)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: window
        )
    }

    @objc private func windowWillClose() {
        appState?.appWindowDidDisappear(id: id)
    }
}
