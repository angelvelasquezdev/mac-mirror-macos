import SwiftUI
import AppKit

@main
struct MacMirrorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // We declare an empty settings scene so SwiftUI doesn't open a default main window on launch
        Settings {
            EmptyView()
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Initialize the notification delegate early before launch completes
        _ = NotificationManager.shared

        // 2. Configure the app to run as an agent (hide dock icon and app menu)
        NSApp.setActivationPolicy(.accessory)

        // 2. Setup SwiftUI Popover
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient // Close when user clicks elsewhere
        popover.contentViewController = NSHostingController(rootView: ContentView())

        // 3. Setup Status Bar Menu Item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            if let iconImage = NSImage(systemSymbolName: "bell.and.waves.left.and.right", accessibilityDescription: "MacMirror")?
                .withSymbolConfiguration(config) {
                button.image = iconImage
            }
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            // Make the popover window the key window so text fields can receive focus
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}
