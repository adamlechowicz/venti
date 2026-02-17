import SwiftUI
import os

@main
struct VentiApp: App {
    @State private var appState = AppState()
    @State private var maintainLoop: MaintainLoop?
    @State private var initialized = false
    @Environment(\.openWindow) private var openWindow

    private let logger = Logger(subsystem: Constants.logSubsystem, category: "app")

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                state: appState,
                onToggle: { enabled in
                    if enabled { enableLimiter() } else { disableLimiter() }
                },
                onOpenSettings: {
                    openWindow(id: "settings")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                },
                onQuit: quit
            )
        } label: {
            Image(appState.limiterRunning ? "ActiveTemplate" : "InactiveTemplate")
                .renderingMode(.template)
                .padding(.horizontal, 3)
                .task {
                    guard !initialized else { return }
                    initialized = true
                    await initialize()
                }
        }
        .menuBarExtraStyle(.window)

        Window("Venti Setup", id: "setup") {
            SetupView(state: appState) {
                Task { await initialize() }
            }
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)

        Window("Settings", id: "settings") {
            SettingsView(state: appState)
        }
        .windowResizability(.contentSize)
        .windowStyle(.titleBar)
    }

    // MARK: - Lifecycle

    private func initialize() async {
        ThresholdService.load()

        // Check if first-time setup is needed
        if !appState.setupCompleted || !SetupService.isSMCInstalled() {
            openWindow(id: "setup")
            return
        }

        // Ensure visudo has Tahoe keys (upgrades from v1.x won't have them)
        let visudoOK = await SetupService.isVisudoConfigured()
        if !visudoOK {
            logger.info("Visudo needs updating for Tahoe key support")
            do {
                try await SetupService.configureVisudo()
            } catch {
                logger.error("Failed to update visudo: \(error.localizedDescription)")
            }
        }

        // Detect SMC capabilities
        appState.smcCapabilities = await SMCService.detectCapabilities()

        if appState.smcCapabilities?.canControlCharging != true {
            logger.error("No SMC charging control available")
            return
        }

        // Initialize maintain loop
        let loop = MaintainLoop(state: appState)
        maintainLoop = loop

        // Auto-enable if was previously enabled
        if UserDefaults.standard.bool(forKey: Constants.Defaults.limiterEnabled) {
            appState.limiterEnabled = true
            loop.start()
        }

        // Initial battery status refresh
        let battery = await BatteryService.getStatus()
        appState.batteryPercentage = battery.percentage
        appState.timeRemaining = battery.timeRemaining
        appState.isCharging = battery.isCharging
    }

    private func enableLimiter() {
        logger.info("Enabling battery limiter")
        appState.limiterEnabled = true
        UserDefaults.standard.set(true, forKey: Constants.Defaults.limiterEnabled)
        maintainLoop?.start()
    }

    private func disableLimiter() {
        logger.info("Disabling battery limiter")
        appState.limiterEnabled = false
        UserDefaults.standard.set(false, forKey: Constants.Defaults.limiterEnabled)
        Task {
            await maintainLoop?.stop()
        }
    }

    private func quit() {
        logger.info("Quitting Venti")
        Task {
            await maintainLoop?.stop()
            await MainActor.run {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
