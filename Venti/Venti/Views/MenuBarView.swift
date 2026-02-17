import SwiftUI

struct MenuBarView: View {
    let state: AppState
    let onToggle: (Bool) -> Void
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    private var limiterBinding: Binding<Bool> {
        Binding(
            get: { state.limiterRunning },
            set: { onToggle($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Toggle row
            HStack {
                Text("Carbon-aware battery limit:  ").bold()
                + Text("\(state.limiterRunning ? "ON" : "OFF")")
                    .font(.system(.body, design: .monospaced))
                + Text(" ")
                + Text("(\(state.targetPercentage)%)")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Toggle("", isOn: limiterBinding)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 5)

            menuDivider

            // Status rows
            statusRow("Battery: \(state.batteryStatusText)", systemImage: batteryIcon)
            statusRow("Power: \(state.chargingStatusText)", systemImage: "powerplug")
            statusRow("Carbon Intensity: \(state.carbonStatusText)", systemImage: "leaf")

            menuDivider

            // About submenu
            Menu {
                Button("Check for updates", systemImage: "arrow.clockwise") {
                    openURL(Constants.releasesURL)
                }
                Button("User manual", systemImage: "book") {
                    openURL(Constants.readmeURL)
                }
                Button("Help and feature requests", systemImage: "questionmark.circle") {
                    openURL(Constants.issuesURL)
                }
            } label: {
                (Text("\(Image(systemName: "info.circle"))") + Text("   About Venti"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .menuStyle(.borderlessButton)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)

            menuButton("Settings...", systemImage: "gearshape") {
                onOpenSettings()
            }

            menuButton("Quit", systemImage: "xmark.rectangle") {
                onQuit()
            }
        }
        .padding(.vertical, 5)
        .frame(width: 380)
    }

    private var batteryIcon: String {
        switch state.batteryPercentage {
        case 96...: "battery.100percent"
        case 63..<96: "battery.75percent"
        case 38..<63: "battery.50percent"
        case 13..<38: "battery.25percent"
        default: "battery.0percent"
        }
    }

    // MARK: - Components

    private var menuDivider: some View {
        Divider().padding(.vertical, 5).padding(.horizontal, 10)
    }

    private func statusRow(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .labelStyle(MenuItemLabelStyle())
            .foregroundStyle(.secondary)
            .font(.body)
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
    }

    private func menuButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        MenuBarButton(title: title, systemImage: systemImage, action: action)
    }

    private func openURL(_ string: String) {
        if let url = URL(string: string) {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Hover-highlighted menu button

private struct MenuBarButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void
    @State private var isHovered = false
    @State private var isClicked = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            isClicked = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
                isClicked = false
                action()
            }
        } label: {
            Label(title, systemImage: systemImage)
                .labelStyle(MenuItemLabelStyle())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
                .padding(.horizontal, 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isHovered && !isClicked ? hoverColor : .clear)
                .padding(.horizontal, 5)
        )
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var hoverColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.1)
            : Color.black.opacity(0.08)
    }
}

// MARK: - Fixed-width icon label style

private struct MenuItemLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.icon
                .frame(width: 16, alignment: .center)
            configuration.title
        }
    }
}
