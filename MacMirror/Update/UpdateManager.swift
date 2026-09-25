import Foundation
import Combine
import AppKit

public enum ReleaseChannel: String, Sendable, CaseIterable {
    case stable
    case beta
    case dev

    public static func channel(for version: String) -> ReleaseChannel {
        let trimmed = version.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.contains("-beta") || trimmed.contains(".beta") {
            return .beta
        } else if trimmed.hasPrefix("dev.") || trimmed.contains("-dev") || trimmed.contains("dev") {
            return .dev
        }
        return .stable
    }

    public var caskName: String {
        switch self {
        case .stable:
            return "macmirror"
        case .beta:
            return "macmirror@beta"
        case .dev:
            return "macmirror@dev"
        }
    }

    public var caskRawUrl: URL {
        URL(string: "https://raw.githubusercontent.com/angelvelasquezdev/homebrew-tap/main/Casks/\(caskName).rb")!
    }

    public var fallbackReleaseUrl: URL {
        switch self {
        case .stable, .beta:
            return URL(string: "https://github.com/angelvelasquezdev/mac-mirror-macos/releases")!
        case .dev:
            return URL(string: "https://github.com/angelvelasquezdev/mac-mirror-macos/releases/tag/dev")!
        }
    }
}

public struct UpdateInfo: Equatable, Sendable {
    public let availableVersion: String
    public let currentVersion: String
    public let channel: ReleaseChannel
    public let caskName: String
    public let releaseUrl: URL

    public init(
        availableVersion: String,
        currentVersion: String,
        channel: ReleaseChannel,
        caskName: String,
        releaseUrl: URL
    ) {
        self.availableVersion = availableVersion
        self.currentVersion = currentVersion
        self.channel = channel
        self.caskName = caskName
        self.releaseUrl = releaseUrl
    }
}

public enum UpdateCheckResult: Equatable, Sendable {
    case updateAvailable(UpdateInfo)
    case upToDate(currentVersion: String)
    case failure(String)
}

public enum UpgradeExecutionResult: Equatable, Sendable {
    case success
    case homebrewNotFound
    case commandFailed(exitCode: Int32, output: String)
}

@MainActor
public final class UpdateManager: ObservableObject {
    public static let shared = UpdateManager()

    @Published public private(set) var availableUpdate: UpdateInfo?
    @Published public private(set) var isChecking: Bool = false
    @Published public private(set) var isUpgrading: Bool = false
    @Published public private(set) var upgradeStatusMessage: String?
    @Published public private(set) var lastCheckDate: Date?

    private var backgroundTask: Task<Void, Never>?
    private let userDefaultsKeyLastCheck = "lastUpdateCheckDate"
    private let checkIntervalSeconds: TimeInterval = 86400 // 24 hours

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    public init() {
        if let storedDate = UserDefaults.standard.object(forKey: userDefaultsKeyLastCheck) as? Date {
            self.lastCheckDate = storedDate
        }
    }

    deinit {
        backgroundTask?.cancel()
    }

    // MARK: - Background Scheduler

    public func startBackgroundScheduler() {
        backgroundTask?.cancel()
        backgroundTask = Task { [weak self] in
            // Wait 5 seconds after startup to avoid competing with networking/Bonjour init
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }

            await self?.performPeriodicCheckIfNeeded()

            // Run check loop every 1 hour to see if 24 hours elapsed
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_600_000_000_000) // 1 hour
                guard !Task.isCancelled else { break }
                await self?.performPeriodicCheckIfNeeded()
            }
        }
    }

    private func performPeriodicCheckIfNeeded() async {
        let now = Date()
        if let lastCheck = lastCheckDate, now.timeIntervalSince(lastCheck) < checkIntervalSeconds {
            return
        }

        let result = await checkForUpdates()
        if case .updateAvailable(let update) = result {
            self.availableUpdate = update
            self.notifyUserOfAvailableUpdate(update)
        }
    }

    // MARK: - Update Checking Logic

    public func checkForUpdates() async -> UpdateCheckResult {
        isChecking = true
        defer {
            isChecking = false
            let now = Date()
            lastCheckDate = now
            UserDefaults.standard.set(now, forKey: userDefaultsKeyLastCheck)
        }

        let currentVer = currentVersion
        let channel = ReleaseChannel.channel(for: currentVer)

        do {
            let availableVer = try await fetchLatestVersionFromCask(channel: channel)
            if Self.isVersion(availableVer, newerThan: currentVer) {
                let info = UpdateInfo(
                    availableVersion: availableVer,
                    currentVersion: currentVer,
                    channel: channel,
                    caskName: channel.caskName,
                    releaseUrl: channel.fallbackReleaseUrl
                )
                self.availableUpdate = info
                return .updateAvailable(info)
            } else {
                self.availableUpdate = nil
                return .upToDate(currentVersion: currentVer)
            }
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    public func dismissAvailableUpdate() {
        self.availableUpdate = nil
    }

    private func fetchLatestVersionFromCask(channel: ReleaseChannel) async throws -> String {
        let (data, response) = try await URLSession.shared.data(from: channel.caskRawUrl)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        guard let content = String(data: data, encoding: .utf8) else {
            throw URLError(.cannotDecodeContentData)
        }

        guard let version = Self.parseCaskVersion(from: content) else {
            throw URLError(.cannotParseResponse)
        }

        return version
    }

    nonisolated public static func parseCaskVersion(from rubyContent: String) -> String? {
        // Matches: version "1.0.1" or version '1.0.1'
        let pattern = #"version\s+["']([^"']+)["']"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(rubyContent.startIndex..<rubyContent.endIndex, in: rubyContent)
        if let match = regex.firstMatch(in: rubyContent, options: [], range: nsRange),
           let versionRange = Range(match.range(at: 1), in: rubyContent) {
            return String(rubyContent[versionRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    // MARK: - Semantic Version Comparison

    nonisolated public static func isVersion(_ available: String, newerThan current: String) -> Bool {
        let a = available.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = current.trimmingCharacters(in: .whitespacesAndNewlines)

        if a.isEmpty || c.isEmpty { return false }
        if a == c { return false }

        // Dev channel handling (e.g. dev.20260925.abc vs dev.20260924.xyz)
        if a.hasPrefix("dev.") && c.hasPrefix("dev.") {
            let aComponents = a.split(separator: ".")
            let cComponents = c.split(separator: ".")
            if aComponents.count >= 2 && cComponents.count >= 2 {
                let aDate = String(aComponents[1])
                let cDate = String(cComponents[1])
                if aDate != cDate {
                    return aDate > cDate
                }
                if aComponents.count >= 3 && cComponents.count >= 3 {
                    return String(aComponents[2]) > String(cComponents[2])
                }
            }
            return a > c
        }

        // Standard semver with optional pre-release (e.g. 1.0.2 vs 1.0.1 or 1.0.2-beta.2 vs 1.0.2-beta.1)
        let aClean = a.hasPrefix("v") ? String(a.dropFirst()) : a
        let cClean = c.hasPrefix("v") ? String(c.dropFirst()) : c

        let aParts = aClean.components(separatedBy: "-")
        let cParts = cClean.components(separatedBy: "-")

        let aCore = aParts[0].split(separator: ".").compactMap { Int($0) }
        let cCore = cParts[0].split(separator: ".").compactMap { Int($0) }

        let maxCount = max(aCore.count, cCore.count)
        for i in 0..<maxCount {
            let aNum = i < aCore.count ? aCore[i] : 0
            let cNum = i < cCore.count ? cCore[i] : 0
            if aNum > cNum { return true }
            if aNum < cNum { return false }
        }

        // Core numbers are identical: check pre-release tags if any
        let aHasPre = aParts.count > 1
        let cHasPre = cParts.count > 1

        // A stable release (no prerelease) is newer than a prerelease with same core numbers
        if !aHasPre && cHasPre {
            return true
        }
        if aHasPre && !cHasPre {
            return false
        }

        if aHasPre && cHasPre {
            let aPre = aParts[1]
            let cPre = cParts[1]
            return comparePrerelease(aPre, newerThan: cPre)
        }

        return false
    }

    nonisolated private static func comparePrerelease(_ a: String, newerThan b: String) -> Bool {
        // e.g. "beta.2" vs "beta.1"
        let aTokens = a.split(separator: ".")
        let bTokens = b.split(separator: ".")

        let maxCount = max(aTokens.count, bTokens.count)
        for i in 0..<maxCount {
            if i >= aTokens.count { return false }
            if i >= bTokens.count { return true }

            let aToken = String(aTokens[i])
            let bToken = String(bTokens[i])

            if let aNum = Int(aToken), let bNum = Int(bToken) {
                if aNum != bNum { return aNum > bNum }
            } else if aToken != bToken {
                return aToken > bToken
            }
        }
        return false
    }

    // MARK: - Homebrew Binary Detection

    nonisolated public static func findBrewExecutablePath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/brew",    // Apple Silicon default
            "/usr/local/bin/brew",       // Intel default
            "/home/linuxbrew/.linuxbrew/bin/brew"
        ]

        let fm = FileManager.default
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Check if brew is in PATH environment
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.components(separatedBy: ":") {
                let potential = (dir as NSString).appendingPathComponent("brew")
                if fm.isExecutableFile(atPath: potential) {
                    return potential
                }
            }
        }

        return nil
    }

    nonisolated public static var isHomebrewInstalled: Bool {
        findBrewExecutablePath() != nil
    }

    /// Detects if MacMirror is managed by Homebrew Cask by checking Caskroom folders or installed cask names
    nonisolated public static func detectInstalledCask() -> String? {
        let caskPrefixes = [
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom"
        ]
        let candidateCasks = ["macmirror@dev", "macmirror@beta", "macmirror"]
        let fm = FileManager.default

        for prefix in caskPrefixes {
            for cask in candidateCasks {
                let caskPath = (prefix as NSString).appendingPathComponent(cask)
                if fm.fileExists(atPath: caskPath) {
                    return cask
                }
            }
        }
        return nil
    }

    /// Launches a detached background process to uninstall the cask via Homebrew and immediately terminates the current app
    public func uninstallViaHomebrew(caskName: String) {
        guard let brewPath = Self.findBrewExecutablePath() else { return }

        // Script runs in background detached, waits a brief moment for MacMirror to quit cleanly, then runs brew uninstall --cask --force
        let uninstallScript = "sleep 1 && '\(brewPath)' uninstall --cask --force '\(caskName)' >/dev/null 2>&1"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", uninstallScript]
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - Upgrading via Homebrew

    public func upgradeViaHomebrew(caskName: String? = nil) async -> UpgradeExecutionResult {
        guard let brewPath = Self.findBrewExecutablePath() else {
            return .homebrewNotFound
        }

        let targetCask = caskName ?? availableUpdate?.caskName ?? ReleaseChannel.channel(for: currentVersion).caskName

        isUpgrading = true
        upgradeStatusMessage = NSLocalizedString("update_progress_title", comment: "")

        let result = await Task.detached { () -> UpgradeExecutionResult in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: brewPath)
            process.arguments = ["upgrade", "--cask", targetCask]

            var env = ProcessInfo.processInfo.environment
            let standardPaths = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
            if let currentPath = env["PATH"] {
                env["PATH"] = "\(standardPaths):\(currentPath)"
            } else {
                env["PATH"] = standardPaths
            }
            process.environment = env

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            do {
                try process.run()
                process.waitUntilExit()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let outputStr = String(data: outputData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    return .success
                } else {
                    return .commandFailed(exitCode: process.terminationStatus, output: outputStr)
                }
            } catch {
                return .commandFailed(exitCode: -1, output: error.localizedDescription)
            }
        }.value

        isUpgrading = false
        upgradeStatusMessage = nil

        if result == .success {
            self.availableUpdate = nil
            // Relaunch the upgraded app automatically
            relaunchApplication()
        }

        return result
    }

    // MARK: - App Relaunch Helper

    public func relaunchApplication() {
        let bundleURL = Bundle.main.bundleURL

        // Dispatch a detached task that waits 1 second and then opens the app
        let relaunchScript = "sleep 1.2 && open '\(bundleURL.path)'"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", relaunchScript]
        try? process.run()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApplication.shared.terminate(nil)
        }
    }

    // MARK: - User Notification

    private func notifyUserOfAvailableUpdate(_ update: UpdateInfo) {
        NotificationManager.shared.showNotification(
            id: "macmirror-update-\(update.availableVersion)",
            appName: "MacMirror",
            title: NSLocalizedString("update_notification_title", comment: ""),
            text: String(format: NSLocalizedString("update_notification_body", comment: ""), update.availableVersion),
            appIconBase64: nil
        )
    }
}
