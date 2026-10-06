import AppKit
import SwiftUI

@MainActor
public final class GlassPanelManager {
    public static let shared = GlassPanelManager()

    private var activePanels: Set<NSPanel> = []

    private init() {}

    public func showAlert(
        title: String,
        message: String,
        icon: GlassAlertIcon = .appIcon,
        buttons: [GlassAlertButton]
    ) {
        let panel = createFloatingPanel(width: 320, height: 250)
        
        // Wrap actions to close the panel on trigger
        let wrappedButtons = buttons.map { btn in
            GlassAlertButton(title: btn.title, role: btn.role) { [weak self, weak panel] in
                btn.action()
                if let panel = panel {
                    self?.dismiss(panel)
                }
            }
        }

        let alertView = GlassAlertView(
            title: title,
            message: message,
            icon: icon,
            buttons: wrappedButtons
        )

        let hostingController = NSHostingController(rootView: alertView)
        panel.contentViewController = hostingController

        present(panel)
    }

    public func showWhatsNew(release: WhatsNewRelease? = nil, onDismiss: (@MainActor @Sendable () -> Void)? = nil) {
        let panel = createFloatingPanel(width: 380, height: 500)

        let whatsNewView = WhatsNewView(release: release) { [weak self, weak panel] in
            onDismiss?()
            if let panel = panel {
                self?.dismiss(panel)
            }
        }

        let hostingController = NSHostingController(rootView: whatsNewView)
        panel.contentViewController = hostingController

        present(panel)
    }

    private func createFloatingPanel(width: CGFloat, height: CGFloat) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.center()
        return panel
    }

    private func present(_ panel: NSPanel) {
        activePanels.insert(panel)
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    public func dismiss(_ panel: NSPanel) {
        panel.orderOut(nil)
        panel.close()
        activePanels.remove(panel)
    }
}
