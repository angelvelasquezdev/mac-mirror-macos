# MacMirror for macOS

<p align="center">
  <strong>Native, lightweight macOS Menu Bar app for mirroring Android notifications over local Wi-Fi.</strong>
</p>

<p align="center">
  <a href="README.md">English</a> • <a href="README.es.md">Español</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-macOS%2014.0%2B%20(Sonoma%20%2F%20Sequoia)-000000?style=flat-square&logo=apple&logoColor=white" alt="macOS Version" />
  <img src="https://img.shields.io/badge/Language-Swift%205.9%2B-FA7343?style=flat-square&logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/UI-SwiftUI-0071e3?style=flat-square&logo=swift&logoColor=white" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Architecture-Universal%20(Apple%20Silicon%20%2F%20Intel)-666666?style=flat-square" alt="Architecture" />
  <img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="License: MIT" />
  <a href="https://github.com/angelvelasquezdev/mac-mirror-android"><img src="https://img.shields.io/badge/Companion%20App-Android%20Client-3DDC84?style=flat-square&logo=android&logoColor=white" alt="Android Repo" /></a>
</p>

---

## Overview

**MacMirror for macOS** is the desktop receiver app for MacMirror. It sits quietly in your macOS Menu Bar, receives notifications streamed from your paired Android phone, and displays them as native macOS system alerts with rich app icons and sounds.

Engineered with **SwiftUI** following **Apple Human Interface Guidelines**, it features a translucent glassmorphic popover, instant pairing, history log, and frictionless zero-cloud networking.

> [!IMPORTANT]
> This app requires the companion Android mobile client to function:
> 👉 **[MacMirror for Android Repository](https://github.com/angelvelasquezdev/mac-mirror-android)**

---

## ✨ Features

- 🖥 **Native Menu Bar Experience**: Always accessible from your status bar. A clean glass popover displays paired device status, IP address, and a chronological history of recent notifications.
- 🔔 **Native macOS System Notifications**: Alerts are delivered directly via `UNUserNotificationCenter` with sound, banner alerts, and rich thumbnails of the originating Android app icon.
- 🔒 **End-to-End Encryption (E2EE)**:
  - Cryptographic 6-digit one-time PIN authentication.
  - Ephemeral Curve P-256 (ECDH) key negotiation via Apple's native `CryptoKit`.
  - AES-256-GCM payload decryption on incoming streams.
- ⚡ **100% Local & Private**: Embedded HTTP server (`:50001`) and WebSocket server (`:50002`). Publishes via **Bonjour / mDNS** (`_macmirror._tcp`) for instant zero-configuration pairing. No external servers or cloud accounts required.
- 🛡 **Silent & Frictionless Storage**: Session keys are stored in private application storage (`~/Library/Application Support/MacMirror/`) with strict POSIX permissions `0600`, completely avoiding annoying system Keychain password prompts during builds and updates.
- 🔄 **Bidirectional Unpairing**: Unpairing from macOS automatically disconnects the Android client and regenerates a fresh pairing PIN.
- 🌐 **Full Internationalization (i18n)**: Native string catalogs supporting English and Spanish.

---

## 🏗 Architecture & Networking

```
┌─────────────────────────────────────────────────────────────┐
│                    MacMirror (macOS)                        │
├────────────────────────┬────────────────────────────────────┤
│ Bonjour (mDNS)         │ Broadcasts _macmirror._tcp:50001   │
│ HTTP Server (:50001)   │ /pair/start, /pair/verify, /status │
│ WebSocket (:50002)     │ Real-time encrypted event stream   │
│ CryptoKit              │ ECDH P-256 & AES-256-GCM engine    │
│ UserNotifications      │ Native banner alerts & sound       │
└────────────────────────┴────────────────────────────────────┘
```

1. **Discovery**: On launch, `BonjourPublisher` advertises the service over the local network using `NetService`.
2. **Key Agreement**: The Android client discovers the Mac, fetches the ephemeral public key, and verifies the 6-digit PIN shown on the Mac menu bar.
3. **Stream Handling**: The `WebSocketServer` accepts the connection and dispatches incoming encrypted packets to `MacOSCrypto`, decrypting the notification contents before passing them to `NotificationManager` for native presentation.

---

## 📋 Requirements

- **Operating System**: macOS 14.0 (Sonoma) or macOS 15.0+ (Sequoia).
- **Architecture**: Apple Silicon (M1/M2/M3/M4) or Intel x86_64.
- **Development Tool**: Xcode 15.0 or later.
- **Local Network**: Mac and Android device must be on the same local Wi-Fi or subnet.

---

## 🚀 Building & Running

### 1. Clone the Repository
```bash
git clone https://github.com/angelvelasquezdev/mac-mirror-macos.git
cd mac-mirror-macos
```

### 2. Open and Build with Xcode
```bash
open MacMirror.xcodeproj
```
- Select the `MacMirror` scheme.
- Press `Cmd + R` to build and run.

### 3. Build from Terminal
```bash
xcodebuild -project MacMirror.xcodeproj -scheme MacMirror -configuration Release build
```

---

## 🔗 Related Projects

| Project | Description | Repository |
| :--- | :--- | :--- |
| **MacMirror (Android)** | Android mobile companion client | [angelvelasquezdev/mac-mirror-android](https://github.com/angelvelasquezdev/mac-mirror-android) |

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2026 Ángel Velásquez
