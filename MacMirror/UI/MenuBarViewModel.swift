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
            self.recentNotifications.removeAll()
            self.generateNewPin()
        }
    }

    func clearAllNotifications() {
        self.recentNotifications.removeAll()
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
                
                // Fetch our ephemeral public key
                guard let myPrivateKey = self.ephemeralPrivateKey else {
                    return (500, Data("{\"error\":\"Pairing session not initialized\"}".utf8))
                }
                let myPubDER = myPrivateKey.publicKey.derRepresentation
                let myPubBase64 = myPubDER.base64EncodedString()
                
                let responseJson: [String: Any] = [
                    "server_ephemeral_pub_key": myPubBase64,
                    "device_name": Host.current().localizedName ?? "MacMirror Server"
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
        server.onStatus = { [weak self] in
            guard let self = self else {
                return (500, Data("{\"error\":\"Internal Server Error\"}".utf8))
            }
            Task { @MainActor in
                self.lastClientActivity = Date()
                self.isClientConnected = true
            }
            let isCurrentlyPaired = self.isPaired
            let pairedName = self.pairedDeviceName ?? ""
            let statusJson = "{\"paired\":\(isCurrentlyPaired),\"deviceName\":\"\(pairedName)\"}"
            return (200, Data(statusJson.utf8))
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
        guard isClientConnected else {
            remoteTestStatus = .error(NSLocalizedString("remote_test_failed_not_connected", comment: ""))
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
                        address = String(cString: hostname)
                    }
                }
            }
            freeifaddrs(ifaddr)
        }
        return address
    }
}
