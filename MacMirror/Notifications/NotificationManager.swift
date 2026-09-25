import Foundation
import UserNotifications
import Intents
import AppKit

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()

    private let iconCacheDir: URL = {
        let baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = baseDir.appendingPathComponent("MacMirror/NotificationIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private var isNotificationCenterAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    override init() {
        super.init()
        if isNotificationCenterAvailable {
            UNUserNotificationCenter.current().delegate = self
        }
    }

    func requestPermission() {
        guard isNotificationCenterAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("macOS Notification permission granted.")
            } else if let error = error {
                print("macOS Notification permission authorization error: \(error)")
            }
        }
    }

    func checkAuthorizationStatus(completion: @escaping @Sendable (UNAuthorizationStatus) -> Void) {
        guard isNotificationCenterAvailable else {
            completion(.authorized)
            return
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    func showNotification(id: String, appName: String, title: String, text: String, appIconBase64: String?) {
        let content = UNMutableNotificationContent()
        
        if title.isEmpty {
            content.title = appName
        } else {
            content.title = "\(appName): \(title)"
        }
        content.body = text
        content.sound = .default

        if let appIconBase64 = appIconBase64,
           !appIconBase64.isEmpty,
           let iconData = Data(base64Encoded: appIconBase64) {
            
            // Save icon to cache directory and attach as UNNotificationAttachment
            // This displays the Android app icon alongside the banner natively in macOS
            let safeFileName = "icon_\(UUID().uuidString).png"
            let fileURL = iconCacheDir.appendingPathComponent(safeFileName)
            
            do {
                try iconData.write(to: fileURL)
                let attachment = try UNNotificationAttachment(
                    identifier: "appIcon-\(UUID().uuidString)",
                    url: fileURL,
                    options: nil
                )
                content.attachments = [attachment]
            } catch {
                print("Failed to attach app icon attachment: \(error)")
            }
        }

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Failed to post notification to UNUserNotificationCenter: \(error)")
            } else {
                print("Successfully added notification request: \(id) for \(appName) to UNUserNotificationCenter")
            }
        }

        pruneOldCachedIcons()
    }

    private func pruneOldCachedIcons() {
        DispatchQueue.global(qos: .background).async { [weak self] in
            guard let self = self else { return }
            guard let files = try? FileManager.default.contentsOfDirectory(at: self.iconCacheDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
            if files.count > 40 {
                let sorted = files.sorted {
                    let d1 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    let d2 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                    return d1 < d2
                }
                for file in sorted.prefix(files.count - 30) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
    }

    // Ensure notifications display even when the app is in focus/foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("UNUserNotificationCenterDelegate: willPresent called for \(notification.request.identifier). Requesting [.banner, .sound]")
        completionHandler([.banner, .sound])
    }

    // Handle notification click: Dismiss notification or dispatch actions
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        print("UNUserNotificationCenterDelegate: Notification clicked (\(identifier)).")
        
        // Remove it from the notification center list
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        
        if identifier.hasPrefix("macmirror-update-") {
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(name: .macMirrorUpdateNotificationClicked, object: nil)
            }
        }

        completionHandler()
    }
}

public extension Notification.Name {
    static let macMirrorUpdateNotificationClicked = Notification.Name("macMirrorUpdateNotificationClicked")
}
