import Foundation
import CryptoKit

final class MacOSCrypto: Sendable {
    static let shared = MacOSCrypto()

    func generatePrivateKey() -> P256.KeyAgreement.PrivateKey {
        return P256.KeyAgreement.PrivateKey()
    }

    func deriveSymmetricKey(privateKey: P256.KeyAgreement.PrivateKey, remotePublicKeyDer: Data, pin: String) throws -> SymmetricKey {
        let remotePublicKey = try P256.KeyAgreement.PublicKey(derRepresentation: remotePublicKeyDer)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: remotePublicKey)

        // Android KDF logic: SHA256(sharedSecret || pin)
        // Swift equivalent using standard Data buffers:
        let sharedSecretBytes = sharedSecret.withUnsafeBytes { Data($0) }
        guard let pinData = pin.data(using: .utf8) else {
            throw CryptoError.invalidPin
        }

        var hasher = SHA256()
        hasher.update(data: sharedSecretBytes)
        hasher.update(data: pinData)
        let digest = hasher.finalize()

        return SymmetricKey(data: digest)
    }

    func decryptPayload(ivBase64: String, ciphertextBase64: String, tagBase64: String, key: SymmetricKey) throws -> String {
        guard let iv = Data(base64Encoded: ivBase64),
              let ciphertext = Data(base64Encoded: ciphertextBase64),
              let tag = Data(base64Encoded: tagBase64) else {
            throw CryptoError.invalidBase64
        }

        let nonce = try AES.GCM.Nonce(data: iv)
        let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ciphertext, tag: tag)
        let decryptedData = try AES.GCM.open(sealedBox, using: key)

        guard let plaintext = String(data: decryptedData, encoding: .utf8) else {
            throw CryptoError.decryptionFailed
        }
        return plaintext
    }

    enum CryptoError: Error {
        case invalidPin
        case invalidBase64
        case decryptionFailed
    }
}
