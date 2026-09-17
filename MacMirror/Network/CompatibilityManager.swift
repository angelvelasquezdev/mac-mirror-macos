import Foundation

public struct CompatibilityManager: Sendable {
    /// Internal protocol version of this macOS build.
    /// Increment when introducing protocol or wire-format changes.
    public static let currentProtocolVersion: Int = 1

    /// Minimum Android protocol version required to communicate with this macOS build.
    /// Only increment if older Android versions are strictly incapable of operating with this build.
    public static let minCompatibleAndroidProtocol: Int = 1

    /// Fallback values for legacy companion apps that do not send protocol or app versions.
    public static let defaultFallbackProtocolVersion: Int = 1
    public static let defaultFallbackAppVersion: String = "1.0.0"

    /// URL to Android releases page for user updates.
    public static let androidReleasesUrl: URL = URL(string: "https://github.com/angelvelasquezdev/mac-mirror-android/releases")!

    /// Current display app version from the main bundle.
    public static var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? defaultFallbackAppVersion
    }

    public struct CompatibilityResult: Equatable, Sendable {
        public let isCompatible: Bool
        public let peerProtocolVersion: Int
        public let peerAppVersion: String
        public let requiresCompanionUpdate: Bool

        public init(
            isCompatible: Bool,
            peerProtocolVersion: Int,
            peerAppVersion: String,
            requiresCompanionUpdate: Bool
        ) {
            self.isCompatible = isCompatible
            self.peerProtocolVersion = peerProtocolVersion
            self.peerAppVersion = peerAppVersion
            self.requiresCompanionUpdate = requiresCompanionUpdate
        }
    }

    /// Validates whether the companion Android app is compatible with this macOS app.
    /// If the companion does not provide a protocol version (legacy client), it defaults
    /// gracefully to version 1.0.0 / protocol 1 without blocking or raising false alarms.
    public static func checkCompatibility(
        peerProtocolVersion: Int?,
        peerAppVersion: String?
    ) -> CompatibilityResult {
        let effectiveProtocol = peerProtocolVersion ?? defaultFallbackProtocolVersion
        let effectiveVersion: String
        if let appVer = peerAppVersion, !appVer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            effectiveVersion = appVer
        } else {
            effectiveVersion = defaultFallbackAppVersion
        }

        let isCompatible = effectiveProtocol >= minCompatibleAndroidProtocol
        let requiresCompanionUpdate = !isCompatible

        return CompatibilityResult(
            isCompatible: isCompatible,
            peerProtocolVersion: effectiveProtocol,
            peerAppVersion: effectiveVersion,
            requiresCompanionUpdate: requiresCompanionUpdate
        )
    }
}
