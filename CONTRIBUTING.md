# Contributing to MacMirror for macOS 🍏

Thank you for your interest in contributing to **MacMirror for macOS**! We welcome bug reports, feature proposals, localization contributions, and pull requests.

---

## 🗺️ Roadmap & Where to Start

Looking for something to work on?
- Check open issues tagged with [`good first issue`](https://github.com/angelvelasquezdev/mac-mirror-macos/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) and [`help wanted`](https://github.com/angelvelasquezdev/mac-mirror-macos/issues?q=is%3Aissue+is%3Aopen+label%3A%22help+wanted%22).
- Planned features:
  - 🔋 Battery percentage indicator from paired Android phone.
  - ⌨️ Global keyboard shortcut to toggle Menu Bar popover.
  - 🗑️ Clear individual or all notification history entries.
  - 🌐 Additional localizations (French, German, Portuguese, Italian, Japanese).
  - 💬 Quick actions / inline notification dismissal.

---

## 🛠️ Development Setup

### Prerequisites
- macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
- Xcode 15.0 or later.
- Swift 5.9+.

### Getting the Code
\`\`\`bash
git clone https://github.com/angelvelasquezdev/mac-mirror-macos.git
cd mac-mirror-macos
open MacMirror.xcodeproj
\`\`\`

### Running Locally without Paid Apple Developer Account
1. Open the project in Xcode.
2. Under **Signing & Capabilities**:
   - Change the Bundle Identifier or select your **Personal Team** in the Team dropdown.
   - Choose **Sign to Run Locally**.
3. Select your Mac as the run destination.
4. Press \`Cmd + R\` to build and launch the Menu Bar app.

---

## 📐 Project Architecture

- \`MacMirrorApp.swift\`: App lifecycle and \`MenuBarExtra\` / Status Item management.
- \`ContentView.swift\`: SwiftUI glassmorphic popover UI following Apple Human Interface Guidelines.
- \`UI/MenuBarViewModel.swift\`: State store binding network events, pairing PIN, and notification history.
- \`Network/BonjourPublisher.swift\`: Local mDNS discovery broadcasting \`_macmirror._tcp\`.
- \`Network/HTTPServer.swift\`: Embedded HTTP server for pairing negotiation (\`/pair/start\`, \`/pair/verify\`).
- \`Network/WebSocketServer.swift\`: WebSocket stream receiver for real-time encrypted notifications.
- \`Security/macOSCrypto.swift\`: ECDH P-256 key agreement and AES-256-GCM decryption engine using native \`CryptoKit\`.
- \`Notifications/NotificationManager.swift\`: Dispatches native banner alerts via \`UNUserNotificationCenter\`.

---

## 🌐 Internationalization (i18n)

MacMirror strictly forbids hardcoded UI strings:
- All visible user-facing text must be declared in string catalogs:
  - \`en.lproj/Localizable.strings\` (English default)
  - \`es.lproj/Localizable.strings\` (Spanish)
- When adding new keys, update all supported locale files.

---

## 🔀 Submitting a Pull Request

1. **Fork the repo** and create your branch from \`main\`:
   \`\`\`bash
   git checkout -b feat/your-feature-name
   \`\`\`
2. **Follow Apple Swift style guidelines**:
   - Clean SwiftUI patterns, avoid force unwrapping (\`!\`), prefer strong typing.
3. **Commit clearly**:
   - Follow Conventional Commits: \`feat: ...\`, \`fix: ...\`, \`docs: ...\`, \`refactor: ...\`.
4. **Test your changes**:
   - Ensure the project builds cleanly (\`Cmd + B\`) and unit tests pass (\`Cmd + U\`).
5. **Open a Pull Request**:
   - Reference any related issue (e.g. \`Closes #1\`).
