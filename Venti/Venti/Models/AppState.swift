import Foundation
import SwiftUI

@Observable
final class AppState {
    // MARK: - Battery status
    var batteryPercentage: Int = 0
    var timeRemaining: String = "unknown"
    var isCharging: Bool = false

    // MARK: - Carbon
    var carbonIntensity: Int = 0
    var carbonRegion: String = Constants.defaultRegion
    var carbonThreshold: Int = Constants.defaultThreshold

    // MARK: - Limiter
    var limiterEnabled: Bool = false
    var limiterRunning: Bool = false

    // MARK: - SMC
    var smcCapabilities: SMCCapabilities?

    // MARK: - Setup
    var setupCompleted: Bool {
        get { UserDefaults.standard.bool(forKey: Constants.Defaults.setupCompleted) }
        set { UserDefaults.standard.set(newValue, forKey: Constants.Defaults.setupCompleted) }
    }

    // MARK: - Settings (persisted as stored properties for observable tracking)
    var targetPercentage: Int {
        didSet { UserDefaults.standard.set(targetPercentage, forKey: Constants.Defaults.targetPercentage) }
    }

    var apiToken: String {
        didSet { UserDefaults.standard.set(apiToken, forKey: Constants.Defaults.apiToken) }
    }

    var fixedRegion: String {
        didSet { UserDefaults.standard.set(fixedRegion, forKey: Constants.Defaults.fixedRegion) }
    }

    init() {
        let target = UserDefaults.standard.integer(forKey: Constants.Defaults.targetPercentage)
        self.targetPercentage = target > 0 ? target : Constants.defaultTargetPercentage
        self.apiToken = UserDefaults.standard.string(forKey: Constants.Defaults.apiToken) ?? ""
        self.fixedRegion = UserDefaults.standard.string(forKey: Constants.Defaults.fixedRegion) ?? ""
    }

    // MARK: - Computed display strings
    var batteryStatusText: String {
        let noEstimate = timeRemaining == "unknown" || timeRemaining == "(no estimate)"
        if isCharging {
            if noEstimate {
                return "\(batteryPercentage)% (charging)"
            }
            return "\(batteryPercentage)% (\(timeRemaining) until full)"
        }
        if noEstimate {
            return "\(batteryPercentage)%"
        }
        return "\(batteryPercentage)% (\(timeRemaining) until empty)"
    }

    var chargingStatusText: String {
        "SMC charging \(isCharging ? "enabled" : "disabled")"
    }

    var carbonStatusText: String {
        "\(carbonIntensity) gCO2eq/kWh"
    }
}
