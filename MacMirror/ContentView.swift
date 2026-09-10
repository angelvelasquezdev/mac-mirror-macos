import SwiftUI

// Native macOS visual effect (vibrancy/blur) view wrapper
struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct ContentView: View {
    @ObservedObject var viewModel: MenuBarViewModel = .shared
    @Environment(\.colorScheme) var colorScheme
    @State private var copiedPin: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Apple Control Center-style Header
            HeaderView(
                localIP: viewModel.localIP,
                isPaired: viewModel.isPaired,
                isConnected: viewModel.isPaired && viewModel.isClientConnected,
                onSendTestNotification: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        viewModel.triggerRemoteTestNotification()
                    }
                },
                onUnpair: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        viewModel.unpair()
                    }
                },
                onQuit: {
                    NSApplication.shared.terminate(nil)
                }
            )
            
            Divider()
                .opacity(0.12)

            if viewModel.remoteTestStatus != .idle {
                RemoteTestStatusBannerView(status: viewModel.remoteTestStatus)
            }

            if !viewModel.notificationPermissionGranted {
                NotificationPermissionWarningView()
            }

            // Main Content Area
            Group {
                if viewModel.isPaired {
                    PairedView(
                        pairedDevice: viewModel.pairedDeviceName ?? NSLocalizedString("fallback_android_device", comment: ""),
                        localIP: viewModel.localIP,
                        notifications: viewModel.recentNotifications,
                        onClearAll: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.clearAllNotifications()
                            }
                        }
                    )
                } else {
                    UnpairedView(
                        pin: viewModel.pairingPin,
                        localIP: viewModel.localIP,
                        copiedPin: $copiedPin,
                        onRegenerate: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                viewModel.generateNewPin()
                            }
                        }
                    )
                }
            }
            .frame(maxHeight: .infinity)
        }
        .frame(width: 360, height: 520)
        // macOS translucent vibrancy background
        .background(VisualEffectView(material: .popover, blendingMode: .behindWindow))
        .background(colorScheme == .light ? Color.white.opacity(0.35) : Color.black.opacity(0.2))
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: viewModel.isPaired)
    }
}

// MARK: - Remote Test Status Banner

struct RemoteTestStatusBannerView: View {
    let status: MenuBarViewModel.RemoteTestStatus
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            switch status {
            case .idle:
                EmptyView()
            case .requesting:
                ProgressView()
                    .controlSize(.mini)
                Text(NSLocalizedString("remote_test_requesting", comment: ""))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            case .success(let msg):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(colorScheme == .light ? Color(red: 0.11, green: 0.52, blue: 0.20) : Color(nsColor: .systemGreen))
                    .font(.system(size: 11))
                Text(msg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            case .error(let msg):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 11))
                Text(msg)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.primary)
            }
            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(borderColor, lineWidth: 0.8)
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var backgroundColor: Color {
        switch status {
        case .requesting:
            return Color.accentColor.opacity(0.12)
        case .success:
            return Color.green.opacity(0.12)
        case .error:
            return Color.orange.opacity(0.12)
        case .idle:
            return Color.clear
        }
    }

    private var borderColor: Color {
        switch status {
        case .requesting:
            return Color.accentColor.opacity(0.25)
        case .success:
            return Color.green.opacity(0.25)
        case .error:
            return Color.orange.opacity(0.25)
        case .idle:
            return Color.clear
        }
    }
}

// MARK: - Notification Permission Warning Banner

struct NotificationPermissionWarningView: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.system(size: 13))

            VStack(alignment: .leading, spacing: 2) {
                Text(NSLocalizedString("permission_warning_title", comment: ""))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.primary)
                Text(NSLocalizedString("permission_warning_desc", comment: ""))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Button(action: {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Text(NSLocalizedString("permission_warning_button", comment: ""))
                    .font(.system(size: 9, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.orange.opacity(0.25), lineWidth: 0.8)
        )
        .padding(.horizontal, 14)
        .padding(.top, 8)
    }
}

// MARK: - Header View (Control Center Inspired)

struct HeaderView: View {
    let localIP: String
    let isPaired: Bool
    let isConnected: Bool
    let onSendTestNotification: () -> Void
    let onUnpair: () -> Void
    let onQuit: () -> Void

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }

    private var appBuild: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    private func openAboutPanel() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            NSApplication.AboutPanelOptionKey.applicationName: NSLocalizedString("app_name", comment: ""),
            NSApplication.AboutPanelOptionKey.applicationVersion: appVersion,
            NSApplication.AboutPanelOptionKey.version: appBuild
        ])
    }

    var body: some View {
        HStack(spacing: 10) {
            // App Icon / Symbol
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: 30, height: 30)
                Image(systemName: "bell.and.waves.left.and.right.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            
            VStack(alignment: .leading, spacing: 1) {
                Text(NSLocalizedString("app_name", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                Text(String(format: NSLocalizedString("ip_format", comment: ""), localIP))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // High-Contrast Connection Status Pill (Green when active client is syncing, Orange when waiting)
            StatusBadgeView(isOnline: isPaired ? isConnected : false)
            
            // Contextual Actions Menu (Apple style ...)
            Menu {
                Text(String(format: NSLocalizedString("menu_app_version", comment: ""), appVersion, appBuild))

                Button(action: openAboutPanel) {
                    Label(NSLocalizedString("menu_about", comment: ""), systemImage: "info.circle")
                }

                Divider()

                Button(action: onSendTestNotification) {
                    Label(NSLocalizedString("menu_send_test", comment: ""), systemImage: "bell.badge")
                }
                
                Divider()
                
                if isPaired {
                    Button(role: .destructive, action: onUnpair) {
                        Label(NSLocalizedString("menu_unpair", comment: ""), systemImage: "link.badge.plus")
                    }
                    Divider()
                }
                
                Button(action: onQuit) {
                    Label(NSLocalizedString("menu_quit", comment: ""), systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.secondary)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - High-Contrast Status Badge

struct StatusBadgeView: View {
    let isOnline: Bool
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        // High-contrast colors for WCAG AA compliance (> 4.5:1) in both light and dark modes
        let foregroundColor: Color = {
            if colorScheme == .light {
                return isOnline ? Color(red: 0.11, green: 0.52, blue: 0.20) : Color(red: 0.72, green: 0.38, blue: 0.0)
            } else {
                return isOnline ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)
            }
        }()

        let backgroundColor: Color = {
            if colorScheme == .light {
                return isOnline ? Color(red: 0.11, green: 0.52, blue: 0.20).opacity(0.14) : Color(red: 0.72, green: 0.38, blue: 0.0).opacity(0.14)
            } else {
                return (isOnline ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange)).opacity(0.16)
            }
        }()

        let labelKey = isOnline ? "status_connected" : "status_waiting"

        HStack(spacing: 5) {
            Circle()
                .fill(foregroundColor)
                .frame(width: 6, height: 6)
                .shadow(color: foregroundColor.opacity(0.4), radius: 2)
            
            Text(NSLocalizedString(labelKey, comment: ""))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(foregroundColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(backgroundColor)
        )
        .overlay(
            Capsule()
                .stroke(foregroundColor.opacity(colorScheme == .light ? 0.35 : 0.2), lineWidth: 0.8)
        )
    }
}

// MARK: - Paired View

struct PairedView: View {
    let pairedDevice: String
    let localIP: String
    let notifications: [MenuBarViewModel.NotificationLog]
    let onClearAll: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 12) {
            // Device Connection Inset Card
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 34, height: 34)
                    Image(systemName: "iphone.radiowaves.left.and.right")
                        .font(.system(size: 16))
                        .foregroundColor(.accentColor)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("header_paired_phone", comment: ""))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                    Text(pairedDevice)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                }
                
                Spacer()
                
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(colorScheme == .light ? Color(red: 0.11, green: 0.52, blue: 0.20) : Color(nsColor: .systemGreen))
                    .font(.system(size: 14))
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .light ? 0.6 : 0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Notifications Header with Clear All
            HStack {
                Text(NSLocalizedString("header_recent_notifications", comment: ""))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
                
                if !notifications.isEmpty {
                    Text("\(notifications.count)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(Capsule())
                }
                
                Spacer()
                
                if !notifications.isEmpty {
                    Button(action: onClearAll) {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text(NSLocalizedString("button_clear", comment: ""))
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)

            // Notifications List
            if notifications.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bell.slash")
                        .font(.system(size: 30, weight: .light))
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(NSLocalizedString("empty_notifications_title", comment: ""))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)
                    Text(NSLocalizedString("empty_notifications_desc", comment: ""))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 8) {
                        ForEach(notifications) { log in
                            NotificationRow(log: log)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 14)
                }
            }
        }
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let log: MenuBarViewModel.NotificationLog
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Dynamic App Icon or High-contrast Fallback
            if let base64 = log.appIconBase64,
               let data = Data(base64Encoded: base64),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .shadow(color: Color.black.opacity(0.08), radius: 1, y: 1)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)
                    Image(systemName: "bell.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.accentColor)
                }
            }
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(log.appName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.primary)
                    Spacer()
                    Text(log.timestamp, style: .time)
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.secondary)
                }
                
                if !log.title.isEmpty {
                    Text(log.title)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                }
                
                if !log.text.isEmpty {
                    Text(log.text)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(colorScheme == .light ? 0.7 : 0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

// MARK: - Unpaired View

struct UnpairedView: View {
    let pin: String
    let localIP: String
    @Binding var copiedPin: Bool
    let onRegenerate: () -> Void
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            
            // Hero Icon
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 60, height: 60)
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 26))
                    .foregroundColor(.accentColor)
            }
            
            VStack(spacing: 6) {
                Text(NSLocalizedString("connect_phone_title", comment: ""))
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(NSLocalizedString("connect_phone_desc", comment: ""))
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // PIN Display (Apple Style 3+3 Digits)
            VStack(spacing: 8) {
                Text(formatPin(pin))
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .tracking(6)
                    .foregroundColor(.primary)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(colorScheme == .light ? 0.06 : 0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
                    )
                
                // Copy PIN to clipboard button
                Button(action: {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(pin, forType: .string)
                    copiedPin = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copiedPin = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: copiedPin ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10))
                        Text(copiedPin ? NSLocalizedString("button_copied", comment: "") : NSLocalizedString("button_copy_code", comment: ""))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(copiedPin ? (colorScheme == .light ? Color(red: 0.11, green: 0.52, blue: 0.20) : Color(nsColor: .systemGreen)) : .accentColor)
                }
                .buttonStyle(.plain)
            }

            // Action: Regenerate PIN
            Button(action: onRegenerate) {
                Label(NSLocalizedString("button_generate_pin", comment: ""), systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            
            Spacer()
            
            // Footer Info
            HStack(spacing: 4) {
                Image(systemName: "wifi")
                    .font(.system(size: 10))
                Text(NSLocalizedString("wifi_notice", comment: ""))
                    .font(.system(size: 10))
            }
            .foregroundColor(.secondary.opacity(0.8))
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formatPin(_ pinStr: String) -> String {
        guard pinStr.count == 6 else { return pinStr }
        let index3 = pinStr.index(pinStr.startIndex, offsetBy: 3)
        return "\(pinStr[..<index3])  \(pinStr[index3...])"
    }
}

#Preview {
    ContentView()
}
