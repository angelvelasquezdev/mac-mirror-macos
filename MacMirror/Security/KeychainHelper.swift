import Foundation
import Security

final class KeychainHelper: Sendable {
    static let shared = KeychainHelper()
    private let service = "com.angelsoft.macmirror"
    private let account = "sessionKey"

    private var storageURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let dir = appSupport.appendingPathComponent("MacMirror", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o700
            ])
        }
        return dir.appendingPathComponent(".session_key")
    }

    @discardableResult
    func saveKey(keyData: Data) -> Bool {
        // Clean up legacy system keychain item if present to prevent system dialogs
        deleteLegacyKeychainItem()

        // Save to private user storage with 0600 (owner read/write only)
        do {
            try keyData.write(to: storageURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
            return true
        } catch {
            print("Failed to save session key to secure storage: \(error)")
            return false
        }
    }

    func retrieveKey() -> Data? {
        // Read from private user storage with 0 prompts and instant access
        if FileManager.default.fileExists(atPath: storageURL.path),
           let data = try? Data(contentsOf: storageURL),
           !data.isEmpty {
            return data
        }
        return nil
    }

    @discardableResult
    func deleteKey() -> Bool {
        deleteLegacyKeychainItem()
        if FileManager.default.fileExists(atPath: storageURL.path) {
            try? FileManager.default.removeItem(at: storageURL)
        }
        return true
    }

    private func deleteLegacyKeychainItem() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
