import Testing
import Foundation
@testable import MacMirror

@Suite("UpdateManager Tests")
struct UpdateManagerTests {

    @Test("Release channel detection based on version string")
    func testReleaseChannelDetection() {
        #expect(ReleaseChannel.channel(for: "1.0.0") == .stable)
        #expect(ReleaseChannel.channel(for: "1.0.1") == .stable)
        #expect(ReleaseChannel.channel(for: "v2.0.0") == .stable)
        #expect(ReleaseChannel.channel(for: "1.0.1-beta") == .beta)
        #expect(ReleaseChannel.channel(for: "1.0.1-beta.2") == .beta)
        #expect(ReleaseChannel.channel(for: "2.0.0.beta1") == .beta)
        #expect(ReleaseChannel.channel(for: "dev.20260924.abcdef") == .dev)
        #expect(ReleaseChannel.channel(for: "dev") == .dev)
        #expect(ReleaseChannel.channel(for: "1.0.0-dev.1") == .dev)
    }

    @Test("Channel cask names and raw cask URLs")
    func testChannelCaskMetadata() {
        #expect(ReleaseChannel.stable.caskName == "macmirror")
        #expect(ReleaseChannel.beta.caskName == "macmirror@beta")
        #expect(ReleaseChannel.dev.caskName == "macmirror@dev")

        #expect(ReleaseChannel.stable.caskRawUrl.absoluteString == "https://raw.githubusercontent.com/angelvelasquezdev/homebrew-tap/main/Casks/macmirror.rb")
        #expect(ReleaseChannel.beta.caskRawUrl.absoluteString == "https://raw.githubusercontent.com/angelvelasquezdev/homebrew-tap/main/Casks/macmirror@beta.rb")
        #expect(ReleaseChannel.dev.caskRawUrl.absoluteString == "https://raw.githubusercontent.com/angelvelasquezdev/homebrew-tap/main/Casks/macmirror@dev.rb")
    }

    @Test("Parse cask version from Ruby file content")
    func testParseCaskVersion() {
        let sampleCask = """
        cask "macmirror" do
          version "1.0.2"
          sha256 "abcdef1234567890"

          url "https://github.com/angelvelasquezdev/mac-mirror-macos/releases/download/v#{version}/MacMirror-v#{version}.dmg"
          name "MacMirror"
        end
        """

        let parsed = UpdateManager.parseCaskVersion(from: sampleCask)
        #expect(parsed == "1.0.2")

        let sampleSingleQuotes = "cask 'macmirror' do\n  version '2.1.0-beta.3'\nend"
        #expect(UpdateManager.parseCaskVersion(from: sampleSingleQuotes) == "2.1.0-beta.3")

        let sampleInvalid = "cask 'macmirror' do\n  name 'MacMirror'\nend"
        #expect(UpdateManager.parseCaskVersion(from: sampleInvalid) == nil)
    }

    @Test("Semantic version comparison for standard releases")
    func testSemanticVersionComparisonStandard() {
        // Newer versions
        #expect(UpdateManager.isVersion("1.0.1", newerThan: "1.0.0") == true)
        #expect(UpdateManager.isVersion("1.1.0", newerThan: "1.0.9") == true)
        #expect(UpdateManager.isVersion("2.0.0", newerThan: "1.99.99") == true)
        #expect(UpdateManager.isVersion("v1.0.2", newerThan: "1.0.1") == true)
        #expect(UpdateManager.isVersion("1.0.2", newerThan: "v1.0.1") == true)

        // Older or equal versions
        #expect(UpdateManager.isVersion("1.0.0", newerThan: "1.0.1") == false)
        #expect(UpdateManager.isVersion("1.0.0", newerThan: "1.0.0") == false)
        #expect(UpdateManager.isVersion("1.0.0", newerThan: "v1.0.0") == false)
        #expect(UpdateManager.isVersion("1.0", newerThan: "1.0.0") == false)
        #expect(UpdateManager.isVersion("", newerThan: "1.0.0") == false)
    }

    @Test("Semantic version comparison for pre-releases and beta")
    func testSemanticVersionComparisonBeta() {
        // Stable is newer than beta with same core numbers
        #expect(UpdateManager.isVersion("1.0.1", newerThan: "1.0.1-beta.1") == true)
        #expect(UpdateManager.isVersion("1.0.1-beta.1", newerThan: "1.0.1") == false)

        // Beta increment
        #expect(UpdateManager.isVersion("1.0.1-beta.2", newerThan: "1.0.1-beta.1") == true)
        #expect(UpdateManager.isVersion("1.0.1-beta.1", newerThan: "1.0.1-beta.2") == false)
        #expect(UpdateManager.isVersion("1.0.2-beta.1", newerThan: "1.0.1-beta.3") == true)
    }

    @Test("Semantic version comparison for develop rolling builds")
    func testSemanticVersionComparisonDev() {
        #expect(UpdateManager.isVersion("dev.20260925.100", newerThan: "dev.20260924.900") == true)
        #expect(UpdateManager.isVersion("dev.20260924.100", newerThan: "dev.20260925.900") == false)
        #expect(UpdateManager.isVersion("dev.20260925.200", newerThan: "dev.20260925.100") == true)
        #expect(UpdateManager.isVersion("dev.20260925.100", newerThan: "dev.20260925.100") == false)
    }

    @Test("Fallback release URLs per channel")
    func testFallbackReleaseUrls() {
        #expect(ReleaseChannel.stable.fallbackReleaseUrl.absoluteString == "https://github.com/angelvelasquezdev/mac-mirror-macos/releases")
        #expect(ReleaseChannel.beta.fallbackReleaseUrl.absoluteString == "https://github.com/angelvelasquezdev/mac-mirror-macos/releases")
        #expect(ReleaseChannel.dev.fallbackReleaseUrl.absoluteString == "https://github.com/angelvelasquezdev/mac-mirror-macos/releases/tag/dev")
    }

    @Test("UpdateInfo model initialization and equality")
    func testUpdateInfo() {
        let info1 = UpdateInfo(
            availableVersion: "1.0.2",
            currentVersion: "1.0.1",
            channel: .stable,
            caskName: "macmirror",
            releaseUrl: URL(string: "https://github.com/angelvelasquezdev/mac-mirror-macos/releases")!
        )
        let info2 = UpdateInfo(
            availableVersion: "1.0.2",
            currentVersion: "1.0.1",
            channel: .stable,
            caskName: "macmirror",
            releaseUrl: URL(string: "https://github.com/angelvelasquezdev/mac-mirror-macos/releases")!
        )
        #expect(info1 == info2)
    }

    @Test("Detect installed Homebrew cask and executable")
    func testDetectInstalledHomebrewCask() {
        if UpdateManager.isHomebrewInstalled {
            #expect(UpdateManager.findBrewExecutablePath() != nil)
        }
        // If macmirror@dev is in Caskroom, detectInstalledCask() should find it
        let detected = UpdateManager.detectInstalledCask()
        if FileManager.default.fileExists(atPath: "/opt/homebrew/Caskroom/macmirror@dev") {
            #expect(detected == "macmirror@dev")
        }
    }
}
