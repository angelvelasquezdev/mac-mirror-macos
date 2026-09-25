import Foundation
import Combine
import CryptoKit
import SwiftUI
import UserNotifications

@MainActor
class MenuBarViewModel: ObservableObject {
    static let shared = MenuBarViewModel()

    @Published var isPaired: Bool = false
    @Published var isClientConnected: Bool = false
    @Published var notificationPermissionGranted: Bool = true
    @Published var pairedDeviceName: String?
    @Published var pairingPin: String = ""
    @Published var localIP: String = "Unknown"
    @Published var recentNotifications: [NotificationLog] = []

    enum RemoteTestStatus: Equatable {
        case idle
        case requesting
        case success(String)
        case error(String)
    }

    @Published var remoteTestStatus: RemoteTestStatus = .idle
    @Published var companionCompatibilityWarning: String? = nil

    @Published var availableUpdate: UpdateInfo? = nil
    @Published var isCheckingForUpdates: Bool = false
    @Published var isUpgradingWithBrew: Bool = false
    @Published var brewUpgradeStatusMessage: String? = nil

    private let updateManager = UpdateManager.shared
    private var cancellables = Set<AnyCancellable>()

    private let server = HTTPServer()
    private let wsServer = WebSocketServer()
    private let publisher = BonjourPublisher()
    private var lastClientActivity: Date = .distantPast
    
    // Ephemeral pairing session state
    private var ephemeralPrivateKey: P256.KeyAgreement.PrivateKey?
    private var clientPublicKeyDer: Data?
    private var clientDeviceName: String?

    struct NotificationLog: Identifiable, Equatable {
        let id: UUID
        let notificationId: String
        let appName: String
        let title: String
        let text: String
        let timestamp: Date
        let appIconBase64: String?

        init(
            id: UUID = UUID(),
            notificationId: String,
            appName: String,
            title: String,
            text: String,
            timestamp: Date = Date(),
            appIconBase64: String?
        ) {
            self.id = id
            self.notificationId = notificationId
            self.appName = appName
            self.title = title
            self.text = text
            self.timestamp = timestamp
            self.appIconBase64 = appIconBase64
        }
    }

    init() {
        self.isPaired = KeychainHelper.shared.retrieveKey() != nil
        self.pairedDeviceName = UserDefaults.standard.string(forKey: "pairedDeviceName")
        self.localIP = getLocalIPAddress() ?? "127.0.0.1"
        
        generateNewPin()
        setupServerHandlers()
        setupWebSocketHandlers()
        
        // Request macOS native notification permission on startup and check status
        NotificationManager.shared.requestPermission()
        refreshNotificationPermission()
        
        // Start network listener, WebSocket listener and Bonjour publishing
        do {
            try server.start()
            wsServer.start()
            publisher.startPublishing(port: Int(server.port))
        } catch {
            print("Failed to initialize networking stack: \(error)")
        }

        // Update Manager subscriptions and background scheduling
        updateManager.$availableUpdate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] update in
                self?.availableUpdate = update
            }
            .store(in: &cancellables)

        updateManager.$isChecking
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isChecking in
                self?.isCheckingForUpdates = isChecking
            }
            .store(in: &cancellables)

        updateManager.$isUpgrading
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isUpgrading in
                self?.isUpgradingWithBrew = isUpgrading
            }
            .store(in: &cancellables)

        updateManager.$upgradeStatusMessage
            .receive(on: DispatchQueue.main)
            .sink { [weak self] msg in
                self?.brewUpgradeStatusMessage = msg
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .macMirrorUpdateNotificationClicked)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.promptOrStartUpgrade()
            }
            .store(in: &cancellables)

        updateManager.startBackgroundScheduler()
    }
    
    func refreshNotificationPermission() {
        NotificationManager.shared.checkAuthorizationStatus { [weak self] status in
            Task { @MainActor in
                self?.notificationPermissionGranted = (status == .authorized || status == .provisional)
            }
        }
    }

    func generateNewPin() {
        // Generate a cryptographically secure random 6-digit PIN
        let pinVal = Int.random(in: 100000...999999)
        self.pairingPin = String(pinVal)
        self.ephemeralPrivateKey = MacOSCrypto.shared.generatePrivateKey()
        self.clientPublicKeyDer = nil
        self.clientDeviceName = nil
    }

    func unpair(notifyClient: Bool = true) {
        if notifyClient {
            wsServer.broadcast(message: "{\"action\":\"unpair\"}")
        }
        KeychainHelper.shared.deleteKey()
        UserDefaults.standard.removeObject(forKey: "pairedDeviceName")
        
        DispatchQueue.main.async {
            self.isPaired = false
            self.pairedDeviceName = nil
            self.companionCompatibilityWarning = nil
            self.recentNotifications.removeAll()
            self.generateNewPin()
        }
    }

    func clearAllNotifications() {
        self.recentNotifications.removeAll()
    }

    func uninstall() {
        // 1. Notify connected companion and unpair cleanly
        unpair(notifyClient: true)

        // 2. Clear UserDefaults for current bundle identifier domain
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
            UserDefaults.standard.synchronize()
        }

        // 3. Clear Application Support directory if exists
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let appDirectory = appSupportURL.appendingPathComponent("MacMirror", isDirectory: true)
            if fileManager.fileExists(atPath: appDirectory.path) {
                try? fileManager.removeItem(at: appDirectory)
            }
        }

        // 4. If installed via Homebrew Cask, uninstall via brew
        if let installedCask = UpdateManager.detectInstalledCask() {
            updateManager.uninstallViaHomebrew(caskName: installedCask)
            return
        }

        // 5. Otherwise, move app bundle to Trash and terminate
        let bundleURL = Bundle.main.bundleURL
        NSWorkspace.shared.recycle([bundleURL]) { _, _ in
            DispatchQueue.main.async {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func setupServerHandlers() {
        // 1. Handle POST /pair/initiate
        server.onInitiatePair = { [weak self] requestData in
            guard let self = self else {
                return (500, Data("{\"error\":\"Internal Server Error\"}".utf8))
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]
                guard let clientPubBase64 = json?["client_ephemeral_pub_key"] as? String,
                      let pubKeyData = Data(base64Encoded: clientPubBase64),
                      let deviceName = json?["device_name"] as? String else {
                    return (400, Data("{\"error\":\"Invalid initiate parameters\"}".utf8))
                }
                
                // Save client handshake state
                self.clientPublicKeyDer = pubKeyData
                self.clientDeviceName = deviceName
                
                let clientProtocol = json?["protocol_version"] as? Int
                let clientAppVer = json?["app_version"] as? String
                let compatResult = CompatibilityManager.checkCompatibility(
                    peerProtocolVersion: clientProtocol,
                    peerAppVersion: clientAppVer
                )

                Task { @MainActor in
                    if compatResult.requiresCompanionUpdate {
                        self.companionCompatibilityWarning = compatResult.peerAppVersion
                        self.showCompatibilityNotification(companionVersion: compatResult.peerAppVersion)
                    } else {
                        self.companionCompatibilityWarning = nil
                    }
                }

                // Fetch our ephemeral public key
                guard let myPrivateKey = self.ephemeralPrivateKey else {
                    return (500, Data("{\"error\":\"Pairing session not initialized\"}".utf8))
                }
                let myPubDER = myPrivateKey.publicKey.derRepresentation
                let myPubBase64 = myPubDER.base64EncodedString()
                
                let responseJson: [String: Any] = [
                    "server_ephemeral_pub_key": myPubBase64,
                    "device_name": Host.current().localizedName ?? "MacMirror Server",
                    "protocol_version": CompatibilityManager.currentProtocolVersion,
                    "app_version": CompatibilityManager.currentAppVersion
                ]
                
                let responseData = try JSONSerialization.data(withJSONObject: responseJson)
                return (200, responseData)
                
            } catch {
                return (400, Data("{\"error\":\"Invalid JSON\"}".utf8))
            }
        }
        
        // 2. Handle POST /pair/confirm
        server.onConfirmPair = { [weak self] requestData in
            guard let self = self else {
                return (500, Data("{\"error\":\"Internal Server Error\"}".utf8))
            }
            
            do {
                let json = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]
                guard let iv = json?["iv"] as? String,
                      let ciphertext = json?["ciphertext"] as? String,
                      let tag = json?["tag"] as? String else {
                    return (400, Data("{\"error\":\"Invalid confirm parameters\"}".utf8))
                }
                
                guard let myPrivateKey = self.ephemeralPrivateKey,
                      let clientPubDer = self.clientPublicKeyDer,
                      let clientName = self.clientDeviceName else {
                    return (400, Data("{\"error\":\"No active pairing session\"}".utf8))
                }
                
                // Derive the key using ECDH shared secret + PIN
                let sessionKey = try MacOSCrypto.shared.deriveSymmetricKey(
                    privateKey: myPrivateKey,
                    remotePublicKeyDer: clientPubDer,
                    pin: self.pairingPin
                )
                
                // Attempt to decrypt verification string
                let decrypted = try MacOSCrypto.shared.decryptPayload(
                    ivBase64: iv,
                    ciphertextBase64: ciphertext,
                    tagBase64: tag,
                    key: sessionKey
                )
                
                if decrypted.hasPrefix("MacMirrorVerify") {
                    // Extract session key bytes to store in Keychain
                    let keyBytes = sessionKey.withUnsafeBytes { Data($0) }
                    KeychainHelper.shared.saveKey(keyData: keyBytes)
                    UserDefaults.standard.set(clientName, forKey: "pairedDeviceName")
                    
                    DispatchQueue.main.async {
                        self.isPaired = true
                        self.pairedDeviceName = clientName
                    }
                    
                    return (200, Data("{\"success\":true}".utf8))
                } else {
                    return (401, Data("{\"error\":\"Verification text mismatch\"}".utf8))
                }
                
            } catch {
                print("Pairing confirmation failed: \(error)")
                return (401, Data("{\"error\":\"Authentication failed\"}".utf8))
            }
        }
        
        // 3. Handle POST /notification
        server.onNotification = { [weak self] requestData in
            guard let self = self else {
                return (500, Data("{\"error\":\"Internal Server Error\"}".utf8))
            }
            
            var notificationId: String? = nil
            if Thread.isMainThread {
                notificationId = self.processEncryptedNotification(requestData: requestData)
            } else {
                DispatchQueue.main.sync {
                    notificationId = self.processEncryptedNotification(requestData: requestData)
                }
            }
            let idStr = notificationId ?? ""
            return (200, Data("{\"status\":\"ok\",\"id\":\"\(idStr)\"}".utf8))
        }

        // 4. Handle POST /pair/unpair
        server.onUnpair = { [weak self] _ in
            guard let self = self else {
                return (500, Data("{\"error\":\"Internal Server Error\"}".utf8))
            }
            Task { @MainActor in
                self.unpair(notifyClient: false)
            }
            return (200, Data("{\"success\":true}".utf8))
        }

        // 5. Handle GET /status
        server.onStatus = { [weak self] headers in
            guard let self = self else {
                return (500, Data("{\"error\":\"Internal Server Error\"}".utf8))
            }
            
            let clientProtocol = headers["x-protocol-version"].flatMap { Int($0) }
            let clientAppVer = headers["x-app-version"]
            let compatResult = CompatibilityManager.checkCompatibility(
                peerProtocolVersion: clientProtocol,
                peerAppVersion: clientAppVer
            )
            
            Task { @MainActor in
                self.lastClientActivity = Date()
                if compatResult.requiresCompanionUpdate {
                    if self.companionCompatibilityWarning == nil {
                        self.showCompatibilityNotification(companionVersion: compatResult.peerAppVersion)
                    }
                    self.companionCompatibilityWarning = compatResult.peerAppVersion
                } else {
                    self.companionCompatibilityWarning = nil
                }
            }
            let isCurrentlyPaired = self.isPaired
            let pairedName = self.pairedDeviceName ?? ""
            let statusJson: [String: Any] = [
                "paired": isCurrentlyPaired,
                "deviceName": pairedName,
                "protocol_version": CompatibilityManager.currentProtocolVersion,
                "app_version": CompatibilityManager.currentAppVersion
            ]
            let statusData = (try? JSONSerialization.data(withJSONObject: statusJson)) ?? Data("{\"status\":\"ok\"}".utf8)
            return (200, statusData)
        }
    }

    func showCompatibilityNotification(companionVersion: String) {
        NotificationManager.shared.showNotification(
            id: "macmirror_compat_warning",
            appName: "MacMirror",
            title: NSLocalizedString("compat_notification_title", comment: ""),
            text: String(format: NSLocalizedString("compat_banner_desc_android_update", comment: ""), companionVersion),
            appIconBase64: nil
        )
    }

    func dismissCompatibilityWarning() {
        self.companionCompatibilityWarning = nil
    }

    func dismissUpdateBanner() {
        updateManager.dismissAvailableUpdate()
    }

    func checkForUpdates(manual: Bool = false) {
        Task { @MainActor in
            let result = await updateManager.checkForUpdates()
            if manual {
                self.handleManualUpdateResult(result)
            }
        }
    }

    private func handleManualUpdateResult(_ result: UpdateCheckResult) {
        NSApp.activate(ignoringOtherApps: true)
        switch result {
        case .upToDate(let currentVer):
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("update_alert_uptodate_title", comment: "")
            alert.informativeText = String(format: NSLocalizedString("update_alert_uptodate_desc", comment: ""), currentVer)
            alert.alertStyle = .informational
            alert.addButton(withTitle: NSLocalizedString("update_alert_uptodate_ok", comment: ""))
            alert.runModal()

        case .updateAvailable:
            promptOrStartUpgrade()

        case .failure(let errorMsg):
            let alert = NSAlert()
            alert.messageText = NSLocalizedString("update_alert_check_error_title", comment: "")
            alert.informativeText = String(format: NSLocalizedString("update_alert_check_error_desc", comment: ""), errorMsg)
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("update_btn_open_releases", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("update_alert_cancel", comment: ""))
            if alert.runModal() == .alertFirstButtonReturn {
                let channel = ReleaseChannel.channel(for: updateManager.currentVersion)
                NSWorkspace.shared.open(channel.fallbackReleaseUrl)
            }
        }
    }

    func promptOrStartUpgrade() {
        guard let update = availableUpdate ?? updateManager.availableUpdate else {
            return
        }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("update_alert_available_title", comment: "")

        let hasHomebrew = UpdateManager.isHomebrewInstalled
        if hasHomebrew {
            alert.informativeText = String(format: NSLocalizedString("update_alert_available_desc", comment: ""), update.availableVersion)
            alert.addButton(withTitle: NSLocalizedString("update_alert_confirm_brew", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("update_alert_download_dmg", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("update_alert_cancel", comment: ""))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                performHomebrewUpgrade(caskName: update.caskName)
            } else if response == .alertSecondButtonReturn {
                NSWorkspace.shared.open(update.releaseUrl)
            }
        } else {
            alert.informativeText = String(format: NSLocalizedString("update_alert_available_desc_no_brew", comment: ""), update.availableVersion)
            alert.addButton(withTitle: NSLocalizedString("update_alert_download_dmg", comment: ""))
            alert.addButton(withTitle: NSLocalizedString("update_alert_cancel", comment: ""))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.open(update.releaseUrl)
            }
        }
    }

    private func performHomebrewUpgrade(caskName: String) {
        Task { @MainActor in
            let result = await updateManager.upgradeViaHomebrew(caskName: caskName)
            switch result {
            case .success:
                break
            case .homebrewNotFound:
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("update_error_title", comment: "")
                alert.informativeText = NSLocalizedString("update_error_no_brew", comment: "")
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("update_alert_download_dmg", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("update_alert_cancel", comment: ""))
                if alert.runModal() == .alertFirstButtonReturn {
                    if let update = self.availableUpdate ?? self.updateManager.availableUpdate {
                        NSWorkspace.shared.open(update.releaseUrl)
                    }
                }
            case .commandFailed(_, let output):
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("update_error_title", comment: "")
                let displayError = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown error" : output
                alert.informativeText = String(format: NSLocalizedString("update_error_desc", comment: ""), displayError)
                alert.alertStyle = .warning
                alert.addButton(withTitle: NSLocalizedString("update_alert_download_dmg", comment: ""))
                alert.addButton(withTitle: NSLocalizedString("update_alert_cancel", comment: ""))
                if alert.runModal() == .alertFirstButtonReturn {
                    if let update = self.availableUpdate ?? self.updateManager.availableUpdate {
                        NSWorkspace.shared.open(update.releaseUrl)
                    }
                }
            }
        }
    }

    private func setupWebSocketHandlers() {
        wsServer.onClientCountChanged = { [weak self] count in
            Task { @MainActor in
                self?.isClientConnected = count > 0
            }
        }

        wsServer.onMessageReceived = { [weak self] message in
            guard let self = self else { return }
            Task { @MainActor in
                self.lastClientActivity = Date()
                self.isClientConnected = true
            }
            if message.contains("\"action\":\"unpair\"") {
                Task { @MainActor in
                    self.unpair(notifyClient: false)
                }
                return
            }
            guard let data = message.data(using: .utf8) else { return }
            
            Task { @MainActor in
                self.processEncryptedNotification(requestData: data)
            }
        }
    }

    @discardableResult
    private func processEncryptedNotification(requestData: Data) -> String? {
        guard self.isPaired,
              let keyData = KeychainHelper.shared.retrieveKey() else {
            print("Notification ignored: Device is not paired or symmetric key not found.")
            return nil
        }
        
        do {
            let json = try JSONSerialization.jsonObject(with: requestData) as? [String: Any]
            guard let iv = json?["iv"] as? String,
                  let ciphertext = json?["ciphertext"] as? String,
                  let tag = json?["tag"] as? String else {
                print("Failed to parse notification payload: missing required envelope parameters.")
                return nil
            }
            
            let sessionKey = SymmetricKey(data: keyData)
            let decryptedText = try MacOSCrypto.shared.decryptPayload(
                ivBase64: iv,
                ciphertextBase64: ciphertext,
                tagBase64: tag,
                key: sessionKey
            )
            
            // Parse the decrypted inner notification JSON
            guard let innerData = decryptedText.data(using: .utf8),
                  let innerJson = try JSONSerialization.jsonObject(with: innerData) as? [String: Any] else {
                print("Failed to decode inner notification content.")
                return nil
            }
            
            let id = innerJson["id"] as? String ?? UUID().uuidString
            let appName = innerJson["appName"] as? String ?? "Android"
            let title = innerJson["title"] as? String ?? ""
            let text = innerJson["text"] as? String ?? ""
            let appIcon = innerJson["appIcon"] as? String ?? ""
            
            // Display alert natively on macOS
            NotificationManager.shared.showNotification(
                id: id,
                appName: appName,
                title: title,
                text: text,
                appIconBase64: appIcon
            )
            
            let log = NotificationLog(
                notificationId: id,
                appName: appName,
                title: title,
                text: text,
                timestamp: Date(),
                appIconBase64: appIcon
            )

            var updated = self.recentNotifications
            updated.removeAll(where: { $0.notificationId == id })
            updated.insert(log, at: 0)
            if updated.count > 50 {
                updated.removeLast()
            }

            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                self.recentNotifications = updated
            }
            
            // Send WebSocket ACK back to Android
            let ackJson = "{\"type\":\"ack\",\"id\":\"\(id)\",\"status\":\"ok\"}"
            self.wsServer.broadcast(message: ackJson)

            // If a remote test was requested, mark it as successful
            if self.remoteTestStatus == .requesting {
                let devName = self.pairedDeviceName ?? NSLocalizedString("fallback_android_device", comment: "")
                self.remoteTestStatus = .success(String(format: NSLocalizedString("remote_test_success", comment: ""), devName))
                self.autoResetTestStatusAfterDelay()
            }

            return id
        } catch {
            print("Notification decryption failed: \(error)")
            return nil
        }
    }

    func triggerRemoteTestNotification() {
        guard isPaired else {
            remoteTestStatus = .error(NSLocalizedString("remote_test_failed_not_connected", comment: ""))
            autoResetTestStatusAfterDelay()
            return
        }
        guard isClientConnected && wsServer.hasActiveConnections else {
            remoteTestStatus = .error(NSLocalizedString("remote_test_bridge_offline", comment: ""))
            autoResetTestStatusAfterDelay()
            return
        }

        remoteTestStatus = .requesting
        wsServer.broadcast(message: "{\"action\":\"trigger_test_notification\"}")

        Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            if self.remoteTestStatus == .requesting {
                self.remoteTestStatus = .error(NSLocalizedString("remote_test_timeout", comment: ""))
                self.autoResetTestStatusAfterDelay()
            }
        }
    }

    private func autoResetTestStatusAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 4_500_000_000)
            if self.remoteTestStatus != .requesting {
                self.remoteTestStatus = .idle
            }
        }
    }
    
    private func getLocalIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddr) == 0 {
            var ptr = ifaddr
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                guard let interface = ptr?.pointee else { continue }
                let addrFamily = interface.ifa_addr.pointee.sa_family
                // Check for IPv4
                if addrFamily == UInt8(AF_INET) {
                    let name = String(cString: interface.ifa_name)
                    if name == "en0" || name == "en1" {
                        var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                        getnameinfo(
                            interface.ifa_addr,
                            socklen_t(interface.ifa_addr.pointee.sa_len),
                            &hostname,
                            socklen_t(hostname.count),
                            nil,
                            socklen_t(0),
                            NI_NUMERICHOST
                        )
                        address = hostname.withUnsafeBufferPointer { ptr in
                            ptr.baseAddress.map { String(cString: $0) }
                        }
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}
