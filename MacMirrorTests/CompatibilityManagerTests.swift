import Testing
import Foundation
@testable import MacMirror

@Suite struct CompatibilityManagerTests {

    @Test func testSameProtocolIsCompatible() {
        let result = CompatibilityManager.checkCompatibility(
            peerProtocolVersion: CompatibilityManager.currentProtocolVersion,
            peerAppVersion: "1.0.0"
        )
        #expect(result.isCompatible == true)
        #expect(result.requiresCompanionUpdate == false)
        #expect(result.peerAppVersion == "1.0.0")
        #expect(result.peerProtocolVersion == CompatibilityManager.currentProtocolVersion)
    }

    @Test func testLegacyPeerWithoutVersionDefaultsGracefully() {
        let result = CompatibilityManager.checkCompatibility(
            peerProtocolVersion: nil,
            peerAppVersion: nil
        )
        // Backward compatibility requirement: legacy builds must work without false alarms
        #expect(result.isCompatible == true)
        #expect(result.requiresCompanionUpdate == false)
        #expect(result.peerProtocolVersion == CompatibilityManager.defaultFallbackProtocolVersion)
        #expect(result.peerAppVersion == CompatibilityManager.defaultFallbackAppVersion)
    }

    @Test func testHigherProtocolIsCompatible() {
        // Forward compatibility: higher protocol version from peer should be accepted
        let result = CompatibilityManager.checkCompatibility(
            peerProtocolVersion: CompatibilityManager.currentProtocolVersion + 1,
            peerAppVersion: "2.0.0"
        )
        #expect(result.isCompatible == true)
        #expect(result.requiresCompanionUpdate == false)
    }

    @Test func testOlderIncompatibleProtocolTriggersUpdateRequirement() {
        // When peer protocol is strictly below minimum required
        let result = CompatibilityManager.checkCompatibility(
            peerProtocolVersion: CompatibilityManager.minCompatibleAndroidProtocol - 1,
            peerAppVersion: "0.9.0"
        )
        #expect(result.isCompatible == false)
        #expect(result.requiresCompanionUpdate == true)
        #expect(result.peerAppVersion == "0.9.0")
    }

    @Test func testReleasesUrlIsConfigured() {
        #expect(CompatibilityManager.androidReleasesUrl.absoluteString.starts(with: "https://github.com/"))
    }
}
