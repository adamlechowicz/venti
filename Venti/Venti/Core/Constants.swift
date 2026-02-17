import Foundation

enum Constants {
    // MARK: - Timing
    static let loopInterval: TimeInterval = 60          // seconds between battery checks
    static let carbonRefreshIterations = 20             // check carbon every ~20 min
    static let forceChargeIterations = 28               // force charge after ~10 hrs high carbon
    static let forceSleepDuration: TimeInterval = 1200  // 20 min sleep during carbon waits

    // MARK: - Defaults
    static let defaultTargetPercentage = 80
    static let defaultThreshold = 1200                  // gCO2eq/kWh (effectively always allow)
    static let defaultRegion = "DEF"

    // MARK: - Paths
    static let smcBinaryPath = "/usr/local/bin/smc"
    static let visudoPath = "/private/etc/sudoers.d/venti"

    // MARK: - API
    static let electricityMapsBaseURL = "https://api.electricitymaps.com/v3/carbon-intensity/latest"
    static let geoLookupURL = "http://ip-api.com/json"
    static let placeholderAPIKey = "1xYYY1xXXX1XXXxXXYyYYxXXyXyyyXXX"  // legacy CO2signal placeholder

    // MARK: - URLs
    static let releasesURL = "https://github.com/adamlechowicz/venti/releases"
    static let readmeURL = "https://github.com/adamlechowicz/venti#readme"
    static let issuesURL = "https://github.com/adamlechowicz/venti/issues"
    static let electricityMapsURL = "https://www.electricitymaps.com/free-tier-api"
    static let setupScriptURL = "https://raw.githubusercontent.com/adamlechowicz/venti/main/setup.sh"

    // MARK: - UserDefaults Keys
    enum Defaults {
        static let targetPercentage = "targetPercentage"
        static let apiToken = "apiToken"
        static let fixedRegion = "fixedRegion"
        static let limiterEnabled = "limiterEnabled"
        static let setupCompleted = "setupCompleted"
        static let lastCarbonIntensity = "lastCarbonIntensity"
        static let lastCarbonRegion = "lastCarbonRegion"
    }

    // MARK: - Logging
    static let logSubsystem = "com.adamlechowicz.venti"
}
