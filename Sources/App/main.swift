import AppKit
import SwiftUI

/// The KeyAwake interface: a Dock icon and one window.
/// Closing the window quits the app and clears it from the Dock. The engine carries on.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var pendingHeight: CGFloat?
    private let model = Model()

    func applicationDidFinishLaunching(_ notification: Notification) {
        LoginItem.startAgentIfNeeded()

        let hosting = NSHostingView(rootView: SettingsView(model: model) { [weak self] height in
            self?.fitWindow(toContentHeight: height)
        })
        hosting.frame = NSRect(x: 0, y: 0, width: 580, height: 740)
        hosting.layoutSubtreeIfNeeded()
        let initialHeight = max(hosting.fittingSize.height, SettingsView.minContentHeight)

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: initialHeight),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "KeyAwake"
        window.contentView = hosting
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window

        if let height = pendingHeight {
            pendingHeight = nil
            fitWindow(toContentHeight: height)
        }
    }

    /// Keeps the window exactly as tall as its content, which is what `SettingsView` reports.
    /// The top edge stays put, so the window grows downwards like a normal resize.
    private func fitWindow(toContentHeight height: CGFloat) {
        guard let window else { pendingHeight = height; return }
        let frame = window.frame
        let chrome = frame.height - window.contentLayoutRect.height
        let available = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? height + chrome
        let target = min(max(ceil(height), SettingsView.minContentHeight), available - chrome)
        guard abs(frame.height - (target + chrome)) > 1 else { return }
        window.setFrame(NSRect(x: frame.minX, y: frame.maxY - target - chrome,
                               width: frame.width, height: target + chrome),
                        display: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
