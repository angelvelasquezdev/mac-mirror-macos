import SwiftUI
import AppKit

public enum GlassAlertIcon: Sendable {
    case appIcon
    case warningWithAppIcon
    case system(String, Color)
}

public struct GlassAlertButton: Identifiable, Sendable {
    public let id = UUID()
    public let title: String
    public let role: Role
    public let action: @MainActor @Sendable () -> Void

    public enum Role: Sendable {
        case regular
        case primary
        case destructive
        case cancel
    }

    public init(title: String, role: Role = .regular, action: @escaping @MainActor @Sendable () -> Void) {
        self.title = title
        self.role = role
        self.action = action
    }
}

public struct GlassAlertView: View {
    let title: String
    let message: String
    let icon: GlassAlertIcon
    let buttons: [GlassAlertButton]
    @Environment(\.colorScheme) var colorScheme

    public init(
        title: String,
        message: String,
        icon: GlassAlertIcon = .appIcon,
        buttons: [GlassAlertButton]
    ) {
        self.title = title
        self.message = message
        self.icon = icon
        self.buttons = buttons
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Icon
            iconView
                .padding(.top, 24)

            // Text Hierarchy
            VStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 8)

            // Action Buttons
            HStack(spacing: 10) {
                ForEach(buttons) { btn in
                    buttonView(for: btn)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
        }
        .frame(width: 320, height: 250)
        .liquidGlass(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.15), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.12 : 0.4), radius: 24, y: 12)
    }

    @ViewBuilder
    private var iconView: some View {
        switch icon {
        case .appIcon:
            if let appIcon = NSImage(named: NSImage.applicationIconName) {
                Image(nsImage: appIcon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 60, height: 60)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .shadow(color: Color.black.opacity(0.12), radius: 4, y: 2)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .frame(width: 60, height: 60)
                    Image(systemName: "bell.and.waves.left.and.right.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
            }

        case .warningWithAppIcon:
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 54, height: 50)
                    .foregroundColor(.yellow)
                    .shadow(color: Color.yellow.opacity(0.3), radius: 4)

                if let appIcon = NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .offset(x: 6, y: 6)
                        .shadow(color: Color.black.opacity(0.2), radius: 2)
                }
            }
            .frame(width: 64, height: 56)

        case .system(let name, let color):
            ZStack {
                Circle()
                    .fill(color.opacity(0.15))
                    .frame(width: 60, height: 60)
                Image(systemName: name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(color)
            }
        }
    }

    @ViewBuilder
    private func buttonView(for btn: GlassAlertButton) -> some View {
        Button(action: btn.action) {
            Text(btn.title)
                .font(.system(size: 12, weight: btn.role == .cancel ? .medium : .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 32)
        }
        .applyButtonStyle(role: btn.role)
        .keyboardShortcut(btn.role == .cancel ? .cancelAction : (btn.role == .primary || btn.role == .destructive ? .defaultAction : nil))
    }
}

private extension View {
    @ViewBuilder
    func applyButtonStyle(role: GlassAlertButton.Role) -> some View {
        if #available(macOS 26.0, *) {
            switch role {
            case .destructive:
                self.buttonStyle(.glassProminent)
                    .tint(.red)
            case .primary:
                self.buttonStyle(.glassProminent)
            case .regular, .cancel:
                self.buttonStyle(.glass)
            }
        } else {
            switch role {
            case .destructive:
                self.buttonStyle(.borderedProminent)
                    .tint(.red)
            case .primary:
                self.buttonStyle(.borderedProminent)
            case .regular, .cancel:
                self.buttonStyle(.bordered)
            }
        }
    }
}
