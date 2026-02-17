import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @State var state: AppState
    @State private var launchAtLogin = false
    @State private var targetInput: Int = 80
    @State private var apiKeyInput = ""
    @State private var regionInput = ""

    var body: some View {
        Form {
            Section("Battery") {
                Stepper(value: $targetInput, in: 20...100) {
                    Text("Target:  ") + Text("\(targetInput)%").font(.system(.body, design: .monospaced)).tracking(1.2)
                }
            }

            Section("Carbon Intensity") {
                SecureField("API Key", text: $apiKeyInput)
                TextField("Fixed Region (leave empty for auto)", text: $regionInput)
                    .textFieldStyle(.roundedBorder)
                Text("Get a free API key at [electricitymaps.com](\(Constants.electricityMapsURL))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("System") {
                Toggle("Launch at Login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, newValue in
                        setLaunchAtLogin(newValue)
                    }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .frame(width: 380)
        .onAppear {
            targetInput = state.targetPercentage
            apiKeyInput = state.apiToken
            regionInput = state.fixedRegion
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onChange(of: targetInput) { _, newValue in
            state.targetPercentage = newValue
        }
        .onChange(of: apiKeyInput) { _, newValue in
            state.apiToken = newValue
        }
        .onChange(of: regionInput) { _, newValue in
            state.fixedRegion = newValue
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Silently handle — user can retry
        }
    }
}
