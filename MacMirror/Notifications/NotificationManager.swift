import Foundation
import UserNotifications
import Intents

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationManager()

    private let iconCacheDir: URL = {
        let baseDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = baseDir.appendingPathComponent("MacMirror/NotificationIcons", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if granted {
                print("macOS Notification permission granted.")
            } else if let error = error {
                print("macOS Notification permission authorization error: \(error)")
            }
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

        var finalContent: UNNotificationContent = content

        if let appIconBase64 = appIconBase64,
           !appIconBase64.isEmpty,
           let iconData = Data(base64Encoded: appIconBase64) {
            
            // 1. Save icon to cache directory and attach as UNNotificationAttachment
            // This ensures macOS Notification Center displays the Android app icon alongside the banner
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
                finalContent = content
            } catch {
                print("Failed to attach app icon attachment: \(error)")
            }

            // 2. Also configure Communication Notification intent with avatar (for supported configurations)
            let avatarImage = INImage(imageData: iconData)
            let senderName = title.isEmpty ? appName : title
            let sender = INPerson(
                personHandle: INPersonHandle(value: appName, type: .unknown),
                nameComponents: nil,
                displayName: senderName,
                image: avatarImage,
                contactIdentifier: nil,
                customIdentifier: nil
            )

            let intent = INSendMessageIntent(
                recipients: nil,
                outgoingMessageType: .outgoingMessageText,
                content: text,
                speakableGroupName: nil,
                conversationIdentifier: id,
                serviceName: appName,
                sender: sender,
                attachments: nil
            )

            if let updated = try? content.updating(from: intent) {
                finalContent = updated
            }
        }

        let request = UNNotificationRequest(
            identifier: id,
            content: finalContent,
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

    // Handle notification click: Dismiss the notification immediately and prevent app window activation
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        print("UNUserNotificationCenterDelegate: Notification clicked (\(identifier)). Dismissing and discarding.")
        
        // Remove it from the notification center list
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [identifier])
        
        completionHandler()
    }
}
