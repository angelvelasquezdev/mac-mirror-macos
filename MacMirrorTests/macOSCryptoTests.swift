import Testing
import Foundation
import CryptoKit
@testable import MacMirror

@Suite struct MacOSCryptoTests {

    @Test func testEphemeralKeyPairGeneration() {
        let privateKey = MacOSCrypto.shared.generatePrivateKey()
        let publicKey = privateKey.publicKey
        
        #expect(publicKey.derRepresentation.count > 0)
    }

    @Test func testECDHKeyAgreementAndDerivation() throws {
        // Generate mock client and server ephemeral key pairs
        let clientPriv = MacOSCrypto.shared.generatePrivateKey()
        let serverPriv = MacOSCrypto.shared.generatePrivateKey()

        let clientPubDer = clientPriv.publicKey.derRepresentation
        let serverPubDer = serverPriv.publicKey.derRepresentation

        // Perform ECDH and derive keys using a shared 6-digit PIN
        let pin = "987654"
        let clientDerived = try MacOSCrypto.shared.deriveSymmetricKey(
            privateKey: clientPriv,
            remotePublicKeyDer: serverPubDer,
            pin: pin
        )
        let serverDerived = try MacOSCrypto.shared.deriveSymmetricKey(
            privateKey: serverPriv,
            remotePublicKeyDer: clientPubDer,
            pin: pin
        )

        // Verify both derived keys are identical
        let clientKeyBytes = clientDerived.withUnsafeBytes { Data($0) }
        let serverKeyBytes = serverDerived.withUnsafeBytes { Data($0) }

        #expect(clientKeyBytes == serverKeyBytes)
    }

    @Test func testPayloadDecryption() throws {
        let key = SymmetricKey(size: .bits256)
        let plaintext = "Hello macOS, this is a secure notification payload!"

        // Encrypt the payload using native CryptoKit
        let nonce = AES.GCM.Nonce()
        let sealedBox = try AES.GCM.seal(Data(plaintext.utf8), using: key, nonce: nonce)

        let ivBase64 = Data(nonce).base64EncodedString()
        let ciphertextBase64 = sealedBox.ciphertext.base64EncodedString()
        let tagBase64 = sealedBox.tag.base64EncodedString()

        // Decrypt the payload using our class wrapper
        let decrypted = try MacOSCrypto.shared.decryptPayload(
            ivBase64: ivBase64,
            ciphertextBase64: ciphertextBase64,
            tagBase64: tagBase64,
            key: key
        )

        #expect(decrypted == plaintext)
    }
}
