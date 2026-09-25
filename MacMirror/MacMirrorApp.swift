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

final class EventMonitor: @unchecked Sendable {
    private var monitor: Any?
    private let mask: NSEvent.EventTypeMask
    private let handler: (NSEvent?) -> Void

    init(mask: NSEvent.EventTypeMask, handler: @escaping (NSEvent?) -> Void) {
        self.mask = mask
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: handler)
    }

    func stop() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private let viewModel = MenuBarViewModel.shared
    private var eventMonitor: EventMonitor?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 1. Initialize the notification delegate early before launch completes
        _ = NotificationManager.shared

        // 2. Configure the app to run as an agent (hide dock icon and app menu)
        NSApp.setActivationPolicy(.accessory)

        // 3. Setup SwiftUI Popover with persistent shared ViewModel
        popover.delegate = self
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient // Close when user clicks elsewhere
        popover.contentViewController = NSHostingController(rootView: ContentView(viewModel: viewModel))

        // 4. Setup global event monitor to reliably close popover on clicks outside,
        // even after interacting with context menus which can desynchronize AppKit's transient tracking.
        eventMonitor = EventMonitor(mask: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.popover.isShown else { return }
                self.popover.performClose(nil)
            }
        }

        // 5. Setup Status Bar Menu Item
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

    func popoverDidClose(_ notification: Notification) {
        eventMonitor?.stop()
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
            eventMonitor?.stop()
        } else {
            viewModel.refreshNotificationPermission()
            popover.show(
                relativeTo: button.bounds,
                of: button,
                preferredEdge: .minY
            )
            // Make the popover window the key window so text fields can receive focus
            popover.contentViewController?.view.window?.makeKey()
            // Activate the application so menus, controls and focus events work on the first click
            NSApp.activate(ignoringOtherApps: true)
            eventMonitor?.start()
        }
    }
}
