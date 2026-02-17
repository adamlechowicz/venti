import SwiftUI
import os

struct SetupView: View {
    @State var state: AppState
    @State private var step: SetupStep = .welcome
    @State private var apiKeyInput = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    let onComplete: () -> Void

    private let logger = Logger.setup

    enum SetupStep {
        case welcome
        case installingSMC
        case apiKey
        case done
    }

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case .welcome:
                welcomeStep
            case .installingSMC:
                installingStep
            case .apiKey:
                apiKeyStep
            case .done:
                doneStep
            }
        }
        .frame(width: 450, height: 300)
        .padding(30)
    }

    private var welcomeStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "leaf.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Welcome to Venti")
                .font(.title)
            Text("Venti needs to install some components to control your battery. It will ask for your password.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Continue") {
                step = .installingSMC
                Task { await installComponents() }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var installingStep: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
            Text("Installing components...")
                .font(.title3)
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
                Button("Retry") {
                    self.errorMessage = nil
                    Task { await installComponents() }
                }
            }
        }
    }

    private var apiKeyStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Electricity Maps API Key")
                .font(.title2)
            Text("Venti needs a free API key to fetch carbon intensity data.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Link("Get your free key at electricitymaps.com",
                 destination: URL(string: Constants.electricityMapsURL)!)
                .font(.caption)
            TextField("Paste your API key", text: $apiKeyInput)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                Button("Skip for now") {
                    step = .done
                }
                Spacer()
                Button("Save") {
                    state.apiToken = apiKeyInput
                    step = .done
                }
                .buttonStyle(.borderedProminent)
                .disabled(apiKeyInput.isEmpty)
            }
        }
    }

    private var doneStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Setup Complete")
                .font(.title)
            Text("Venti is ready. You'll find it in your menu bar.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Get Started") {
                state.setupCompleted = true
                onComplete()
                dismiss()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func installComponents() async {
        do {
            try await SetupService.runFullSetup()
            step = .apiKey
        } catch is PrivilegedHelper.PrivilegedError {
            errorMessage = "Setup requires administrator privileges. Please try again."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
