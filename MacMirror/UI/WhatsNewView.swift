import SwiftUI

public struct WhatsNewFeatureItem: Identifiable, Sendable {
    public let id: String
    public let iconName: String
    public let iconColor: Color
    public let titleKey: String
    public let descriptionKey: String

    public init(
        id: String,
        iconName: String,
        iconColor: Color,
        titleKey: String,
        descriptionKey: String
    ) {
        self.id = id
        self.iconName = iconName
        self.iconColor = iconColor
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
    }
}

public struct WhatsNewRelease: Sendable {
    public let version: String
    public let items: [WhatsNewFeatureItem]

    public init(version: String, items: [WhatsNewFeatureItem]) {
        self.version = version
        self.items = items
    }
}

public struct WhatsNewCatalog {
    public static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: "1.2",
            items: [
                WhatsNewFeatureItem(
                    id: "autostart",
                    iconName: "power",
                    iconColor: Color.orange,
                    titleKey: "whats_new_autostart_title",
                    descriptionKey: "whats_new_autostart_desc"
                ),
                WhatsNewFeatureItem(
                    id: "low_latency",
                    iconName: "bolt.horizontal.fill",
                    iconColor: Color.blue,
                    titleKey: "whats_new_low_latency_title",
                    descriptionKey: "whats_new_low_latency_desc"
                ),
                WhatsNewFeatureItem(
                    id: "e2ee",
                    iconName: "lock.shield.fill",
                    iconColor: Color.green,
                    titleKey: "whats_new_e2ee_title",
                    descriptionKey: "whats_new_e2ee_desc"
                ),
                WhatsNewFeatureItem(
                    id: "wifi_awareness",
                    iconName: "wifi.exclamationmark",
                    iconColor: Color.orange,
                    titleKey: "whats_new_wifi_awareness_title",
                    descriptionKey: "whats_new_wifi_awareness_desc"
                )
            ]
        )
    ]

    public static func hasHighlights(for version: String) -> Bool {
        return highlights(for: version) != nil
    }

    public static func highlights(for version: String) -> WhatsNewRelease? {
        let cleanVersion = version.trimmingCharacters(in: .whitespacesAndNewlines)
        return releases.first { release in
            cleanVersion == release.version ||
            cleanVersion.hasPrefix(release.version + ".") ||
            cleanVersion.hasPrefix(release.version + "-") ||
            release.version.hasPrefix(cleanVersion + ".")
        }
    }

    public static var latestRelease: WhatsNewRelease? {
        releases.first
    }
}

public struct WhatsNewView: View {
    let release: WhatsNewRelease
    let onDismiss: () -> Void
    @Environment(\.colorScheme) var colorScheme

    public init(release: WhatsNewRelease? = nil, onDismiss: @escaping () -> Void) {
        let currentVer = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2.0"
        self.release = release ?? WhatsNewCatalog.highlights(for: currentVer) ?? WhatsNewCatalog.latestRelease ?? WhatsNewRelease(version: currentVer, items: [])
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.16))
                        .frame(width: 56, height: 56)

                    Image(systemName: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.accentColor)
                }
                .liquidGlass(.tinted(Color.accentColor), in: Circle())
                .padding(.top, 28)

                VStack(spacing: 6) {
                    Text(NSLocalizedString("whats_new_title", comment: ""))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundColor(.primary)

                    Text(String(format: NSLocalizedString("whats_new_version_badge", comment: ""), release.version))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .liquidGlass(.clear, in: Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                        )
                }
            }
            .padding(.horizontal, 24)

            Divider()
                .opacity(0.12)
                .padding(.top, 16)
                .padding(.bottom, 14)

            // Features list
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 16) {
                    ForEach(release.items) { item in
                        HStack(alignment: .top, spacing: 14) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(item.iconColor.opacity(0.15))
                                    .frame(width: 38, height: 38)

                                Image(systemName: item.iconName)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(item.iconColor)
                            }
                            .liquidGlass(.tinted(item.iconColor), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                            VStack(alignment: .leading, spacing: 3) {
                                Text(NSLocalizedString(item.titleKey, comment: ""))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(.primary)

                                Text(NSLocalizedString(item.descriptionKey, comment: ""))
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .lineSpacing(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 6)
            }

            Spacer(minLength: 10)

            Divider()
                .opacity(0.12)
                .padding(.bottom, 16)

            // Action Button
            Button(action: onDismiss) {
                Text(NSLocalizedString("whats_new_continue", comment: ""))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
            }
            .applyWhatsNewButtonStyle()
            .padding(.horizontal, 24)
            .padding(.bottom, 22)
            .keyboardShortcut(.defaultAction)
        }
        .frame(width: 380, height: 500)
        .liquidGlass(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color.primary.opacity(colorScheme == .light ? 0.08 : 0.16), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(colorScheme == .light ? 0.14 : 0.4), radius: 28, y: 14)
    }
}

private extension View {
    @ViewBuilder
    func applyWhatsNewButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
                .controlSize(.regular)
        }
    }
}
