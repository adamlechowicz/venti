import Foundation
import os

/// Async battery management state machine — faithful port of venti.sh maintain_synchronous
@MainActor
final class MaintainLoop {
    private let logger = Logger.loop
    private let state: AppState
    private var task: Task<Void, Never>?

    init(state: AppState) {
        self.state = state
    }

    var isRunning: Bool {
        task != nil && !(task?.isCancelled ?? true)
    }

    func start() {
        guard !isRunning else {
            logger.info("Maintain loop already running")
            return
        }

        state.limiterRunning = true
        task = Task { [weak self] in
            await self?.run()
        }
        logger.info("Maintain loop started")
    }

    func stop() async {
        logger.info("Stopping maintain loop")
        task?.cancel()
        task = nil
        state.limiterRunning = false

        // Re-enable charging on stop (safety measure)
        if let caps = state.smcCapabilities {
            await SMCService.enableCharging(capabilities: caps)
        }
        logger.info("Maintain loop stopped, charging re-enabled")
    }

    // MARK: - Main Loop

    private func run() async {
        guard let caps = state.smcCapabilities else {
            logger.error("No SMC capabilities detected, cannot run maintain loop")
            return
        }

        let target = state.targetPercentage
        var refreshCounter = 0
        var forceCounter = 0

        // Initial carbon intensity fetch
        await refreshCarbon()

        logger.info("Maintaining at \(target)% from \(self.state.batteryPercentage)%, carbon=\(self.state.carbonIntensity)")

        while !Task.isCancelled {
            // Refresh battery status
            let battery = await BatteryService.getStatus()
            state.batteryPercentage = battery.percentage
            state.timeRemaining = battery.timeRemaining
            state.isCharging = battery.isCharging  // physical state for display

            let isCharging = await SMCService.isChargingEnabled(capabilities: caps)  // SMC state for control logic

            let percentage = battery.percentage
            let carbonIntensity = state.carbonIntensity
            let threshold = state.carbonThreshold

            // State machine (matches venti.sh lines 483-510)
            if percentage >= target && isCharging {
                // State 1: Above target and charging → disable
                logger.info("Charge above \(target)%")
                await SMCService.disableCharging(capabilities: caps)
                state.isCharging = false
                forceCounter = 0

            } else if percentage < target && carbonIntensity > threshold && forceCounter >= Constants.forceChargeIterations {
                // State 2: Below target, high carbon, but forced → charge anyway
                logger.info("Charging despite high carbon intensity (forced after \(forceCounter) intervals)")
                await SMCService.enableCharging(capabilities: caps)
                state.isCharging = true
                refreshCounter = Constants.carbonRefreshIterations // trigger carbon refresh next iteration

            } else if percentage < target && carbonIntensity > threshold {
                // State 3: Below target, high carbon → wait
                logger.info("Charge below \(target)%, but carbon too high (\(carbonIntensity) > \(threshold))")
                await SMCService.disableCharging(capabilities: caps)
                state.isCharging = false
                refreshCounter = Constants.carbonRefreshIterations // trigger carbon refresh next iteration
                forceCounter += 1

            } else if percentage < target && carbonIntensity <= threshold && !isCharging {
                // State 4: Below target, low carbon, not charging → enable
                logger.info("Charge below \(target)%")
                await SMCService.enableCharging(capabilities: caps)
                state.isCharging = true
                forceCounter = 0
            }

            // Sleep for loop interval
            try? await Task.sleep(for: .seconds(Constants.loopInterval))

            refreshCounter += 1

            // Refresh carbon intensity periodically
            if refreshCounter >= Constants.carbonRefreshIterations {
                await refreshCarbon()
                refreshCounter = 0
            }
        }

        logger.info("Maintain loop cancelled")
    }

    private func refreshCarbon() async {
        logger.info("Refreshing carbon intensity and location")

        let reading = await CarbonService.fetchCarbonIntensity(
            apiToken: state.apiToken,
            fixedRegion: self.state.fixedRegion.isEmpty ? nil : self.state.fixedRegion
        )

        state.carbonIntensity = reading.intensity
        state.carbonRegion = reading.region
        state.carbonThreshold = ThresholdService.threshold(for: reading.region)

        logger.info("Carbon: \(reading.intensity) gCO2eq/kWh, region: \(reading.region), threshold: \(self.state.carbonThreshold)")
    }
}
